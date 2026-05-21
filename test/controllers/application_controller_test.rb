require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  def with_captured_logger(level:)
    original = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io).tap { |l| l.level = level }
    yield io
  ensure
    Rails.logger = original
  end

  test "logs response body at debug level" do
    with_captured_logger(level: Logger::DEBUG) do |io|
      get "/v1/health"

      assert_response :success
      assert_match(/\[response\] GET \/v1\/health → 200/, io.string)
      assert_match(/"status":"ok"/, io.string)
    end
  end

  test "does not log response body when level is above debug" do
    with_captured_logger(level: Logger::INFO) do |io|
      get "/v1/health"

      assert_response :success
      assert_no_match(/\[response\]/, io.string)
    end
  end
end
