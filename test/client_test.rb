# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  def setup
    @transport = FakeTransport.new
  end

  def client(*answers, **options)
    @transport = FakeTransport.new(*answers)
    build_client(@transport, **options).first
  end

  # --- one test per operation ------------------------------------------------

  def test_search_locations
    response = client(ok_fixture("search.json")).search_locations("lon", country: "gb")

    path, query = parsed(@transport.last)
    assert_equal "/v1/locations/search", path
    assert_equal({ "q" => "lon", "country" => "gb" }, query)

    first, second = response.data
    assert_instance_of PastClimate::LocationSearchResult, first
    assert_equal "gb/london", first.id
    assert_equal 8_982_000, first.population
    assert_equal true, first.weather_available
    assert_equal false, second.weather_available
    assert_nil second.population
    assert_nil second.lat
    assert_nil response.location
    assert_equal 2, response.meta.count
    assert_equal "lon", response.meta.query
    assert_nil response.meta.country
  end

  def test_search_locations_without_country_leaves_it_out
    client(ok_fixture("search.json")).search_locations("lon")
    _path, query = parsed(@transport.last)
    assert_equal({ "q" => "lon" }, query)
  end

  def test_nearest_location
    response = client(ok_fixture("nearest.json")).nearest_location(lat: 51.51, lon: -0.12, country: "gb")

    path, query = parsed(@transport.last)
    assert_equal "/v1/locations/nearest", path
    assert_equal({ "lat" => "51.51", "lon" => "-0.12", "country" => "gb" }, query)

    assert_instance_of PastClimate::NearestLocation, response.data
    assert_equal "gb/london", response.data.id
    assert_in_delta 3.2, response.data.requested.distance_km
    assert_instance_of PastClimate::RequestedPoint, response.data.requested
    assert_equal 8_982_000, response.data.population
    assert_instance_of PastClimate::Location, response.location
    assert_in_delta(-0.12, response.location.requested.lon)
  end

  def test_get_location
    response = client(ok_fixture("location.json")).get_location("gb/london")

    path, query = parsed(@transport.last)
    assert_equal "/v1/locations/gb/london", path
    assert_equal({}, query)

    assert_instance_of PastClimate::LocationDetail, response.data
    assert_equal 1990, response.data.coverage.first_year
    assert_equal Date.new(2026, 10, 31), response.data.coverage.last_date
    assert_equal "Europe/London", response.location.timezone
  end

  def test_get_location_escapes_the_path
    client(ok_fixture("location.json")).get_location("gb/new york")
    assert_equal "/v1/locations/gb/new%20york", URI.parse(@transport.last[:url]).path
  end

  def test_get_location_needs_an_id
    c = client
    assert_raises(ArgumentError) { c.get_location("london") }
    assert_raises(ArgumentError) { c.get_location(PastClimate::Place.point(lat: 1, lon: 2, country: "gb")) }
    assert_empty @transport.requests
  end

  def test_get_daily_with_dates_and_imperial_units
    response = client(ok_fixture("daily.json")).get_daily(
      "gb/london", start_date: Date.new(2024, 1, 1), end_date: Time.new(2024, 1, 2, 12, 0, 0), units: :imperial
    )

    path, query = parsed(@transport.last)
    assert_equal "/v1/daily", path
    assert_equal({ "location" => "gb/london", "start" => "2024-01-01", "end" => "2024-01-02", "units" => "imperial" }, query)

    first, second = response.data
    assert_instance_of PastClimate::DailyRow, first
    assert_equal Date.new(2024, 1, 1), first.date
    assert_in_delta 5.2, first.daily_avg_temp
    assert_equal 78, first.daily_avg_cloud_percent
    assert_equal true, first.rain_flag
    assert_equal false, second.rain_flag
    assert_equal "metric", response.meta.units.system
    assert_equal "C", response.meta.units.temperature
    assert_equal Date.new(2024, 1, 1), response.meta.start
    assert_equal Date.new(2024, 1, 2), response.meta.end
    assert_equal 2, response.meta.days
  end

  def test_daily_with_string_dates_leaves_units_and_format_out
    client(ok_fixture("daily.json")).get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-31")
    _path, query = parsed(@transport.last)
    assert_equal %w[end location start], query.keys.sort
  end

  def test_daily_by_point
    place = PastClimate::Place.point(lat: 51.5, lon: -0.12, country: "gb")
    client(ok_fixture("daily.json")).get_daily(place, start_date: "2024-01-01", end_date: "2024-01-02")
    _path, query = parsed(@transport.last)
    assert_equal "51.5,-0.12", query["location"]
    assert_equal "gb", query["country"]
  end

  def test_point_numbers_are_plain_decimals
    assert_equal "0.00001,-120.5", PastClimate::Place.point(lat: 0.00001, lon: -120.5, country: "gb").location
    assert_equal "0,10", PastClimate::Place.point(lat: 0, lon: 10.0, country: "gb").location
  end

  def test_get_hourly
    response = client(ok_fixture("hourly.json")).get_hourly("gb/london", date: "2024-01-15", days: 1, units: "metric")

    path, query = parsed(@transport.last)
    assert_equal "/v1/hourly", path
    assert_equal({ "location" => "gb/london", "date" => "2024-01-15", "days" => "1", "units" => "metric" }, query)

    row = response.data.first
    assert_instance_of PastClimate::HourlyRow, row
    assert_equal Time.utc(2024, 1, 15, 0, 0, 0), row.timestamp_utc
    assert row.timestamp_utc.utc?
    assert_in_delta 1012.4, row.pressure
    assert_equal 90, row.cloud_cover_percent
    assert_equal "Europe/London", response.meta.timezone
    assert_equal Date.new(2024, 1, 15), response.meta.date
  end

  def test_get_monthly
    response = client(ok_fixture("monthly.json")).get_monthly("gb/london", units: :imperial)

    path, query = parsed(@transport.last)
    assert_equal "/v1/monthly", path
    assert_equal({ "location" => "gb/london", "units" => "imperial" }, query)

    row = response.data.first
    assert_instance_of PastClimate::MonthlyRow, row
    assert_equal [2024, 1, 15, 744], [row.year, row.month, row.rainy_days, row.hours]
    assert_in_delta 95_000_000.0, row.monthly_total_solar_j_m2
    assert_equal 1, response.meta.rows
  end

  def test_get_yearly
    response = client(ok_fixture("yearly.json")).get_yearly("gb/london")

    path, query = parsed(@transport.last)
    assert_equal "/v1/yearly", path
    assert_equal({ "location" => "gb/london" }, query)

    row = response.data.first
    assert_instance_of PastClimate::YearlyRow, row
    assert_equal [2023, 12, 365], [row.year, row.months, row.days]
  end

  def test_get_normals_with_a_month
    response = client(ok_fixture("normals.json")).get_normals("gb/london", month: 7)

    path, query = parsed(@transport.last)
    assert_equal "/v1/normals", path
    assert_equal({ "location" => "gb/london", "month" => "7" }, query)

    assert_instance_of PastClimate::NormalsData, response.data
    month = response.data.monthly.first
    assert_instance_of PastClimate::NormalsMonthlyRow, month
    assert_equal 7, month.month
    assert_equal 30, month.years_covered
    assert_nil month.avg_humidity_pct
    day = response.data.day_of_year.last
    assert_instance_of PastClimate::NormalsDayRow, day
    assert_equal "07-02", day.md
    assert_in_delta 0.25, day.rain_prob
    assert_equal 7, response.meta.month
  end

  def test_get_normals_without_a_month_leaves_it_out
    client(ok_fixture("normals.json")).get_normals("gb/london")
    _path, query = parsed(@transport.last)
    assert_equal({ "location" => "gb/london" }, query)
  end

  def test_get_records
    response = client(ok_fixture("records.json")).get_records("gb/london")

    path, _query = parsed(@transport.last)
    assert_equal "/v1/records", path

    assert_equal %w[hottest_day coldest_day wettest_day windiest_day], response.data.map(&:metric)
    hottest = response.data.first
    assert_instance_of PastClimate::RecordItem, hottest
    assert_in_delta 37.9, hottest.value
    assert_equal "C", hottest.unit
    assert_equal Date.new(2022, 7, 19), hottest.occurred_on
    assert_nil response.data[2].occurred_on
  end

  def test_get_coverage
    response = client(ok_fixture("coverage.json")).get_coverage(country: "gb")

    path, query = parsed(@transport.last)
    assert_equal "/v1/coverage", path
    assert_equal({ "country" => "gb" }, query)

    assert_instance_of PastClimate::CoverageData, response.data
    assert_equal %w[gb fr], response.data.countries.map(&:country)
    assert_equal Date.new(2026, 10, 31), response.data.countries.first.last_date
    assert_nil response.location
  end

  def test_get_coverage_without_a_country
    client(ok_fixture("coverage.json")).get_coverage
    _path, query = parsed(@transport.last)
    assert_equal({}, query)
    assert_nil URI.parse(@transport.last[:url]).query
  end

  def test_get_me
    response = client(ok_fixture("me.json")).get_me

    path, query = parsed(@transport.last)
    assert_equal "/v1/me", path
    assert_equal({}, query)

    me = response.data
    assert_instance_of PastClimate::MeData, me
    assert_equal "free", me.plan.id
    assert_equal false, me.plan.commercial_use
    assert_equal true, me.plan.attribution_link_required
    assert_equal 3, me.plan.hourly_max_days_per_call
    assert_equal 5, me.plan.hourly_max_age_months
    assert_equal "plan_first", me.key.spend_order
    assert_equal 321, me.credits.one_time_limit
    assert_equal 300, me.credits.one_time_remaining
    assert_nil me.credits.monthly_limit
    assert_nil me.credits.month_resets_at
    assert_equal Time.utc(2026, 11, 15), me.credits.day_resets_at
    assert_equal [11, 4], [me.credits.topup_balance, me.credits.topup_used]
    assert_equal [17, 16], [me.rate_limit.per_minute, me.rate_limit.remaining]
  end

  # --- meta, credits and rate limits on every response ----------------------

  def test_meta_credits_and_rate_limit_are_on_every_response
    c = client(*Array.new(11) { |i| ok_fixture(%w[search nearest location daily hourly monthly yearly normals records coverage me][i] + ".json") })
    responses = [
      c.search_locations("lon"),
      c.nearest_location(lat: 51.5, lon: -0.12, country: "gb"),
      c.get_location("gb/london"),
      c.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02"),
      c.get_hourly("gb/london", date: "2024-01-15"),
      c.get_monthly("gb/london"),
      c.get_yearly("gb/london"),
      c.get_normals("gb/london"),
      c.get_records("gb/london"),
      c.get_coverage,
      c.get_me
    ]
    responses.each do |r|
      assert_equal "test-1", r.meta.methodology_version
      assert_equal 1234, r.meta.credits_remaining
      assert_equal 1234, r.credits_remaining
      refute_nil r.credits_used
      assert_equal PastClimate::RateLimit.new(limit: 17, remaining: 16, reset: 42), r.rate_limit
      assert_equal 200, r.status
      assert_equal "17", r.headers["ratelimit-limit"]
    end
    assert_equal 7, responses[3].credits_used
    assert_equal 0, responses[0].credits_used
  end

  def test_credits_fall_back_to_headers_when_meta_has_none
    body = JSON.generate("location" => nil, "data" => [], "meta" => { "methodology_version" => "x" })
    r = client(ok(body, headers: { "x-credits-used" => "9", "x-credits-remaining" => "55" })).search_locations("lon")
    assert_equal 9, r.credits_used
    assert_equal 55, r.credits_remaining
  end

  def test_rate_limit_values_are_nil_when_headers_are_missing
    answer = PastClimate::TransportResponse.new(status: 200, headers: {}, body: fixture("coverage.json"))
    r = client(answer).get_coverage
    assert_equal PastClimate::RateLimit.new, r.rate_limit
    assert_nil r.rate_limit.limit
  end

  def test_header_names_are_case_insensitive
    answer = PastClimate::TransportResponse.new(status: 200, headers: { "RateLimit-Limit" => "9", "X-Credits-Used" => "3" },
                                                body: JSON.generate("location" => nil, "data" => [], "meta" => {}))
    r = client(answer).search_locations("lon")
    assert_equal 9, r.rate_limit.limit
    assert_equal 3, r.credits_used
  end

  def test_unknown_fields_are_ignored_and_kept_in_raw
    body = JSON.generate("location" => nil, "meta" => { "credits" => 0, "brand_new" => 1 },
                         "data" => [{ "id" => "gb/london", "name" => "London", "country" => "gb", "population" => 1, "weather_available" => true,
                                      "shiny_new_field" => "x" }])
    r = client(ok(body)).search_locations("lon")
    assert_equal "gb/london", r.data.first.id
    assert_equal "x", r.data.first.raw["shiny_new_field"]
    assert_equal 1, r.meta.raw["brand_new"]
  end

  def test_models_have_to_h_and_equality
    c = client(ok_fixture("daily.json"), ok_fixture("daily.json"))
    r = c.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    again = c.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    assert_equal r.data.first, again.data.first
    assert_equal Date.new(2024, 1, 1), r.data.first.to_h[:date]
    refute_equal r.data.first, r.data.last
  end

  # --- auth, user agent, no key in the URL -----------------------------------

  def test_sends_the_key_in_the_authorization_header_and_a_user_agent
    client(ok_fixture("me.json")).get_me
    headers = @transport.last[:headers]
    assert_equal "Bearer #{TEST_KEY}", headers["Authorization"]
    assert_equal "pastclimate-ruby/#{PastClimate::VERSION}", headers["User-Agent"]
    assert_equal "application/json", headers["Accept"]
  end

  def test_the_key_is_never_in_the_url
    c = client(*Array.new(11) { |i| ok_fixture(%w[search nearest location daily hourly monthly yearly normals records coverage me][i] + ".json") })
    c.search_locations("lon", country: "gb")
    c.nearest_location(lat: 51.5, lon: -0.12, country: "gb")
    c.get_location("gb/london")
    c.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02", units: :imperial)
    c.get_hourly("gb/london", date: "2024-01-15", days: 1)
    c.get_monthly("gb/london")
    c.get_yearly("gb/london")
    c.get_normals("gb/london", month: 7)
    c.get_records("gb/london")
    c.get_coverage(country: "gb")
    c.get_me

    assert_equal 11, @transport.requests.size
    @transport.requests.each do |request|
      refute_includes request[:url], TEST_KEY
      refute_match(/api[_-]?key|token|authorization/i, URI.parse(request[:url]).query.to_s)
      assert_equal :get, request[:method]
      assert_equal "Bearer #{TEST_KEY}", request[:headers]["Authorization"]
    end
  end

  def test_the_client_never_prints_the_key
    c = client
    refute_includes c.inspect, TEST_KEY
    refute_includes c.to_s, TEST_KEY
  end

  # --- configuration ---------------------------------------------------------

  def test_key_comes_from_the_environment
    with_env("PASTCLIMATE_API_KEY" => "env-key-123") do
      transport = FakeTransport.new(ok_fixture("me.json"))
      PastClimate::Client.new(transport: transport).get_me
      assert_equal "Bearer env-key-123", transport.last[:headers]["Authorization"]
    end
  end

  def test_an_explicit_key_beats_the_environment
    with_env("PASTCLIMATE_API_KEY" => "env-key-123") do
      transport = FakeTransport.new(ok_fixture("me.json"))
      PastClimate::Client.new(api_key: "arg-key-456", transport: transport).get_me
      assert_equal "Bearer arg-key-456", transport.last[:headers]["Authorization"]
    end
  end

  def test_no_key_raises_a_configuration_error
    with_env("PASTCLIMATE_API_KEY" => nil) do
      error = assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new }
      assert_includes error.message, "PASTCLIMATE_API_KEY"
      assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "  ") }
    end
  end

  def test_a_key_with_a_newline_is_refused
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "abc\r\nX-Evil: 1") }
  end

  def test_default_and_custom_base_urls
    with_env("PASTCLIMATE_BASE_URL" => nil) do
      assert_equal "https://api.pastclimate.com", PastClimate::Client.new(api_key: "k").base_url
      c = client(ok_fixture("me.json"), base_url: "https://example.test/")
      c.get_me
      assert_equal "https://example.test", c.base_url
      assert_equal "https://example.test/v1/me", @transport.last[:url]
    end
  end

  def test_base_url_from_the_environment
    with_env("PASTCLIMATE_BASE_URL" => "https://staging.example.test") do
      assert_equal "https://staging.example.test", PastClimate::Client.new(api_key: "k").base_url
    end
  end

  def test_plain_http_is_allowed_only_for_localhost
    assert_equal "http://127.0.0.1:8787", PastClimate::Client.new(api_key: "k", base_url: "http://127.0.0.1:8787").base_url
    assert_equal "http://localhost:8787", PastClimate::Client.new(api_key: "k", base_url: "http://localhost:8787").base_url
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", base_url: "http://api.example.test") }
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", base_url: "ftp://example.test") }
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", base_url: "not a url") }
  end

  def test_defaults_and_settings
    c = PastClimate::Client.new(api_key: "k")
    assert_equal 30, c.timeout
    assert_equal 2, c.max_retries
    c2 = PastClimate::Client.new(api_key: "k", timeout: 5, max_retries: 4, max_retry_delay: 10)
    assert_equal [5, 4, 10], [c2.timeout, c2.max_retries, c2.max_retry_delay]
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", timeout: 0) }
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", max_retries: -1) }
    assert_raises(PastClimate::ConfigurationError) { PastClimate::Client.new(api_key: "k", max_retries: 1.5) }
  end

  def test_the_timeout_is_passed_to_the_transport
    client(ok_fixture("me.json"), timeout: 12).get_me
    assert_equal 12, @transport.last[:timeout]
  end

  # --- parameter checks (nothing is sent for a bad call) ---------------------

  def test_bad_parameters_raise_before_any_request
    c = client
    assert_raises(ArgumentError) { c.search_locations("") }
    assert_raises(ArgumentError) { c.get_monthly("gb/london", units: :kelvin) }
    assert_raises(ArgumentError) { c.get_daily("gb/london", start_date: "01/02/2024", end_date: "2024-01-02") }
    assert_raises(ArgumentError) { c.get_daily("gb/london", start_date: "2024-01-01", end_date: 20_240_102) }
    assert_raises(ArgumentError) { c.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02", format: :xml) }
    assert_raises(ArgumentError) { c.get_normals("gb/london", month: 13) }
    assert_raises(ArgumentError) { c.get_hourly("gb/london", date: "2024-01-01", days: 0) }
    assert_raises(ArgumentError) { c.get_monthly("") }
    assert_raises(ArgumentError) { c.get_monthly(42) }
    assert_raises(ArgumentError) { c.get_monthly("51.5,-0.12") }
    assert_raises(ArgumentError) { c.nearest_location(lat: 51.5, lon: -0.12, country: "") }
    assert_raises(ArgumentError) { c.nearest_location(lat: "x", lon: -0.12, country: "gb") }
    assert_empty @transport.requests
  end

  # --- CSV ---------------------------------------------------------------------

  def test_daily_csv
    response = client(ok(fixture("daily.csv"), headers: { "content-type" => "text/csv" }))
               .get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02", format: :csv)

    _path, query = parsed(@transport.last)
    assert_equal "csv", query["format"]
    assert_includes @transport.last[:headers]["Accept"], "text/csv"

    assert_instance_of PastClimate::CsvResponse, response
    assert_equal fixture("daily.csv"), response.csv
    assert_equal fixture("daily.csv"), response.to_s
    assert_equal 7, response.credits_used
    assert_equal 1234, response.credits_remaining
    assert_equal 16, response.rate_limit.remaining
    assert_equal 200, response.status
  end

  def test_hourly_csv_with_the_shorthand_and_units
    response = client(ok(fixture("hourly.csv"), headers: { "content-type" => "text/csv" }))
               .get_hourly_csv("gb/london", date: "2024-01-15", days: 1, units: :imperial)
    _path, query = parsed(@transport.last)
    assert_equal({ "location" => "gb/london", "date" => "2024-01-15", "days" => "1", "units" => "imperial", "format" => "csv" }, query)
    assert_equal fixture("hourly.csv"), response.csv
  end

  def test_daily_csv_shorthand
    response = client(ok(fixture("daily.csv"))).get_daily_csv("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    assert_instance_of PastClimate::CsvResponse, response
  end

  def test_format_json_is_the_default_and_is_not_sent
    client(ok_fixture("daily.json")).get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02", format: :json)
    _path, query = parsed(@transport.last)
    refute query.key?("format")
  end

  def test_an_error_on_a_csv_request_is_still_a_typed_error
    c = client(error_answer(404, "not_published", message: "No published data for this request."))
    error = assert_raises(PastClimate::NotFoundError) do
      c.get_daily("gb/london", start_date: "1900-01-01", end_date: "1900-01-02", format: :csv)
    end
    assert_equal "not_published", error.code
  end

  # --- success body problems ------------------------------------------------

  def test_an_unreadable_success_body_is_a_server_error
    error = assert_raises(PastClimate::ServerError) { client(ok("<html>hello</html>")).get_me }
    assert_equal "invalid_response", error.code
    assert_equal 200, error.status

    assert_raises(PastClimate::ServerError) { client(ok("[1,2]")).get_me }
    bad_date = JSON.generate("location" => nil, "meta" => {}, "data" => [{ "date" => "not-a-date" }])
    assert_raises(PastClimate::ServerError) do
      client(ok(bad_date)).get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    end
  end
end
