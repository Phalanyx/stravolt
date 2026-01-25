module TeslaFleetErrors
  class TeslaFleetError < StandardError; end
  class VehicleAsleepError < TeslaFleetError; end
  class TokenExpiredError < TeslaFleetError; end
  class VehicleNotFoundError < TeslaFleetError; end
  class ApiUnavailableError < TeslaFleetError; end
end
