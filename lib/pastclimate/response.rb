# frozen_string_literal: true

module PastClimate
  # Helpers for reading response headers (names are lower-cased).
  module Headers
    def self.normalize(headers)
      result = {}
      (headers || {}).each { |name, value| result[name.to_s.downcase] = value.is_a?(Array) ? value.join(", ") : value.to_s }
      result
    end

    # An integer header, or nil when it is absent or not a whole number.
    def self.integer(headers, name)
      value = headers[name]
      return nil if value.nil?

      text = value.to_s.strip
      text.match?(/\A\d+\z/) ? text.to_i : nil
    end

    # Retry-After in whole seconds, or nil. Only the delay-in-seconds form is read.
    def self.retry_after(headers)
      integer(headers, "retry-after")
    end
  end

  # The per-minute request limit as the server reported it. Any value is nil
  # when the response did not carry that header (some refusals do not).
  class RateLimit
    attr_reader :limit, :remaining, :reset

    def initialize(limit: nil, remaining: nil, reset: nil)
      @limit = limit
      @remaining = remaining
      @reset = reset
      freeze
    end

    def self.from_headers(headers)
      new(
        limit: Headers.integer(headers, "ratelimit-limit"),
        remaining: Headers.integer(headers, "ratelimit-remaining"),
        reset: Headers.integer(headers, "ratelimit-reset")
      )
    end

    def to_h
      { limit: limit, remaining: remaining, reset: reset }
    end

    def ==(other)
      other.is_a?(RateLimit) && to_h == other.to_h
    end

    def inspect
      "#<PastClimate::RateLimit limit=#{limit.inspect} remaining=#{remaining.inspect} reset=#{reset.inspect}>"
    end
  end

  # What every call has in common: HTTP status, headers, the rate limit and the
  # credit numbers.
  module ResponseInfo
    attr_reader :status, :headers, :rate_limit

    # Credits this call used (meta.credits, else the X-Credits-Used header), or nil.
    def credits_used
      from_meta = meta&.credits
      from_meta.nil? ? Headers.integer(headers, "x-credits-used") : from_meta
    end

    # Credits you can still spend (meta.credits_remaining, else the
    # X-Credits-Remaining header), or nil.
    def credits_remaining
      from_meta = meta&.credits_remaining
      from_meta.nil? ? Headers.integer(headers, "x-credits-remaining") : from_meta
    end

    def meta
      nil
    end
  end

  # A JSON answer: +data+ (typed models), +location+, +meta+, plus rate-limit and credit info.
  class Response
    include ResponseInfo

    attr_reader :data, :location, :meta

    def initialize(data:, location:, meta:, status:, headers:)
      @data = data
      @location = location
      @meta = meta
      @status = status
      @headers = headers
      @rate_limit = RateLimit.from_headers(headers)
    end

    def inspect
      "#<PastClimate::Response status=#{status} credits_used=#{credits_used.inspect} credits_remaining=#{credits_remaining.inspect}>"
    end
  end

  # A CSV answer (+format: :csv+). +csv+ is the text. There is no meta in a CSV
  # body, so credit numbers come from the response headers.
  class CsvResponse
    include ResponseInfo

    attr_reader :csv

    def initialize(csv:, status:, headers:)
      @csv = csv
      @status = status
      @headers = headers
      @rate_limit = RateLimit.from_headers(headers)
    end

    def to_s
      csv
    end

    def inspect
      "#<PastClimate::CsvResponse status=#{status} bytes=#{csv.bytesize} credits_used=#{credits_used.inspect}>"
    end
  end
end
