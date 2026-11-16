# frozen_string_literal: true

require_relative "lib/pastclimate/version"

Gem::Specification.new do |spec|
  spec.name = "pastclimate"
  spec.version = PastClimate::VERSION
  spec.authors = ["PastClimate"]

  spec.summary = "Official Ruby client for the PastClimate historical weather API."
  spec.description = "Daily, hourly, monthly and yearly weather, climate normals and records for places around the world. " \
                     "Typed responses, typed errors, automatic retries, and no runtime dependencies."
  spec.homepage = "https://developer.pastclimate.com/api/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://developer.pastclimate.com/api/",
    # Placeholder: point this at the real repository before publishing.
    "source_code_uri" => "https://github.com/pastclimate/pastclimate-ruby",
    "changelog_uri" => "https://github.com/pastclimate/pastclimate-ruby/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rake", ">= 13.0"
end
