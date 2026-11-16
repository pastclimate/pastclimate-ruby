# pastclimate (Ruby)

The official Ruby client for the [PastClimate API](https://developer.pastclimate.com/api/):
historical daily, hourly, monthly and yearly weather, climate normals and records.

- Ruby 3.0 or newer. No runtime dependencies (it uses `net/http`).
- One method per API operation, with typed response models.
- One error class per kind of failure.
- Automatic retries where retrying is safe.
- Credit and rate-limit numbers on every response.

## Install

```sh
gem install pastclimate
```

or in your `Gemfile`:

```ruby
gem "pastclimate"
```

## Quickstart

Get a key on your [API page](https://www.pastclimate.com/account/api/) and put it in an
environment variable. Never put a key in source code or in a URL.

```sh
export PASTCLIMATE_API_KEY=your_key_here
```

```ruby
require "pastclimate"

client = PastClimate::Client.new # reads PASTCLIMATE_API_KEY

response = client.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-31")

response.data.each do |day|
  puts "#{day.date}: #{day.daily_min_temp} to #{day.daily_max_temp}"
end

puts "Used #{response.credits_used} credits, #{response.credits_remaining} left"
```

A runnable version is in [`examples/quickstart.rb`](examples/quickstart.rb). It makes real calls, so it
only runs when `PASTCLIMATE_API_KEY` is set.

## Configuration

```ruby
client = PastClimate::Client.new(
  api_key: "...",                         # default: ENV["PASTCLIMATE_API_KEY"]
  base_url: "https://api.pastclimate.com", # default: ENV["PASTCLIMATE_BASE_URL"], then this value
  timeout: 30,                            # seconds per attempt
  max_retries: 2,                         # retries after the first try
  max_retry_delay: 60                     # longest wait the client will sleep between tries
)
```

- With no key, `Client.new` raises `PastClimate::ConfigurationError`.
- `base_url` must be `https`. Plain `http` is accepted only for `localhost` and `127.0.0.1`.
- The key is sent as `Authorization: Bearer <key>`, never in the URL. `client.inspect` hides it.
- Redirects are not followed, so the key cannot be sent to another host.
- The `User-Agent` is `pastclimate-ruby/<version>`.

## Places

Every weather method takes a place as its first argument. Give it in one of two ways.

```ruby
# 1. A location id: country code, slash, place slug. A plain String works.
client.get_monthly("gb/london")
client.get_monthly(PastClimate::Place.id("gb/london"))

# 2. A latitude and longitude, with the two-letter country they are in.
point = PastClimate::Place.point(lat: 51.5, lon: -0.12, country: "gb")
client.get_monthly(point)
```

Find ids with `search_locations`. A point is snapped to the nearest place in that country; the
response's `location.requested` shows the point you sent and how far away the chosen place is.

## Methods

Every method returns a `PastClimate::Response` with `data`, `location`, `meta`, `rate_limit`,
`credits_used`, `credits_remaining`, `status` and `headers`. The type of `data` is given below.
Fields the server leaves out are `nil`; fields this version does not know about are ignored
(`model.raw` has the original hash).

Dates are `Date` objects and timestamps are UTC `Time` objects. You may pass dates as `Date`,
`Time` or `"YYYY-MM-DD"` strings.

### `search_locations(q, country: nil)`

Search places by the start of their name. `data` is an `Array` of `LocationSearchResult`.

```ruby
found = client.search_locations("lon", country: "gb")
found.data.each { |place| puts "#{place.id} #{place.name} #{place.weather_available}" }
```

### `nearest_location(lat:, lon:, country:)`

The place nearest a point, inside one country. `data` is a `NearestLocation`.

```ruby
nearest = client.nearest_location(lat: 51.5, lon: -0.12, country: "gb")
puts "#{nearest.data.id}, #{nearest.data.requested.distance_km} km away"
```

### `get_location(id)`

One location by id. `data` is a `LocationDetail`, including `coverage` (`first_year`, `last_date`).

```ruby
london = client.get_location("gb/london")
puts london.data.timezone, london.data.coverage.last_date
```

### `get_daily(location, start_date:, end_date:, units: nil, format: :json)`

Daily values from `start_date` to `end_date`, both included. `data` is an `Array` of `DailyRow`.

```ruby
daily = client.get_daily("gb/london", start_date: "2024-01-01", end_date: "2024-01-31", units: :imperial)
daily.data.each { |d| puts "#{d.date} #{d.daily_avg_temp} #{daily.meta.units.temperature}" }
```

### `get_hourly(location, date:, days: nil, units: nil, format: :json)`

Hourly values for `days` consecutive local days starting at `date`. `data` is an `Array` of `HourlyRow`.
Leave `days` out for the server default.

```ruby
hourly = client.get_hourly("gb/london", date: "2024-01-15", days: 1)
hourly.data.each { |h| puts "#{h.timestamp_utc.iso8601} #{h.temperature}" }
```

### `get_monthly(location, units: nil)`

Every month on file. `data` is an `Array` of `MonthlyRow`.

```ruby
monthly = client.get_monthly("gb/london")
puts monthly.data.last.monthly_total_rain
```

### `get_yearly(location, units: nil)`

Every year on file. `data` is an `Array` of `YearlyRow`.

```ruby
yearly = client.get_yearly("gb/london")
yearly.data.each { |y| puts "#{y.year} #{y.yearly_avg_temp}" }
```

### `get_normals(location, month: nil, units: nil)`

Climate normals. `data` is a `NormalsData` with `monthly` and `day_of_year` arrays. `month:` (1 to 12)
narrows both to one month.

```ruby
normals = client.get_normals("gb/london", month: 7)
puts normals.data.monthly.first.avg_temp
puts normals.data.day_of_year.first.rain_prob
```

### `get_records(location, units: nil)`

The hottest, coldest, wettest and windiest day on file. `data` is an `Array` of `RecordItem`.

```ruby
client.get_records("gb/london").data.each do |record|
  puts "#{record.metric}: #{record.value} #{record.unit} on #{record.occurred_on}"
end
```

### `get_coverage(country: nil)`

The countries the archive serves, and the first year and last day of published data for each.
`data` is a `CoverageData`. Check it before asking for dates near the end of the archive.

```ruby
client.get_coverage(country: "gb").data.countries.each do |c|
  puts "#{c.country}: #{c.first_year} to #{c.last_date}"
end
```

### `get_me`

Your plan, credit balance and limits. `data` is a `MeData`. Use it instead of hard-coding limits.

```ruby
me = client.get_me.data
puts me.plan.name
puts me.credits.used_this_month
puts me.rate_limit.per_minute
```

## Units

`units:` is `:metric` (the server default) or `:imperial`. Field names are the same in both; the
unit of each value is in `response.meta.units` (`system`, `temperature`, `precipitation`,
`wind_speed`, `pressure`). Anything else raises `ArgumentError` before a request is sent.

```ruby
response = client.get_records("gb/london", units: :imperial)
puts response.meta.units.temperature # => "F"
```

## CSV

`get_daily` and `get_hourly` can return CSV. Pass `format: :csv`, or use the shorthands
`get_daily_csv` and `get_hourly_csv`. You get a `PastClimate::CsvResponse`:

```ruby
csv = client.get_daily_csv("gb/london", start_date: "2023-01-01", end_date: "2023-12-31")
File.write("london-2023.csv", csv.csv)
puts csv.credits_used
```

A CSV body has no `meta`, so `credits_used`, `credits_remaining` and `rate_limit` come from the
response headers. If the request fails you still get a typed error, never an error saved as CSV.

## Credits and rate limits

Every response, JSON or CSV, tells you what the call cost and what is left:

```ruby
response = client.get_monthly("gb/london")

response.credits_used          # credits this call used
response.credits_remaining     # credits you can still spend (may be nil)
response.meta.methodology_version

limit = response.rate_limit    # the per-minute request limit
limit.limit                    # requests allowed per minute
limit.remaining                # requests left in this minute
limit.reset                    # seconds until the oldest request leaves the minute window
```

The SDK does not know what a call costs and does not check your balance. Read the numbers from the
response, or call `get_me`. Rate-limit values are `nil` when the server did not send the header.

## Errors

Every failure is a subclass of `PastClimate::Error`.

| Class | Raised for (error `code`) |
|---|---|
| `AuthenticationError` | `missing_key`, `invalid_key`, `key_revoked`, `email_not_verified`, `account_suspended` |
| `InvalidRequestError` | `invalid_request`, `range_too_large`, `key_in_query`, `cors_not_supported`, `method_not_allowed` |
| `NotFoundError` | `location_not_found`, `not_published`, `not_found`, `location_blocked` |
| `PlanRequiredError` | `plan_required` |
| `RateLimitedError` | `rate_limited`, `daily_request_cap_reached` |
| `QuotaExceededError` | `quota_exceeded` |
| `ServerError` | `internal_error`, `api_disabled`, `metering_unavailable` (and `invalid_response`, when a success body cannot be read) |
| `ConnectionError` | no HTTP answer: DNS, TLS, reset or timeout (`error.timeout?`) |
| `ConfigurationError` | the client was set up wrongly |

The first seven (`AuthenticationError` to `ServerError`) inherit from `PastClimate::ApiError` and carry
`status`, `code`, `message`, `docs_url`, plus `headers`, `rate_limit`, `retry_after` (seconds, or `nil`),
`upgrade_url` and the raw `body`. An unknown future code still maps to a class by its HTTP status. If a
proxy answers without the API's error body, `code` is `"http_<status>"` and `docs_url` is `nil`.

```ruby
begin
  client.get_daily("gb/london", start_date: "1900-01-01", end_date: "1900-01-31")
rescue PastClimate::NotFoundError => e
  puts "No data: #{e.code} - #{e.message}" # e.g. not_published; see client.get_coverage
rescue PastClimate::QuotaExceededError => e
  puts "Out of credits. Upgrade: #{e.upgrade_url}"
rescue PastClimate::RateLimitedError => e
  puts "Slow down. Wait #{e.retry_after.inspect} seconds."
rescue PastClimate::ApiError => e
  puts "#{e.status} #{e.code}: #{e.message} (#{e.docs_url})"
rescue PastClimate::ConnectionError => e
  puts "Network problem: #{e.message}"
end
```

Branch on the class or `code`, not on the message. Failed calls are not charged.

## Retries

The client retries a call automatically, up to `max_retries` times (default 2):

| Failure | What happens |
|---|---|
| `429` **with** `Retry-After` | waits that many seconds, then retries |
| `429` **without** `Retry-After` | raised at once (on a plan with one-time credits this means they are used up, and waiting does not help) |
| `500`, `502`, `503`, any `5xx` | retries with exponential backoff and jitter |
| network error or timeout | retries with the same backoff |
| any other `4xx` | raised at once; fix the request |

A `429` whose `Retry-After` is longer than `max_retry_delay` (default 60 seconds), for example "wait
until midnight UTC", is raised instead of slept on; `retry_after` tells you how long. Set
`max_retries: 0` to turn retrying off. Retries repeat the same GET, so they cannot double-send
anything. Refused calls still count toward your daily request limit, so do not wrap the client in an
unbounded retry loop of your own.

## Custom HTTP transport

The default transport uses `Net::HTTP`. To use another library, or a fake in your own tests, pass any
object with `call(method:, url:, headers:, timeout:)` that returns a `PastClimate::TransportResponse`
(`status`, `headers` with lower-case names, `body`) and raises `PastClimate::ConnectionError` when no
HTTP answer arrives:

```ruby
client = PastClimate::Client.new(api_key: "test", transport: MyTransport.new)
```

## Development

```sh
bundle install
bundle exec rake test
```

Without Bundler: `ruby -Ilib -Itest -e 'Dir["test/**/*_test.rb"].each { |f| require File.expand_path(f) }'`.
The tests use a fake transport and a small local HTTP server; they never call the real API.

## License

MIT. See [LICENSE](LICENSE).
