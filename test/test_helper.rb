# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"
require "uri"
require "pastclimate"

# A made-up key. It is not a real PastClimate key.
TEST_KEY = "test-key-0123456789"

module TestHelper
  FIXTURES = File.expand_path("fixtures", __dir__)

  DEFAULT_HEADERS = {
    "content-type" => "application/json",
    "ratelimit-limit" => "17",
    "ratelimit-remaining" => "16",
    "ratelimit-reset" => "42",
    "x-credits-used" => "7",
    "x-credits-remaining" => "1234"
  }.freeze

  # A transport that never touches the network. Queue answers (a
  # TransportResponse, or an exception to raise) and read +requests+ afterwards.
  class FakeTransport
    attr_reader :requests

    def initialize(*answers)
      @answers = answers
      @requests = []
    end

    def call(method:, url:, headers:, timeout:)
      @requests << { method: method, url: url, headers: headers, timeout: timeout }
      answer = @answers.shift
      raise "FakeTransport: request ##{@requests.size} had no answer queued (#{url})" if answer.nil?
      raise answer if answer.is_a?(Exception)

      answer
    end

    def last
      @requests.last
    end
  end

  def fixture(name)
    File.read(File.join(FIXTURES, name))
  end

  def ok(body, headers: {}, status: 200)
    PastClimate::TransportResponse.new(status: status, headers: DEFAULT_HEADERS.merge(headers), body: body)
  end

  def ok_fixture(name, headers: {})
    ok(fixture(name), headers: headers)
  end

  def error_answer(status, code, message: "Something is wrong.", headers: {})
    body = JSON.generate("error" => { "code" => code, "message" => message,
                                      "docs_url" => "https://developer.pastclimate.com/api/getting-started/errors/##{code}" })
    PastClimate::TransportResponse.new(status: status, headers: { "content-type" => "application/json" }.merge(headers), body: body)
  end

  # Builds a client wired to +transport+ with a recording sleeper.
  # Returns [client, sleeps].
  def build_client(transport, random: -> { 1.0 }, **options)
    sleeps = []
    settings = { api_key: TEST_KEY, transport: transport, sleeper: ->(seconds) { sleeps << seconds }, random: random }
    client = PastClimate::Client.new(**settings.merge(options))
    [client, sleeps]
  end

  def parsed(request)
    uri = URI.parse(request[:url])
    query = uri.query ? URI.decode_www_form(uri.query).to_h : {}
    [uri.path, query]
  end

  def with_env(values)
    saved = values.keys.to_h { |name| [name, ENV[name]] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end

Minitest::Test.include TestHelper
