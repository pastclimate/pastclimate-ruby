# frozen_string_literal: true

require "json"

module PastClimate
  # Base class of everything this gem raises on purpose.
  class Error < StandardError; end

  # The client was set up wrongly (for example, no API key).
  class ConfigurationError < Error; end

  # The request never produced an HTTP answer: DNS, TLS, connection reset or timeout.
  class ConnectionError < Error
    def initialize(message = "Could not reach the PastClimate API.", timeout: false)
      super(message)
      @timeout = timeout
    end

    # True when the call timed out.
    def timeout?
      @timeout
    end
  end

  # The API answered with an error. Branch on the subclass, or on +code+.
  #
  # Every error carries the HTTP +status+, the stable error +code+, the human
  # +message+ and a +docs_url+. When the server did not send the API's error
  # body (for example a proxy 502), +code+ is "http_<status>" and +docs_url+
  # is nil.
  class ApiError < Error
    attr_reader :status, :code, :docs_url, :headers, :rate_limit, :retry_after, :upgrade_url, :body

    def initialize(message = nil, status: nil, code: nil, docs_url: nil, headers: {}, body: nil)
      super(message || "The PastClimate API returned an error.")
      @status = status
      @code = code
      @docs_url = docs_url
      @headers = headers
      @body = body
      @rate_limit = RateLimit.from_headers(headers)
      @retry_after = Headers.retry_after(headers)
      @upgrade_url = headers["x-upgrade-url"]
    end
  end

  # No key, a bad key, a revoked key, or an account that cannot make calls.
  # Codes: missing_key, invalid_key, key_revoked, email_not_verified, account_suspended.
  class AuthenticationError < ApiError; end

  # The request is not valid. Fix it; retrying will not help.
  # Codes: invalid_request, range_too_large, key_in_query, cors_not_supported, method_not_allowed.
  class InvalidRequestError < ApiError; end

  # No such place, nothing published for the request, or a place that cannot be served.
  # Codes: location_not_found, not_published, not_found, location_blocked.
  class NotFoundError < ApiError; end

  # Your plan does not include this request. Code: plan_required.
  class PlanRequiredError < ApiError; end

  # Too many requests (per minute or per day). +retry_after+ says how long to wait.
  # Codes: rate_limited, daily_request_cap_reached.
  class RateLimitedError < ApiError; end

  # Credits are used up. Code: quota_exceeded. On a plan whose credits are one-time
  # there is no +retry_after+, because waiting does not help.
  class QuotaExceededError < ApiError; end

  # Something went wrong on the server, or the API is unavailable.
  # Codes: internal_error, api_disabled, metering_unavailable. Also raised
  # (code "invalid_response") when a success answer cannot be read.
  class ServerError < ApiError; end

  # Maps an HTTP error answer to one of the classes above.
  module Errors
    CODE_CLASSES = {
      "missing_key" => AuthenticationError,
      "invalid_key" => AuthenticationError,
      "key_revoked" => AuthenticationError,
      "email_not_verified" => AuthenticationError,
      "account_suspended" => AuthenticationError,
      "plan_required" => PlanRequiredError,
      "invalid_request" => InvalidRequestError,
      "range_too_large" => InvalidRequestError,
      "key_in_query" => InvalidRequestError,
      "cors_not_supported" => InvalidRequestError,
      "method_not_allowed" => InvalidRequestError,
      "location_not_found" => NotFoundError,
      "not_published" => NotFoundError,
      "not_found" => NotFoundError,
      "location_blocked" => NotFoundError,
      "rate_limited" => RateLimitedError,
      "daily_request_cap_reached" => RateLimitedError,
      "quota_exceeded" => QuotaExceededError,
      "daily_cap_reached" => QuotaExceededError,
      "internal_error" => ServerError,
      "api_disabled" => ServerError,
      "metering_unavailable" => ServerError
    }.freeze

    # Builds (does not raise) the error for a non-2xx +response+ (a TransportResponse).
    def self.from_response(response)
      status = response.status
      body = parse_body(response.body)
      detail = body.is_a?(Hash) ? body["error"] : nil

      if detail.is_a?(Hash) && detail["code"]
        code = detail["code"].to_s
        message = detail["message"] || "The PastClimate API returned an error (#{code})."
        docs_url = detail["docs_url"]
      else
        code = "http_#{status}"
        message = "The API answered HTTP #{status} without an error body."
        docs_url = nil
      end

      klass = CODE_CLASSES[code] || class_for_status(status)
      klass.new(message, status: status, code: code, docs_url: docs_url, headers: response.headers, body: response.body)
    end

    def self.class_for_status(status)
      case status
      when 401 then AuthenticationError
      when 400, 405 then InvalidRequestError
      when 404 then NotFoundError
      when 429 then RateLimitedError
      when 500..599 then ServerError
      else ApiError
      end
    end

    def self.parse_body(text)
      JSON.parse(text.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
