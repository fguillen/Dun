class ApplicationController < ActionController::API
  before_action :set_current_request_id
  after_action :log_response_body

  private

  def set_current_request_id
    Current.request_id = request.request_id
  end

  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
  end

  def log_response_body
    return unless response.media_type == "application/json"
    Rails.logger.debug { "[response] #{request.method} #{request.path} → #{response.status} #{response.body}" }
  end
end
