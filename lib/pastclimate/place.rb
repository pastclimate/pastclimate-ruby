# frozen_string_literal: true

module PastClimate
  # Where to get weather for: a location id, or a latitude/longitude plus country.
  #
  #   PastClimate::Place.id("gb/london")
  #   PastClimate::Place.point(lat: 51.5, lon: -0.12, country: "gb")
  #
  # Anywhere a place is expected you may also pass the id as a plain String.
  # A point is snapped to the nearest place in that country; the server echoes
  # the snapped point in +response.location.requested+.
  class Place
    POINT_LIKE = /\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/.freeze

    attr_reader :location, :country

    def self.id(id)
      text = id.to_s.strip
      raise ArgumentError, "a location id is required, for example \"gb/london\"" if text.empty?
      if text.match?(POINT_LIKE)
        raise ArgumentError, "#{text.inspect} looks like a point; use Place.point(lat:, lon:, country:)"
      end

      new(text, nil)
    end

    def self.point(lat:, lon:, country:)
      raise ArgumentError, "lat and lon must be numbers" unless finite_number?(lat) && finite_number?(lon)

      cc = country.to_s.strip
      raise ArgumentError, "country is required with a lat/lon point, for example \"gb\"" if cc.empty?

      new("#{format_number(lat)},#{format_number(lon)}", cc)
    end

    # Turns a String id or a Place into a Place.
    def self.coerce(value)
      case value
      when Place then value
      when String then id(value)
      else raise ArgumentError, "expected a location id String or a PastClimate::Place, got #{value.class}"
      end
    end

    def self.finite_number?(value)
      value.is_a?(Numeric) && value.to_f.finite?
    end

    # Plain decimal text, never scientific notation.
    def self.format_number(value)
      format("%.10f", value.to_f).sub(/0+\z/, "").sub(/\.\z/, "")
    end

    def initialize(location, country)
      @location = location
      @country = country
      freeze
    end

    # Query parameters for this place.
    def to_query
      params = { "location" => location }
      params["country"] = country if country
      params
    end

    def to_s
      country ? "#{location} (#{country})" : location
    end

    def inspect
      "#<PastClimate::Place #{self}>"
    end
  end
end
