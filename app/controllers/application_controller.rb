class ApplicationController < ActionController::API
  before_action :set_current_request_id

  private

  def set_current_request_id
    Current.request_id = request.request_id
  end

  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
  end
end
