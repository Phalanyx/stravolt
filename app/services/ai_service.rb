class AiService
  GEMINI_MODEL = ENV.fetch("GEMINI_MODEL", "gemini-2.0-flash")
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{GEMINI_MODEL}:generateContent"

  class Error < StandardError; end

  def recommend_warmup_time(context_text, timezone: Time.zone.name)
    response = connection.post do |req|
      req.params["key"] = api_key
      req.headers["Content-Type"] = "application/json"
      req.body = request_body(context_text, timezone: timezone).to_json
    end

    raise Error, "Gemini request failed (#{response.status})" unless response.success?

    text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    raise Error, "Gemini returned an empty response" if text.blank?

    parse_warmup_time(text)
  rescue Faraday::Error => e
    raise Error, "Gemini request error: #{e.message}"
  end

  private

  def api_key
    key = ENV["GEMINI_API_KEY"]
    raise Error, "GEMINI_API_KEY is not configured" if key.blank?

    key
  end

  def connection
    @connection ||= Faraday.new(url: GEMINI_URL) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def request_body(context_text, timezone:)
    {
      contents: [
        {
          parts: [
            { text: prompt(context_text, timezone: timezone) }
          ]
        }
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: {
            warmup_at: {
              type: "STRING",
              description: "ISO8601 datetime for the next recommended vehicle warmup, or null if none"
            }
          },
          required: ["warmup_at"]
        }
      }
    }
  end

  def prompt(context_text, timezone:)
    <<~PROMPT
      You analyze Tesla usage data and recommend one vehicle warmup (climate precondition) time.

      Rules:
      - Use trip start times to infer when the owner usually leaves in the morning.
      - Schedule warmup 20-30 minutes before that inferred departure time.
      - Prefer the next upcoming weekday morning unless the data clearly shows weekend usage.
      - Return warmup_at as an ISO8601 datetime in timezone #{timezone}.
      - If there is not enough data to infer a departure pattern, return warmup_at as null.

      Current time: #{Time.current.iso8601}
      Timezone: #{timezone}

      Vehicle data:
      #{context_text}
    PROMPT
  end

  def parse_warmup_time(text)
    payload = JSON.parse(text)
    value = payload["warmup_at"]
    return nil if value.blank? || value.to_s.downcase == "null"

    Time.zone.parse(value)
  rescue ArgumentError, TypeError, JSON::ParserError => e
    raise Error, "Unable to parse Gemini warmup time: #{e.message}"
  end
end
