require "test_helper"

module Stockpile
  class CheckpointTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      @kingdom.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
        "checkpoint_at" => 1.hour.ago.iso8601
      })
    end

    test "flushes accrued production and advances checkpoint_at" do
      Checkpoint.call(@kingdom)
      @kingdom.reload
      assert @kingdom.stockpiles["wood"].to_i.positive?
      checkpoint = Time.iso8601(@kingdom.stockpiles["checkpoint_at"])
      assert_in_delta Time.current, checkpoint, 5
    end

    test "emits dun.stockpile.checkpointed notification" do
      captured = nil
      ActiveSupport::Notifications.subscribed(
        ->(_name, _start, _finish, _id, payload) { captured = payload },
        "dun.stockpile.checkpointed"
      ) do
        Checkpoint.call(@kingdom)
      end

      assert_equal @kingdom.id, captured[:kingdom_id]
      assert_equal @kingdom.world_id, captured[:world_id]
      assert captured[:checkpoint_at].present?
    end
  end
end
