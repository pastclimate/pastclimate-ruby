# frozen_string_literal: true

require "json"
require "date"
require "uri"

module PastClimate
  # The PastClimate API client. One instance can be shared by many threads.
  #
  #   client = PastClimate::Client.new(api_key: ENV["PASTCLIMATE_API_KEY"])
  #   response = client.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-31")
  #   response.data.first.daily_max_temp
  #   response.credits_remaining
  #
  # Every JSON method returns a Response (+data+, +location+, +meta+, +rate_limit+,
  # +credits_used+, +credits_remaining+). With +format: :csv+ the daily and hourly
  # methods return a CsvResponse instead.
  class Client
    DEFAULT_BASE_URL = "https://api.pastclimate.com"
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_MAX_RETRY_DELAY = 60
    API_KEY_ENV = "PASTCLIMATE_API_KEY"
    BASE_URL_ENV = "PASTCLIMATE_BASE_URL"
    BACKOFF_BASE = 0.5
    UNITS = %w[metric imperial].freeze
    FORMATS = %w[json csv].freeze
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    attr_reader :base_url, :timeout, :max_retries, :max_retry_delay

    # @param api_key [String, nil] your key; falls back to ENV["PASTCLIMATE_API_KEY"]
    # @param base_url [String, nil] defaults to ENV["PASTCLIMATE_BASE_URL"], then https://api.pastclimate.com
    # @param timeout [Numeric] seconds, per connection attempt (default 30)
    # @param max_retries [Integer] retries after the first try (default 2)
    # @param max_retry_delay [Numeric] longest wait, in seconds, the client will sleep
    #   between tries. A 429 whose Retry-After is longer than this is raised, not waited out.
    # @param transport [#call, nil] a custom HTTP transport (see NetHttpTransport)
    # @param sleeper [#call, nil] called with the seconds to wait; for tests
    # @param random [#call, nil] returns a Float in [0, 1) for backoff jitter; for tests
    def initialize(api_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES,
                   max_retry_delay: DEFAULT_MAX_RETRY_DELAY, transport: nil, sleeper: nil, random: nil)
      @api_key = clean_api_key(api_key || ENV[API_KEY_ENV])
      @base_url = clean_base_url(base_url || ENV[BASE_URL_ENV] || DEFAULT_BASE_URL)
      @timeout = positive_number(timeout, "timeout")
      @max_retries = non_negative_integer(max_retries, "max_retries")
      @max_retry_delay = non_negative_number(max_retry_delay, "max_retry_delay")
      @transport = transport || NetHttpTransport.new
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @random = random || -> { rand }
    end

    # The key is never printed.
    def inspect
      "#<PastClimate::Client base_url=#{@base_url.inspect} api_key=[REDACTED]>"
    end
    alias to_s inspect

    # --- Locations ---------------------------------------------------------

    # Search places by the start of their name (free). Returns Response whose
    # data is an Array of LocationSearchResult.
    #
    # @param q [String] the start of a place name
    # @param country [String, nil] limit results to one country (two-letter code)
    def search_locations(q, country: nil)
      raise ArgumentError, "q is required" if q.to_s.strip.empty?

      get("/v1/locations/search", { "q" => q.to_s, "country" => blank_to_nil(country) }) do |data|
        list(data, LocationSearchResult)
      end
    end

    # The place nearest a point, inside one country (free). data is a NearestLocation.
    def nearest_location(lat:, lon:, country:)
      point = Place.point(lat: lat, lon: lon, country: country)
      get("/v1/locations/nearest", {
            "lat" => Place.format_number(lat), "lon" => Place.format_number(lon), "country" => point.country
          }) { |data| NearestLocation.from_hash(data) }
    end

    # One location by id (free). data is a LocationDetail.
    #
    # @param id [String, Place] a location id such as "gb/london"
    def get_location(id)
      place = Place.coerce(id)
      raise ArgumentError, "get_location needs a location id such as \"gb/london\"" if place.country

      country, slug = place.location.split("/", 2)
      raise ArgumentError, "a location id looks like \"gb/london\"" if slug.nil? || country.empty? || slug.empty?

      get("/v1/locations/#{path_segment(country)}/#{path_segment(slug)}") { |data| LocationDetail.from_hash(data) }
    end

    # --- Weather -----------------------------------------------------------

    # Daily weather for each day from +start_date+ to +end_date+, both included.
    # data is an Array of DailyRow, or the CSV text with +format: :csv+.
    #
    # @param location [String, Place]
    # @param start_date [Date, Time, String] first day, YYYY-MM-DD
    # @param end_date [Date, Time, String] last day, YYYY-MM-DD
    # @param units [Symbol, String, nil] :metric (the server default) or :imperial
    # @param format [Symbol, String] :json (default) or :csv
    def get_daily(location, start_date:, end_date:, units: nil, format: :json)
      query = place_query(location).merge(
        "start" => date_param(start_date, "start_date"),
        "end" => date_param(end_date, "end_date"),
        "units" => units_param(units)
      )
      weather_get("/v1/daily", query, format) { |data| list(data, DailyRow) }
    end

    # Hourly weather for +days+ consecutive local days starting at +date+.
    # data is an Array of HourlyRow, or the CSV text with +format: :csv+.
    #
    # @param days [Integer, nil] number of days; leave nil for the server default
    def get_hourly(location, date:, days: nil, units: nil, format: :json)
      query = place_query(location).merge(
        "date" => date_param(date, "date"),
        "days" => days_param(days),
        "units" => units_param(units)
      )
      weather_get("/v1/hourly", query, format) { |data| list(data, HourlyRow) }
    end

    # Convenience for get_daily(..., format: :csv). Returns a CsvResponse.
    def get_daily_csv(location, start_date:, end_date:, units: nil)
      get_daily(location, start_date: start_date, end_date: end_date, units: units, format: :csv)
    end

    # Convenience for get_hourly(..., format: :csv). Returns a CsvResponse.
    def get_hourly_csv(location, date:, days: nil, units: nil)
      get_hourly(location, date: date, days: days, units: units, format: :csv)
    end

    # One row per calendar month (UTC) for the whole archive. data is an Array of MonthlyRow.
    def get_monthly(location, units: nil)
      get("/v1/monthly", place_query(location).merge("units" => units_param(units))) { |data| list(data, MonthlyRow) }
    end

    # One row per calendar year (UTC) for the whole archive. data is an Array of YearlyRow.
    def get_yearly(location, units: nil)
      get("/v1/yearly", place_query(location).merge("units" => units_param(units))) { |data| list(data, YearlyRow) }
    end

    # Climate normals: 12 monthly and 366 day-of-year rows, or only +month+ (1 to 12).
    # data is a NormalsData.
    def get_normals(location, month: nil, units: nil)
      query = place_query(location).merge("month" => month_param(month), "units" => units_param(units))
      get("/v1/normals", query) { |data| NormalsData.from_hash(data) }
    end

    # The hottest, coldest, wettest and windiest day on file. data is an Array of RecordItem.
    def get_records(location, units: nil)
      get("/v1/records", place_query(location).merge("units" => units_param(units))) { |data| list(data, RecordItem) }
    end

    # --- Account -----------------------------------------------------------

    # The countries the archive serves, and the span of published data for each
    # (free). data is a CoverageData.
    def get_coverage(country: nil)
      get("/v1/coverage", { "country" => blank_to_nil(country) }) { |data| CoverageData.from_hash(data) }
    end

    # Your plan, credit balance and limits (free). data is a MeData.
    def get_me
      get("/v1/me") { |data| MeData.from_hash(data) }
    end

    private

    # --- Request plumbing --------------------------------------------------

    def weather_get(path, query, format, &parser)
      if format_param(format) == "csv"
        get_csv(path, query.merge("format" => "csv"))
      else
        get(path, query, &parser)
      end
    end

    def get(path, query = {}, &parser)
      raw = perform(build_url(path, query), request_headers(csv: false))
      parse_envelope(raw, parser)
    end

    def get_csv(path, query)
      raw = perform(build_url(path, query), request_headers(csv: true))
      CsvResponse.new(csv: raw.body.to_s, status: raw.status, headers: Headers.normalize(raw.headers))
    end

    def request_headers(csv:)
      {
        "Authorization" => "Bearer #{@api_key}",
        "Accept" => csv ? "text/csv, application/json;q=0.9" : "application/json",
        "User-Agent" => "pastclimate-ruby/#{VERSION}"
      }
    end

    def build_url(path, query)
      pairs = query.reject { |_name, value| value.nil? }
      text = pairs.map { |name, value| "#{query_component(name)}=#{query_component(value)}" }.join("&")
      "#{@base_url}#{path}#{text.empty? ? '' : "?#{text}"}"
    end

    def query_component(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def path_segment(value)
      query_component(value)
    end

    # Sends the request, retrying where it is safe. Returns the 2xx TransportResponse
    # or raises a typed error.
    def perform(url, headers)
      attempt = 0
      loop do
        begin
          raw = @transport.call(method: :get, url: url, headers: headers, timeout: @timeout)
        rescue ConnectionError
          raise if attempt >= @max_retries

          @sleeper.call(backoff_delay(attempt))
          attempt += 1
          next
        end

        raw = TransportResponse.new(status: raw.status, headers: Headers.normalize(raw.headers), body: raw.body)
        return raw if raw.status >= 200 && raw.status < 300

        error = Errors.from_response(raw)
        delay = retry_delay(error, attempt)
        raise error if delay.nil?

        @sleeper.call(delay)
        attempt += 1
      end
    end

    # Seconds to wait before the next try, or nil for "do not retry".
    # 429 is retried only when it carries Retry-After (and the wait is not longer
    # than max_retry_delay). 5xx is retried with backoff. Other 4xx never.
    def retry_delay(error, attempt)
      return nil if attempt >= @max_retries

      if error.status == 429
        wait = error.retry_after
        return nil if wait.nil? || wait > @max_retry_delay

        wait
      elsif error.status >= 500
        backoff_delay(attempt)
      end
    end

    def backoff_delay(attempt)
      capped = [BACKOFF_BASE * (2**attempt), @max_retry_delay].min
      capped * (0.5 + (0.5 * @random.call))
    end

    def parse_envelope(raw, parser)
      json = JSON.parse(raw.body.to_s)
      raise TypeError, "expected a JSON object" unless json.is_a?(Hash)

      Response.new(
        data: parser.call(json["data"]),
        location: Location.from_hash(json["location"]),
        meta: Meta.from_hash(json["meta"]),
        status: raw.status,
        headers: raw.headers
      )
    rescue JSON::ParserError, TypeError, ArgumentError => e
      raise ServerError.new(
        "The API answered #{raw.status} but the body could not be read (#{e.message}).",
        status: raw.status, code: "invalid_response", headers: raw.headers, body: raw.body
      )
    end

    def list(data, model)
      return [] if data.nil?
      raise TypeError, "expected a JSON array" unless data.is_a?(Array)

      data.map { |item| model.from_hash(item) }
    end

    # --- Parameter handling ------------------------------------------------

    def place_query(location)
      Place.coerce(location).to_query
    end

    def units_param(units)
      return nil if units.nil?

      value = units.to_s.strip.downcase
      raise ArgumentError, "units must be :metric or :imperial, got #{units.inspect}" unless UNITS.include?(value)

      value
    end

    def format_param(format)
      value = format.to_s.strip.downcase
      raise ArgumentError, "format must be :json or :csv, got #{format.inspect}" unless FORMATS.include?(value)

      value
    end

    def date_param(value, name)
      case value
      when Date, Time then value.strftime("%Y-%m-%d") # DateTime is a Date
      when String
        raise ArgumentError, "#{name} must look like 2024-01-31, got #{value.inspect}" unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        value
      else
        raise ArgumentError, "#{name} must be a Date, a Time or a YYYY-MM-DD String, got #{value.inspect}"
      end
    end

    def days_param(days)
      return nil if days.nil?
      raise ArgumentError, "days must be a whole number of at least 1" unless days.is_a?(Integer) && days >= 1

      days.to_s
    end

    def month_param(month)
      return nil if month.nil?
      raise ArgumentError, "month must be a whole number from 1 to 12" unless month.is_a?(Integer) && month.between?(1, 12)

      month.to_s
    end

    def blank_to_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    # --- Settings ----------------------------------------------------------

    def clean_api_key(value)
      key = value.to_s.strip
      if key.empty?
        raise ConfigurationError,
              "No API key. Pass api_key: or set the #{API_KEY_ENV} environment variable."
      end
      raise ConfigurationError, "The API key contains characters that are not allowed in a header." if key.match?(/[[:cntrl:]]|\s/)

      key
    end

    def clean_base_url(value)
      text = value.to_s.strip.sub(%r{/+\z}, "")
      uri = begin
        URI.parse(text)
      rescue URI::InvalidURIError
        nil
      end
      unless uri && %w[http https].include?(uri.scheme) && uri.host
        raise ConfigurationError, "base_url must be an http(s) URL, got #{value.inspect}"
      end
      if uri.scheme == "http" && !LOOPBACK_HOSTS.include?(uri.host)
        raise ConfigurationError, "base_url must use https (plain http is allowed only for localhost), got #{value.inspect}"
      end

      text
    end

    def positive_number(value, name)
      raise ConfigurationError, "#{name} must be a positive number" unless value.is_a?(Numeric) && value.positive?

      value
    end

    def non_negative_number(value, name)
      raise ConfigurationError, "#{name} must be a number, 0 or more" unless value.is_a?(Numeric) && value >= 0

      value
    end

    def non_negative_integer(value, name)
      raise ConfigurationError, "#{name} must be a whole number, 0 or more" unless value.is_a?(Integer) && value >= 0

      value
    end
  end
end
