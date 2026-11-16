# frozen_string_literal: true

require "date"
require "time"

module PastClimate
  # Base class of the response models. A model reads the fields it declares and
  # ignores the rest, so new server fields never break old code. Models are frozen.
  # Use +to_h+ for a plain Hash and +raw+ for the original JSON Hash.
  class Model
    class << self
      def attributes
        @attributes ||= {}
      end

      # Declares a field. +type+ is :string, :integer, :float, :boolean, :date
      # (a Date), :time (a UTC Time), a Model subclass, or [ModelSubclass] for a list.
      def attribute(name, type = :string)
        attributes[name] = type
        attr_reader name
      end

      def from_hash(hash)
        return nil if hash.nil?
        raise ArgumentError, "expected a JSON object for #{self}, got #{hash.class}" unless hash.is_a?(Hash)

        new(hash)
      end

      def coerce(value, type)
        return nil if value.nil?

        case type
        when :string then value.to_s
        when :integer then value.is_a?(Numeric) ? value.to_i : Integer(value)
        when :float then Float(value)
        when :boolean then boolean(value)
        when :date then Date.iso8601(value.to_s)
        when :time then Time.iso8601(value.to_s).utc
        when Array then Array(value).map { |item| type.first.from_hash(item) }
        else type.from_hash(value)
        end
      end

      def boolean(value)
        return value if value == true || value == false

        value.to_s == "true"
      end
    end

    attr_reader :raw

    def initialize(hash = {})
      @raw = hash
      self.class.attributes.each do |name, type|
        instance_variable_set("@#{name}", self.class.coerce(hash[name.to_s], type))
      end
      freeze
    end

    def to_h
      self.class.attributes.each_key.each_with_object({}) do |name, result|
        value = public_send(name)
        result[name] =
          case value
          when Model then value.to_h
          when Array then value.map { |item| item.is_a?(Model) ? item.to_h : item }
          else value
          end
      end
    end

    def ==(other)
      other.class == self.class && other.to_h == to_h
    end
    alias eql? ==

    def hash
      [self.class, to_h].hash
    end

    def inspect
      fields = self.class.attributes.each_key.map { |name| "#{name}=#{public_send(name).inspect}" }
      "#<#{self.class.name} #{fields.join(' ')}>"
    end
  end
end
