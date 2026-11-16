# frozen_string_literal: true

require "pastclimate/version"
require "pastclimate/response"
require "pastclimate/errors"
require "pastclimate/model"
require "pastclimate/models"
require "pastclimate/place"
require "pastclimate/transport"
require "pastclimate/client"

# Official Ruby client for the PastClimate historical weather API.
#
#   client = PastClimate::Client.new # reads PASTCLIMATE_API_KEY
#   client.get_me.data.plan.name
module PastClimate
end
