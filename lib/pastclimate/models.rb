# frozen_string_literal: true

# Response models. Every field is optional on purpose: a field the server omits is nil,
# and a field this version does not know about is ignored (see Model#raw).
module PastClimate
  # The point you asked for and how far it was from the grid cell that supplies the data.
  class RequestedPoint < Model
    # Latitude you asked for.
    attribute :lat, :float
    # Longitude you asked for.
    attribute :lon, :float
    # Great-circle distance from the requested point to the snapped grid cell, in km.
    attribute :distance_km, :float
  end

  # Span of published data for a location's country.
  class LocationCoverage < Model
    # First year with published data for the country.
    attribute :first_year, :integer
    # Last day with published data for the country.
    attribute :last_date, :date
  end

  # The place a response is about (the "location" part of the envelope).
  class Location < Model
    # Location id: country code, a slash, then the place slug. Use it as the location parameter.
    attribute :id, :string
    # Display name.
    attribute :name, :string
    # Lower-case two-letter country code.
    attribute :country, :string
    # Latitude of the centre of the grid cell that supplies the data (0.25 degree cells, about 28 km), not of the town centre.
    attribute :lat, :float
    # Longitude of the centre of the grid cell that supplies the data.
    attribute :lon, :float
    # IANA timezone. Daily and hourly days are local calendar days in this timezone.
    attribute :timezone, :string
    # Present only when the location was given as lat,lon (or by /v1/locations/nearest): the point that was snapped.
    attribute :requested, RequestedPoint
  end

  # One result of a place search.
  class LocationSearchResult < Model
    # Location id.
    attribute :id, :string
    # Display name.
    attribute :name, :string
    # Lower-case two-letter country code.
    attribute :country, :string
    # Population, used to rank results.
    attribute :population, :integer
    # Grid cell centre latitude. Absent when weather_available is false.
    attribute :lat, :float
    # Grid cell centre longitude. Absent when weather_available is false.
    attribute :lon, :float
    # IANA timezone. Absent when weather_available is false.
    attribute :timezone, :string
    # false when this place cannot be served. Asking for its data returns 422 location_blocked.
    attribute :weather_available, :boolean
  end

  # One location by id.
  class LocationDetail < Model
    # Location id.
    attribute :id, :string
    # Display name.
    attribute :name, :string
    # Lower-case two-letter country code.
    attribute :country, :string
    # Grid cell centre latitude.
    attribute :lat, :float
    # Grid cell centre longitude.
    attribute :lon, :float
    # IANA timezone.
    attribute :timezone, :string
    # Population.
    attribute :population, :integer
    attribute :coverage, LocationCoverage
  end

  # The place nearest a point.
  class NearestLocation < Model
    # Location id.
    attribute :id, :string
    # Display name.
    attribute :name, :string
    # Lower-case two-letter country code.
    attribute :country, :string
    # Grid cell centre latitude.
    attribute :lat, :float
    # Grid cell centre longitude.
    attribute :lon, :float
    # IANA timezone.
    attribute :timezone, :string
    # Present only when the location was given as lat,lon (or by /v1/locations/nearest): the point that was snapped.
    attribute :requested, RequestedPoint
    # Population.
    attribute :population, :integer
  end

  # One local calendar day of weather.
  class DailyRow < Model
    # The local calendar day, in the location's timezone.
    attribute :date, :date
    # Mean temperature of the day, deg C. With units=imperial: deg F.
    attribute :daily_avg_temp, :float
    # Lowest temperature of the day, deg C. With units=imperial: deg F.
    attribute :daily_min_temp, :float
    # Highest temperature of the day, deg C. With units=imperial: deg F.
    attribute :daily_max_temp, :float
    # Total precipitation of the day, mm. With units=imperial: inches.
    attribute :daily_total_rain, :float
    # Mean wind speed of the day, m/s. With units=imperial: mph.
    attribute :daily_avg_wind, :float
    # Mean cloud cover of the day, 0 to 100.
    attribute :daily_avg_cloud_percent, :integer
    # true when total precipitation was at least 1 mm.
    attribute :rain_flag, :boolean
  end

  # One hour of weather.
  class HourlyRow < Model
    # Start of the hour, UTC.
    attribute :timestamp_utc, :time
    # Air temperature at 2 m, deg C. With units=imperial: deg F.
    attribute :temperature, :float
    # Apparent temperature (Steadman), deg C. With units=imperial: deg F.
    attribute :feels_like_temperature, :float
    # Dewpoint, deg C. With units=imperial: deg F.
    attribute :dewpoint, :float
    # Precipitation in the hour, mm. With units=imperial: inches.
    attribute :precipitation, :float
    # Wind speed, m/s. With units=imperial: mph.
    attribute :wind_speed, :float
    # Wind direction, degrees, 0 to 360.
    attribute :wind_direction_deg, :float
    # Relative humidity, 0 to 100, derived from temperature and dewpoint.
    attribute :relative_humidity_percent, :float
    # Surface pressure, hPa. With units=imperial: inHg.
    attribute :pressure, :float
    # Total cloud cover, 0 to 100.
    attribute :cloud_cover_percent, :integer
    # Solar radiation received in the hour, kWh per square metre. Not changed by units.
    attribute :solar_radiation_kwh_m2, :float
  end

  # One calendar month (UTC) of summary values.
  class MonthlyRow < Model
    # Calendar year (UTC).
    attribute :year, :integer
    # Month, 1 to 12 (UTC).
    attribute :month, :integer
    # Mean hourly temperature, deg C. With units=imperial: deg F.
    attribute :monthly_avg_temp, :float
    # Lowest hourly temperature in the month, deg C. With units=imperial: deg F.
    attribute :monthly_min_temp, :float
    # Highest hourly temperature in the month, deg C. With units=imperial: deg F.
    attribute :monthly_max_temp, :float
    # Total precipitation, mm. With units=imperial: inches.
    attribute :monthly_total_rain, :float
    # Mean wind speed, m/s. With units=imperial: mph.
    attribute :monthly_avg_wind, :float
    # Mean surface pressure, hPa. With units=imperial: inHg.
    attribute :monthly_avg_pressure, :float
    # Mean cloud cover, 0 to 100.
    attribute :monthly_avg_cloud_percent, :float
    # Total solar radiation, joules per square metre. Not changed by units.
    attribute :monthly_total_solar_j_m2, :float
    # Days with at least 1 mm of precipitation.
    attribute :rainy_days, :integer
    # Days with at least 20 mm of precipitation.
    attribute :heavy_rain_days, :integer
    # Days with a maximum of at least 40 deg C. A count, not changed by units.
    attribute :extreme_heat_days, :integer
    # Days with a minimum of at most 0 deg C. A count, not changed by units.
    attribute :extreme_cold_days, :integer
    # Hourly values that went into the month.
    attribute :hours, :integer
    # Days that went into the day counts.
    attribute :days, :integer
  end

  # One calendar year (UTC) of summary values.
  class YearlyRow < Model
    # Calendar year (UTC).
    attribute :year, :integer
    # Mean hourly temperature, deg C. With units=imperial: deg F.
    attribute :yearly_avg_temp, :float
    # Lowest hourly temperature in the year, deg C. With units=imperial: deg F.
    attribute :yearly_min_temp, :float
    # Highest hourly temperature in the year, deg C. With units=imperial: deg F.
    attribute :yearly_max_temp, :float
    # Total precipitation, mm. With units=imperial: inches.
    attribute :yearly_total_rain, :float
    # Mean wind speed, m/s. With units=imperial: mph.
    attribute :yearly_avg_wind, :float
    # Mean surface pressure, hPa. With units=imperial: inHg.
    attribute :yearly_avg_pressure, :float
    # Mean cloud cover, 0 to 100.
    attribute :yearly_avg_cloud_percent, :float
    # Total solar radiation, joules per square metre. Not changed by units.
    attribute :yearly_total_solar_j_m2, :float
    # Days with at least 1 mm of precipitation.
    attribute :rainy_days, :integer
    # Days with at least 20 mm of precipitation.
    attribute :heavy_rain_days, :integer
    # Days with a maximum of at least 40 deg C.
    attribute :extreme_heat_days, :integer
    # Days with a minimum of at most 0 deg C.
    attribute :extreme_cold_days, :integer
    # Hourly values that went into the year.
    attribute :hours, :integer
    # Days that went into the day counts.
    attribute :days, :integer
    # Months that went into the year (12 for a complete year).
    attribute :months, :integer
  end

  # Climate normal for one month.
  class NormalsMonthlyRow < Model
    # Month, 1 to 12.
    attribute :month, :integer
    # Mean daily mean temperature, deg C. With units=imperial: deg F.
    attribute :avg_temp, :float
    # Mean daily minimum temperature, deg C. With units=imperial: deg F.
    attribute :min_temp, :float
    # Mean daily maximum temperature, deg C. With units=imperial: deg F.
    attribute :max_temp, :float
    # Mean monthly precipitation total, mm. With units=imperial: inches.
    attribute :total_rain, :float
    # Mean number of days with at least 1 mm of precipitation.
    attribute :rainy_days, :float
    # Mean wind speed, m/s. With units=imperial: mph.
    attribute :avg_wind, :float
    # Mean cloud cover, 0 to 100.
    attribute :avg_cloud_pct, :float
    # Mean daily solar radiation, kWh per square metre. Not changed by units.
    attribute :avg_solar_kwh_m2, :float
    # Years of data the normal is averaged over.
    attribute :years_covered, :integer
    # Mean relative humidity, 0 to 100.
    attribute :avg_humidity_pct, :float
  end

  # Climate normal for one calendar day of the year.
  class NormalsDayRow < Model
    # Calendar day as MM-DD. 02-29 is included.
    attribute :md, :string
    # Mean daily mean temperature on this calendar day, deg C. With units=imperial: deg F.
    attribute :avg_temp, :float
    # Mean daily minimum, deg C. With units=imperial: deg F.
    attribute :min_temp, :float
    # Mean daily maximum, deg C. With units=imperial: deg F.
    attribute :max_temp, :float
    # Share of years, 0 to 1, with at least 1 mm of precipitation on this calendar day.
    attribute :rain_prob, :float
  end

  # Monthly and day-of-year climate normals.
  class NormalsData < Model
    # 12 rows, or 1 when month is given.
    attribute :monthly, [NormalsMonthlyRow]
    # 366 rows, or the days of that month when month is given.
    attribute :day_of_year, [NormalsDayRow]
  end

  # One extreme on record.
  class RecordItem < Model
    # Which extreme.
    attribute :metric, :string
    # The extreme value, in the unit given by unit.
    attribute :value, :float
    # Unit of value.
    attribute :unit, :string
    # The day the extreme occurred.
    attribute :occurred_on, :date
  end

  # The plan of the account the key belongs to.
  class MePlan < Model
    # Plan id.
    attribute :id, :string
    # Plan name.
    attribute :name, :string
    # Whether commercial use is allowed.
    attribute :commercial_use, :boolean
    # Whether a visible link back is required.
    attribute :attribution_link_required, :boolean
    # Most days one /v1/hourly call may ask for.
    attribute :hourly_max_days_per_call, :integer
    # How far back hourly data goes, in months. null for full history.
    attribute :hourly_max_age_months, :integer
  end

  # The key the call was made with.
  class MeKey < Model
    # Which credits this key spends first: "plan_first" or "topup_first".
    attribute :spend_order, :string
  end

  # Credit balance and usage.
  class MeCredits < Model
    # One-time credits for the life of the account. They never refill. null when your plan has none.
    attribute :one_time_limit, :integer
    # One-time credits left. null when your plan has none.
    attribute :one_time_remaining, :integer
    # Credits used since the account was created, on any plan.
    attribute :used_all_time, :integer
    # Credits in your plan each month. null when your plan has no monthly credits.
    attribute :monthly_limit, :integer
    # Credits used this month (UTC).
    attribute :used_this_month, :integer
    # Credits left this month. null when your plan has no monthly credits.
    attribute :remaining_this_month, :integer
    # When the monthly allowance next renews (UTC). null when your plan has no monthly allowance.
    attribute :month_resets_at, :time
    # Most credits you can use in a day. null when there is no daily credit cap.
    attribute :daily_cap, :integer
    # Credits used today (UTC).
    attribute :used_today, :integer
    # Credits left today. null when there is no daily credit cap.
    attribute :remaining_today, :integer
    # When the daily count resets.
    attribute :day_resets_at, :time
    # Bought credits left. They never expire and never reset. Calls spend your plan's credits first, then these.
    attribute :topup_balance, :integer
    # Bought credits spent so far.
    attribute :topup_used, :integer
  end

  # Per-minute request limit.
  class MeRateLimit < Model
    # Requests allowed per minute.
    attribute :per_minute, :integer
    # Requests left in the current minute.
    attribute :remaining, :integer
  end

  # Your plan, credit balance and limits.
  class MeData < Model
    attribute :plan, MePlan
    attribute :key, MeKey
    attribute :credits, MeCredits
    attribute :rate_limit, MeRateLimit
  end

  # Published coverage of one country.
  class CountryCoverage < Model
    # Lower-case two-letter country code.
    attribute :country, :string
    # First year with published data.
    attribute :first_year, :integer
    # Last day with published data.
    attribute :last_date, :date
  end

  # The countries the archive serves.
  class CoverageData < Model
    attribute :countries, [CountryCoverage]
  end

  # The unit system used for the values in a response.
  class MetaUnits < Model
    # The unit system used for the values in this response.
    attribute :system, :string
    # Temperature unit.
    attribute :temperature, :string
    # Precipitation unit.
    attribute :precipitation, :string
    # Wind speed unit.
    attribute :wind_speed, :string
    # Pressure unit.
    attribute :pressure, :string
  end

  # Response metadata: credits used and left, plus the fields each endpoint adds. Fields an endpoint does not send are null.
  class Meta < Model
    # Credits this call used. 0 on an error.
    attribute :credits, :integer
    # Credits the next call can spend: the plan's remaining allowance plus bought credits.
    attribute :credits_remaining, :integer
    # Version of the data-processing methodology. Changes only when published numbers can shift.
    attribute :methodology_version, :string
    # The search text.
    attribute :query, :string
    # The country filter, or null.
    attribute :country, :string
    # Results returned.
    attribute :count, :integer
    attribute :units, MetaUnits
    # First day.
    attribute :start, :date
    # Last day.
    attribute :end, :date
    # Rows returned.
    attribute :days, :integer
    # First day.
    attribute :date, :date
    # Timezone of the local days.
    attribute :timezone, :string
    # Rows returned.
    attribute :rows, :integer
    # The month filter, or null.
    attribute :month, :integer
  end
end
