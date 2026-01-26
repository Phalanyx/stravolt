package simple

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/teslamotors/fleet-telemetry/datastore/simple/transformers"
	logrus "github.com/teslamotors/fleet-telemetry/logger"
	"github.com/teslamotors/fleet-telemetry/protos"
	"github.com/teslamotors/fleet-telemetry/telemetry"
)

// Config for the protobuf logger
type Config struct {
	// Verbose controls whether types are explicitly shown in the logs. Only applicable for record type 'V'.
	Verbose bool `json:"verbose"`
	// APIEndpoint is the URL to send telemetry data to (optional, defaults to env var STRAVOLT_API_ENDPOINT)
	APIEndpoint string `json:"api_endpoint"`
	// BearerToken is the authentication token (optional, defaults to env var STRAVOLT_BEARER_TOKEN)
	BearerToken string `json:"bearer_token"`
}

// Producer is a simple protobuf logger
type Producer struct {
	Config     *Config
	logger     *logrus.Logger
	httpClient *http.Client
}

// NewProtoLogger initializes the parameters for protobuf payload logging
func NewProtoLogger(config *Config, logger *logrus.Logger) telemetry.Producer {
	config.APIEndpoint = os.Getenv("STRAVOLT_API_ENDPOINT")
	config.BearerToken = os.Getenv("STRAVOLT_BEARER_TOKEN")
	return &Producer{
		Config:     config,
		logger:     logger,
		httpClient: &http.Client{},
	}
}

// Close the producer
func (p *Producer) Close() error {
	return nil
}

// ProcessReliableAck noop method
func (p *Producer) ProcessReliableAck(_ *telemetry.Record) {
}

// Produce sends the data to the logger
func (p *Producer) Produce(entry *telemetry.Record) {
	data, err := p.recordToLogMap(entry, entry.Vin)
	if err != nil {
		p.logger.ErrorLog("record_logging_error", err, logrus.LogInfo{"vin": entry.Vin, "txtype": entry.TxType, "metadata": entry.Metadata()})
		return
	}

	// Prepare the JSON payload
	payload := map[string]interface{}{
		"vin":      entry.Vin,
		"metadata": entry.Metadata(),
		"data":     data,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		p.logger.ErrorLog("json_marshal_error", err, logrus.LogInfo{"vin": entry.Vin})
		return
	}

	// Send HTTP POST request to API endpoint
	req, err := http.NewRequest("POST", p.Config.APIEndpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		p.logger.ErrorLog("http_request_creation_error", err, logrus.LogInfo{"vin": entry.Vin})
		return
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p.Config.BearerToken)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		p.logger.ErrorLog("http_request_error", err, logrus.LogInfo{"vin": entry.Vin, "endpoint": p.Config.APIEndpoint})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		p.logger.ActivityLog("record_sent_successfully", logrus.LogInfo{"vin": entry.Vin, "status": resp.StatusCode})
	} else {
		p.logger.ErrorLog("http_response_error", fmt.Errorf("status code: %d", resp.StatusCode), logrus.LogInfo{"vin": entry.Vin, "status": resp.StatusCode})
	}
}

// ReportError noop method
func (p *Producer) ReportError(_ string, _ error, _ logrus.LogInfo) {
}

// recordToLogMap converts the data of a record to a map or slice of maps
func (p *Producer) recordToLogMap(record *telemetry.Record, vin string) (interface{}, error) {
	switch payload := record.GetProtoMessage().(type) {
	case *protos.Payload:
		return transformers.PayloadToMap(payload, p.Config.Verbose, vin, p.logger), nil
	case *protos.VehicleAlerts:
		alertMaps := make([]map[string]interface{}, len(payload.Alerts))
		for i, alert := range payload.Alerts {
			alertMaps[i] = transformers.VehicleAlertToMap(alert)
		}
		return alertMaps, nil
	case *protos.VehicleErrors:
		errorMaps := make([]map[string]interface{}, len(payload.Errors))
		for i, vehicleError := range payload.Errors {
			errorMaps[i] = transformers.VehicleErrorToMap(vehicleError)
		}
		return errorMaps, nil
	case *protos.VehicleConnectivity:
		return transformers.VehicleConnectivityToMap(payload), nil
	default:
		return nil, fmt.Errorf("unknown txType: %s", record.TxType)
	}
}
