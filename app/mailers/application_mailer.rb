class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAGIC_LINK_FROM_EMAIL") }
  layout "mailer"
end
