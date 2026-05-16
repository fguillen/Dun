require "test_helper"

module Accounts
  class DeleteTest < ActiveSupport::TestCase
    setup do
      @player = create(:player, email: "player@example.com", name: "Alice")
      @server = create(:server)
      @profile = create(:player_profile, server: @server, player: @player, handle: "alice", real_name: "Alice Anderson")
      @profile.stats.update!(rounds_played: 3, rounds_won: 1, wonders_destroyed: 2, peak_nodes: 5)
      @world = create(:world, :active, server: @server)
      PlayerTitle.create!(player_profile: @profile, world: @world, awarded_at: Time.current)
      @api_key, = ApiKey.generate_for(owner: @player, name: "cli")
      @snapshot = LeaderboardSnapshot.create!(
        server: @server, kind: "champions", snapshot_at: Time.current,
        entries: [
          { "player_profile_id" => @profile.id, "handle" => "alice", "score" => 1, "secondary" => 0 },
          { "player_profile_id" => "other-profile", "handle" => "bob", "score" => 2, "secondary" => 1 }
        ]
      )
    end

    test "tombstones the player, anonymizes profile, retires handle, zeros stats, deletes titles, revokes keys" do
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.account.deleted") do
        Delete.call(player: @player)
      end

      @player.reload
      assert_not_nil @player.deleted_at
      assert_equal "[deleted]", @player.name
      assert_match(/\Adeleted-.+@dun\.local\z/, @player.email)

      @profile.reload
      assert_match(/\A\[deleted player /, @profile.handle)
      assert_nil @profile.real_name

      @profile.stats.reload
      PlayerProfileStats::COUNTER_COLUMNS.each { |c| assert_equal 0, @profile.stats.public_send(c).to_i, "expected #{c} to be zeroed" }

      assert_equal 0, PlayerTitle.where(player_profile_id: @profile.id).count

      assert RetiredHandle.reserved?(server_id: @server.id, handle: "alice")

      @api_key.reload
      assert_not_nil @api_key.revoked_at

      @snapshot.reload
      handles = @snapshot.entries.map { |e| e["handle"] }
      assert_equal [ "bob" ], handles

      assert_equal 1, events.size
      assert_equal @player.id, events.first[:player_id]
    end

    test "is idempotent on re-call" do
      Delete.call(player: @player)
      tombstoned_email = @player.reload.email
      Delete.call(player: @player)
      assert_equal tombstoned_email, @player.reload.email
    end
  end
end
