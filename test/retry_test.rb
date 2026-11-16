# frozen_string_literal: true

require "test_helper"

class RetryTest < Minitest::Test
  def setup
    @ok = ok_fixture("me.json")
  end

  def run_me(*answers, random: -> { 1.0 }, **options)
    @transport = FakeTransport.new(*answers)
    @client, @sleeps = build_client(@transport, random: random, **options)
    @client.get_me
  end

  # --- 429 -------------------------------------------------------------------

  def test_429_with_retry_after_waits_then_succeeds
    response = run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "3" }), @ok)
    assert_equal 200, response.status
    assert_equal 2, @transport.requests.size
    assert_equal [3], @sleeps
  end

  def test_the_retry_sends_the_same_request
    run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "1" }), @ok)
    first, second = @transport.requests
    assert_equal first, second
    assert_equal "Bearer #{TEST_KEY}", second[:headers]["Authorization"]
  end

  def test_429_without_retry_after_is_never_retried
    error = assert_raises(PastClimate::QuotaExceededError) { run_me(error_answer(429, "quota_exceeded")) }
    assert_equal "quota_exceeded", error.code
    assert_equal 1, @transport.requests.size
    assert_empty @sleeps

    assert_raises(PastClimate::RateLimitedError) { run_me(error_answer(429, "rate_limited")) }
    assert_equal 1, @transport.requests.size
  end

  def test_429_with_a_retry_after_longer_than_the_cap_is_raised_not_waited
    error = assert_raises(PastClimate::RateLimitedError) do
      run_me(error_answer(429, "daily_request_cap_reached", headers: { "retry-after" => "3600" }))
    end
    assert_equal 3600, error.retry_after
    assert_equal 1, @transport.requests.size
    assert_empty @sleeps
  end

  def test_the_cap_is_configurable
    run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "90" }), @ok, max_retry_delay: 120)
    assert_equal [90], @sleeps
  end

  def test_429_retry_after_zero_retries_at_once
    run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "0" }), @ok)
    assert_equal [0], @sleeps
  end

  def test_429_with_an_unreadable_retry_after_is_not_retried
    assert_raises(PastClimate::RateLimitedError) do
      run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "soon" }))
    end
    assert_equal 1, @transport.requests.size
  end

  def test_429_gives_up_after_max_retries
    limited = -> { error_answer(429, "rate_limited", headers: { "retry-after" => "1" }) }
    error = assert_raises(PastClimate::RateLimitedError) { run_me(limited.call, limited.call, limited.call) }
    assert_equal 1, error.retry_after
    assert_equal 3, @transport.requests.size # 1 try + 2 retries
    assert_equal [1, 1], @sleeps
  end

  # --- 5xx -------------------------------------------------------------------

  def test_5xx_is_retried_with_growing_backoff
    boom = -> { error_answer(500, "internal_error") }
    error = assert_raises(PastClimate::ServerError) { run_me(boom.call, boom.call, boom.call, random: -> { 1.0 }) }
    assert_equal "internal_error", error.code
    assert_equal 3, @transport.requests.size
    assert_equal [0.5, 1.0], @sleeps
  end

  def test_backoff_has_jitter_between_half_and_full
    boom = -> { error_answer(503, "api_disabled") }
    assert_raises(PastClimate::ServerError) { run_me(boom.call, boom.call, boom.call, random: -> { 0.0 }) }
    assert_equal [0.25, 0.5], @sleeps
  end

  def test_backoff_is_capped_by_max_retry_delay
    boom = -> { error_answer(500, "internal_error") }
    assert_raises(PastClimate::ServerError) do
      run_me(boom.call, boom.call, boom.call, boom.call, max_retries: 3, max_retry_delay: 0.6)
    end
    assert_equal [0.5, 0.6, 0.6], @sleeps
  end

  def test_5xx_then_success
    response = run_me(error_answer(503, "metering_unavailable"), @ok)
    assert_equal 200, response.status
    assert_equal 2, @transport.requests.size
  end

  def test_a_5xx_without_an_error_body_is_retried
    html = PastClimate::TransportResponse.new(status: 502, headers: {}, body: "<html>bad gateway</html>")
    response = run_me(html, @ok)
    assert_equal 200, response.status
  end

  def test_max_retries_zero_means_one_try
    assert_raises(PastClimate::ServerError) { run_me(error_answer(500, "internal_error"), max_retries: 0) }
    assert_equal 1, @transport.requests.size
    assert_raises(PastClimate::RateLimitedError) do
      run_me(error_answer(429, "rate_limited", headers: { "retry-after" => "1" }), max_retries: 0)
    end
    assert_equal 1, @transport.requests.size
  end

  def test_the_default_is_two_retries
    boom = -> { error_answer(500, "internal_error") }
    @transport = FakeTransport.new(boom.call, boom.call, boom.call, boom.call)
    client = PastClimate::Client.new(api_key: TEST_KEY, transport: @transport, sleeper: ->(_) {})
    assert_raises(PastClimate::ServerError) { client.get_me }
    assert_equal 3, @transport.requests.size
  end

  # --- other 4xx are never retried -------------------------------------------

  def test_other_client_errors_are_never_retried
    [[400, "invalid_request"], [400, "range_too_large"], [401, "invalid_key"], [403, "plan_required"],
     [404, "location_not_found"], [404, "not_published"], [422, "location_blocked"]].each do |status, code|
      assert_raises(PastClimate::ApiError, code) { run_me(error_answer(status, code), @ok) }
      assert_equal 1, @transport.requests.size, code
      assert_empty @sleeps, code
    end
  end

  # --- network errors --------------------------------------------------------

  def test_network_errors_are_retried
    response = run_me(PastClimate::ConnectionError.new("reset"), PastClimate::ConnectionError.new("reset"), @ok)
    assert_equal 200, response.status
    assert_equal 3, @transport.requests.size
    assert_equal [0.5, 1.0], @sleeps
  end

  def test_network_errors_are_raised_when_retries_run_out
    boom = -> { PastClimate::ConnectionError.new("The request timed out.", timeout: true) }
    error = assert_raises(PastClimate::ConnectionError) { run_me(boom.call, boom.call, boom.call) }
    assert_predicate error, :timeout?
    assert_equal 3, @transport.requests.size
  end

  def test_a_non_timeout_connection_error
    error = assert_raises(PastClimate::ConnectionError) { run_me(PastClimate::ConnectionError.new("refused"), max_retries: 0) }
    refute_predicate error, :timeout?
  end

  def test_csv_requests_retry_too
    @transport = FakeTransport.new(error_answer(500, "internal_error"), ok(fixture("daily.csv")))
    client, sleeps = build_client(@transport)
    response = client.get_daily_csv("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    assert_equal fixture("daily.csv"), response.csv
    assert_equal 1, sleeps.size
  end
end
