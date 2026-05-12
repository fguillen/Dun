Rails.application.configure do
  config.lograge.enabled = !Rails.env.test?
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.base_controller_class = [ "ActionController::API", "ActionController::Base" ]

  config.lograge.custom_options = lambda do |event|
    { request_id: event.payload[:request_id], params: event.payload[:params]&.except(*%w[controller action format authenticity_token]), time: Time.zone.now.iso8601 }
  end
end
