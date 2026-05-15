ENV["RAILS_ENV"] ||= "test"
ENV["ADMIN_BOOTSTRAP_EMAIL"] ||= "admin@example.com"
ENV["ADMIN_BOOTSTRAP_NAME"] ||= "Bootstrap Admin"
ENV["MAGIC_LINK_FROM_EMAIL"] ||= "no-reply@example.com"

require_relative "../config/environment"
require "rails/test_help"
require "factory_bot_rails"
require "mocha/minitest"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("test/test_helpers/**/*.rb")].each { |f| require f }

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  include FactoryBot::Syntax::Methods
  include ActiveSupport::Testing::TimeHelpers
end

class ActionDispatch::IntegrationTest
  include AuthenticationHelpers
end

class ActionController::TestCase
  include AuthenticationHelpers
end
