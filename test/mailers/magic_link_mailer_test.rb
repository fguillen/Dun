require "test_helper"

class MagicLinkMailerTest < ActionMailer::TestCase
  test "renders the player-scope subject and includes the raw token" do
    mail = MagicLinkMailer.with(email: "alice@example.com", raw_token: "RAW-TOKEN", scope: "player").send_link

    assert_equal [ "alice@example.com" ], mail.to
    assert_equal [ ENV.fetch("MAGIC_LINK_FROM_EMAIL") ], mail.from
    assert_equal "Your dun sign-in link", mail.subject
    assert_includes mail.body.encoded, "RAW-TOKEN"
  end

  test "renders the admin-scope subject" do
    mail = MagicLinkMailer.with(email: "boss@example.com", raw_token: "RAW-ADMIN", scope: "admin").send_link

    assert_equal "Your dun admin sign-in link", mail.subject
    assert_includes mail.body.encoded, "RAW-ADMIN"
  end
end
