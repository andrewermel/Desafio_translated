require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'vcr'
require 'dotenv/load'
require_relative '../app'

ENV['RACK_ENV'] = 'test'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data('<SLACK_BOT_TOKEN>') { ENV['SLACK_BOT_TOKEN'] }
  config.filter_sensitive_data('<LLM_API_KEY>') { ENV['LLM_API_KEY'] }
end

RSpec.configure do |config|
  config.include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end