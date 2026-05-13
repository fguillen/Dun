class MagicLinkMailer < ApplicationMailer
  def send_link
    @email = params.fetch(:email)
    @raw_token = params.fetch(:raw_token)
    @scope = params.fetch(:scope).to_s

    subject = @scope == "admin" ? "Your dun admin sign-in link" : "Your dun sign-in link"
    mail(to: @email, subject: subject)
  end
end
