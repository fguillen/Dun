module Api
  class BaseController < ApplicationController
    include Authentication

    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_invalid
    rescue_from ActionController::ParameterMissing, with: :handle_param_missing

    before_action :require_player

    private

    def render_error(code:, message:, status:, retry_after: nil)
      response.set_header("Retry-After", retry_after.to_s) if retry_after
      payload = { error: { code: code.to_s, message: message } }
      payload[:error][:retry_after] = retry_after if retry_after
      render json: payload, status: status
    end

    def handle_not_found(error)
      Rails.logger.debug "Record not found: #{error.model}, message: #{error.message}"
      render_error(code: "not_found", message: "Resource not found", status: :not_found)
    end

    def handle_invalid(error)
      render_error(code: "invalid", message: error.record.errors.full_messages.join(", "), status: :unprocessable_entity)
    end

    def handle_param_missing(error)
      render_error(code: "param_missing", message: error.message, status: :unprocessable_entity)
    end
  end
end
