require "test_helper"

module Api
  class HealthControllerTest < ActionDispatch::IntegrationTest
    test "returns ok JSON" do
      get "/v1/health"

      assert_response :success
      assert_equal({ "status" => "ok" }, response.parsed_body)
    end
  end
end
