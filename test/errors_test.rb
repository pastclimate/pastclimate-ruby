# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  EXPECTED = {
    "missing_key" => [401, PastClimate::AuthenticationError],
    "invalid_key" => [401, PastClimate::AuthenticationError],
    "key_revoked" => [401, PastClimate::AuthenticationError],
    "email_not_verified" => [403, PastClimate::AuthenticationError],
    "account_suspended" => [403, PastClimate::AuthenticationError],
    "plan_required" => [403, PastClimate::PlanRequiredError],
    "cors_not_supported" => [403, PastClimate::InvalidRequestError],
    "invalid_request" => [400, PastClimate::InvalidRequestError],
    "range_too_large" => [400, PastClimate::InvalidRequestError],
    "key_in_query" => [400, PastClimate::InvalidRequestError],
    "method_not_allowed" => [405, PastClimate::InvalidRequestError],
    "location_not_found" => [404, PastClimate::NotFoundError],
    "not_published" => [404, PastClimate::NotFoundError],
    "not_found" => [404, PastClimate::NotFoundError],
    "location_blocked" => [422, PastClimate::NotFoundError],
    "rate_limited" => [429, PastClimate::RateLimitedError],
    "daily_request_cap_reached" => [429, PastClimate::RateLimitedError],
    "quota_exceeded" => [429, PastClimate::QuotaExceededError],
    "internal_error" => [500, PastClimate::ServerError],
    "api_disabled" => [503, PastClimate::ServerError],
    "metering_unavailable" => [503, PastClimate::ServerError]
  }.freeze

  def call_me(*answers)
    transport = FakeTransport.new(*answers)
    client, = build_client(transport, max_retries: 0)
    client.get_me
  end

  def test_every_documented_code_maps_to_its_class
    EXPECTED.each do |code, (status, klass)|
      error = assert_raises(klass, code) { call_me(error_answer(status, code, message: "msg for #{code}")) }
      assert_instance_of klass, error, code
      assert_equal code, error.code
      assert_equal status, error.status
      assert_equal "msg for #{code}", error.message
      assert_equal "https://developer.pastclimate.com/api/getting-started/errors/##{code}", error.docs_url
      assert_kind_of PastClimate::ApiError, error
      assert_kind_of PastClimate::Error, error
    end
  end

  def test_the_error_carries_headers_rate_limit_and_retry_info
    answer = error_answer(429, "rate_limited", headers: {
                            "retry-after" => "12", "x-upgrade-url" => "https://example.test/upgrade",
                            "ratelimit-limit" => "17", "ratelimit-remaining" => "0", "ratelimit-reset" => "12"
                          })
    error = assert_raises(PastClimate::RateLimitedError) { call_me(answer) }
    assert_equal 12, error.retry_after
    assert_equal "https://example.test/upgrade", error.upgrade_url
    assert_equal PastClimate::RateLimit.new(limit: 17, remaining: 0, reset: 12), error.rate_limit
    assert_equal "12", error.headers["retry-after"]
    assert_includes error.body, "rate_limited"
  end

  def test_quota_exceeded_without_retry_after
    error = assert_raises(PastClimate::QuotaExceededError) { call_me(error_answer(429, "quota_exceeded")) }
    assert_nil error.retry_after
  end

  def test_a_body_that_is_not_the_api_error_envelope
    answer = PastClimate::TransportResponse.new(status: 502, headers: { "content-type" => "text/html" }, body: "<html>Bad gateway</html>")
    error = assert_raises(PastClimate::ServerError) { call_me(answer) }
    assert_equal "http_502", error.code
    assert_equal 502, error.status
    assert_nil error.docs_url
    assert_includes error.message, "502"
  end

  def test_an_unknown_code_falls_back_to_the_status
    {
      401 => PastClimate::AuthenticationError, 400 => PastClimate::InvalidRequestError,
      404 => PastClimate::NotFoundError, 429 => PastClimate::RateLimitedError,
      500 => PastClimate::ServerError, 504 => PastClimate::ServerError,
      403 => PastClimate::ApiError, 418 => PastClimate::ApiError, 302 => PastClimate::ApiError
    }.each do |status, klass|
      error = assert_raises(klass) { call_me(error_answer(status, "a_code_from_the_future")) }
      assert_instance_of klass, error, "status #{status}"
      assert_equal "a_code_from_the_future", error.code
    end
  end

  def test_every_class_is_an_api_error
    [PastClimate::AuthenticationError, PastClimate::InvalidRequestError, PastClimate::NotFoundError,
     PastClimate::PlanRequiredError, PastClimate::RateLimitedError, PastClimate::QuotaExceededError,
     PastClimate::ServerError].each do |klass|
      assert_operator klass, :<, PastClimate::ApiError
    end
    assert_operator PastClimate::ConnectionError, :<, PastClimate::Error
    assert_operator PastClimate::ConfigurationError, :<, PastClimate::Error
    refute_operator PastClimate::ConnectionError, :<, PastClimate::ApiError
  end

  def test_errors_can_be_rescued_by_category
    rescued = begin
      call_me(error_answer(404, "location_not_found"))
    rescue PastClimate::NotFoundError => e
      e.code
    end
    assert_equal "location_not_found", rescued
  end
end
