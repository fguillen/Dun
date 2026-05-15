require "test_helper"

class BattleParticipantTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    participant = create(:battle_participant)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, participant.id)
  end

  test "validates side inclusion" do
    participant = build(:battle_participant, side: "bystander")
    refute participant.valid?
    assert participant.errors[:side].present?
  end

  test "army association is optional" do
    participant = build(:battle_participant, army: nil)
    assert participant.valid?
  end
end
