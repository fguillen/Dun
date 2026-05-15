require "test_helper"

class BattleTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    battle = create(:battle)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, battle.id)
  end

  test "validates outcome inclusion" do
    battle = build(:battle, outcome: "draw")
    refute battle.valid?
    assert battle.errors[:outcome].present?
  end

  test "validates timestamps presence" do
    battle = build(:battle, started_at: nil, ended_at: nil)
    refute battle.valid?
    assert battle.errors[:started_at].present?
    assert battle.errors[:ended_at].present?
  end

  test "involving scope matches when kingdom is attacker or defender" do
    battle = create(:battle)
    assert_includes Battle.involving(battle.attacker_kingdom_id), battle
    assert_includes Battle.involving(battle.defender_kingdom_id), battle
    refute_includes Battle.involving(create(:kingdom).id), battle
  end

  test "participants are destroyed with the battle" do
    battle = create(:battle)
    create(:battle_participant, battle: battle, kingdom: battle.attacker_kingdom, side: "attacker")
    create(:battle_participant, battle: battle, kingdom: battle.defender_kingdom, side: "defender")
    assert_equal 2, battle.participants.count
    battle.destroy!
    assert_equal 0, BattleParticipant.where(battle_id: battle.id).count
  end
end
