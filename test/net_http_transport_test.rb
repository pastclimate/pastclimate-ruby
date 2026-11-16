# frozen_string_literal: true

require "test_helper"
require "socket"

# Talks to a throwaway HTTP server on 127.0.0.1, so the default Net::HTTP
# transport is exercised for real (headers, query string, status, timeouts).
class NetHttpTransportTest < Minitest::Test
  class MiniServer
    attr_reader :port, :requests

    # The block gets (request_line, headers) and returns [status, headers, body].
    def initialize(&handler)
      @handler = handler
      @requests = []
      @lock = Mutex.new
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @threads = [Thread.new { accept_loop }]
    end

    def base_url
      "http://127.0.0.1:#{port}"
    end

    def stop
      @server.close
    rescue IOError
      nil
    ensure
      @threads.each(&:kill)
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        @threads << Thread.new(socket) { |s| serve(s) }
      end
    rescue IOError, SystemCallError
      nil
    end

    def serve(socket)
      request_line = socket.gets.to_s.chomp
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.chomp.split(": ", 2)
        headers[name.downcase] = value
      end
      @lock.synchronize { @requests << { line: request_line, headers: headers } }
      status, response_headers, body = @handler.call(request_line, headers)
      head = +"HTTP/1.1 #{status} Status\r\n"
      response_headers.each { |name, value| head << "#{name}: #{value}\r\n" }
      head << "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n"
      socket.write(head + body)
    rescue IOError, SystemCallError
      nil
    ensure
      socket.close unless socket.closed?
    end
  end

  def teardown
    @server&.stop
  end

  def start_server(&handler)
    @server = MiniServer.new(&handler)
  end

  def real_client(**options)
    PastClimate::Client.new(api_key: TEST_KEY, base_url: @server.base_url, **options)
  end

  def json_ok(name)
    [200, DEFAULT_HEADERS, fixture(name)]
  end

  def test_a_real_round_trip
    start_server { |_line, _headers| json_ok("daily.json") }
    response = real_client.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-02", units: :imperial)

    request = @server.requests.first
    assert_equal "GET /v1/daily?location=gb%2Flondon&start=2024-01-01&end=2024-01-02&units=imperial HTTP/1.1", request[:line]
    assert_equal "Bearer #{TEST_KEY}", request[:headers]["authorization"]
    assert_equal "pastclimate-ruby/#{PastClimate::VERSION}", request[:headers]["user-agent"]
    refute_includes request[:line], TEST_KEY

    assert_equal 2, response.data.size
    assert_equal 7, response.credits_used
    assert_equal 1234, response.credits_remaining
    assert_equal 42, response.rate_limit.reset
  end

  def test_csv_over_a_real_socket
    start_server { |_line, _headers| [200, DEFAULT_HEADERS.merge("content-type" => "text/csv"), fixture("daily.csv")] }
    response = real_client.get_daily_csv("gb/london", start_date: "2024-01-01", end_date: "2024-01-02")
    assert_equal fixture("daily.csv"), response.csv
    assert_equal Encoding::UTF_8, response.csv.encoding
  end

  def test_an_error_answer_is_typed
    start_server { |_line, _headers| [404, { "content-type" => "application/json" }, JSON.generate("error" => { "code" => "location_not_found", "message" => "Location not found.", "docs_url" => "https://example.test/x" })] }
    error = assert_raises(PastClimate::NotFoundError) { real_client.get_location("gb/nowhere") }
    assert_equal "location_not_found", error.code
    assert_equal 1, @server.requests.size
  end

  def test_429_with_retry_after_is_retried_for_real
    calls = 0
    start_server do |_line, _headers|
      calls += 1
      if calls == 1
        [429, { "content-type" => "application/json", "retry-after" => "0" },
         JSON.generate("error" => { "code" => "rate_limited", "message" => "slow down", "docs_url" => "u" })]
      else
        json_ok("me.json")
      end
    end
    response = real_client.get_me
    assert_equal 200, response.status
    assert_equal 2, @server.requests.size
  end

  def test_429_without_retry_after_is_not_retried_for_real
    start_server do |_line, _headers|
      [429, { "content-type" => "application/json" },
       JSON.generate("error" => { "code" => "quota_exceeded", "message" => "gone", "docs_url" => "u" })]
    end
    assert_raises(PastClimate::QuotaExceededError) { real_client.get_me }
    assert_equal 1, @server.requests.size
  end

  def test_redirects_are_not_followed_so_the_key_cannot_leak
    start_server { |_line, _headers| [302, { "location" => "http://example.invalid/steal" }, ""] }
    error = assert_raises(PastClimate::ApiError) { real_client.get_me }
    assert_equal 302, error.status
    assert_equal "http_302", error.code
    assert_equal 1, @server.requests.size
  end

  def test_a_timeout_is_a_connection_error
    start_server do |_line, _headers|
      sleep 2
      json_ok("me.json")
    end
    started = Time.now
    error = assert_raises(PastClimate::ConnectionError) { real_client(timeout: 0.3, max_retries: 0).get_me }
    assert_predicate error, :timeout?
    assert_operator Time.now - started, :<, 1.5
  end

  def test_a_refused_connection_is_a_connection_error
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    client = PastClimate::Client.new(api_key: TEST_KEY, base_url: "http://127.0.0.1:#{port}", max_retries: 0)
    error = assert_raises(PastClimate::ConnectionError) { client.get_me }
    refute_predicate error, :timeout?
  end
end
