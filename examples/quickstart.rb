# frozen_string_literal: true

# A quickstart against the live API. It runs only when PASTCLIMATE_API_KEY is set.
#
#   PASTCLIMATE_API_KEY=... ruby -Ilib examples/quickstart.rb
#
# Optional: PASTCLIMATE_BASE_URL points it at another host (a test host, say).
# The last call asks for weather data, which uses credits; the response says how many.

require "pastclimate"

if ENV["PASTCLIMATE_API_KEY"].to_s.strip.empty?
  warn "Set PASTCLIMATE_API_KEY to run this example. It makes real calls to the PastClimate API."
  exit 1
end

client = PastClimate::Client.new

begin
  me = client.get_me
  puts "Plan: #{me.data.plan.name}"

  found = client.search_locations("lon", country: "gb")
  place = found.data.first
  puts "Found: #{place.id} (#{place.name})"

  detail = client.get_location(place.id)
  puts "Data for #{detail.data.name} runs to #{detail.data.coverage.last_date}"

  last_day = detail.data.coverage.last_date
  daily = client.get_daily(place.id, start_date: last_day, end_date: last_day, units: :metric)
  row = daily.data.first
  puts "#{row.date}: #{row.daily_min_temp} to #{row.daily_max_temp} #{daily.meta.units.temperature}, rain #{row.daily_total_rain} #{daily.meta.units.precipitation}"
  puts "That call used #{daily.credits_used} credits; #{daily.credits_remaining} left."
  puts "Requests left this minute: #{daily.rate_limit.remaining}"
rescue PastClimate::QuotaExceededError, PastClimate::RateLimitedError => e
  warn "Limit reached (#{e.code}): #{e.message}"
  warn "Wait #{e.retry_after} seconds." if e.retry_after
  exit 1
rescue PastClimate::ApiError => e
  warn "#{e.class} #{e.status} #{e.code}: #{e.message} (#{e.docs_url})"
  exit 1
rescue PastClimate::ConnectionError => e
  warn "Could not reach the API: #{e.message}"
  exit 1
end
