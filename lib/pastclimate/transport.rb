# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module PastClimate
  # What a transport returns: HTTP status, lower-cased header names, body text.
  TransportResponse = Struct.new(:status, :headers, :body, keyword_init: true)

  # The default transport, built on Net::HTTP. A transport is any object with
  #
  #   call(method:, url:, headers:, timeout:) -> TransportResponse
  #
  # that raises PastClimate::ConnectionError when no HTTP answer arrives. Pass
  # your own to Client.new(transport: ...) to use another HTTP library or a fake.
  class NetHttpTransport
    NETWORK_ERRORS = [
      SocketError, SystemCallError, IOError, EOFError, OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse, Net::ProtocolError
    ].freeze

    def call(method:, url:, headers:, timeout:)
      raise ArgumentError, "only GET is supported" unless method == :get

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.max_retries = 0 # the client does its own retrying
      request = Net::HTTP::Get.new(uri.request_uri, headers)
      response = http.start { |connection| connection.request(request) }

      response_headers = {}
      response.each_header { |name, value| response_headers[name.downcase] = value }
      TransportResponse.new(
        status: response.code.to_i,
        headers: response_headers,
        body: response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      )
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
      raise ConnectionError.new("The request timed out (#{e.class}).", timeout: true)
    rescue *NETWORK_ERRORS => e
      raise ConnectionError, "Network error: #{e.class}: #{e.message}"
    end
  end
end
