module Accounts
  # §17.4 account deletion: irreversible, immediate real-name purge, handles
  # anonymized in player profiles + reserved 30 days, stats zeroed, titles
  # removed, leaderboard entries scrubbed, ApiKeys revoked.
  class Delete
    DELETED_HANDLE_PREFIX = "[deleted player".freeze
    TOMBSTONE_EMAIL_HOST = "dun.local".freeze

    def self.call(player:, at: Time.current)
      new(player: player, at: at).call
    end

    def initialize(player:, at:)
      @player = player
      @at = at
    end

    def call
      ActiveRecord::Base.transaction do
        player = Player.lock.find(@player.id)
        return player if player.deleted_at.present?

        retire_profiles(player)
        scrub_leaderboards(player)
        tombstone_player(player)
        revoke_api_keys(player)

        ActiveSupport::Notifications.instrument(
          "dun.account.deleted",
          player_id: player.id
        )

        player
      end
    end

    private

    def retire_profiles(player)
      player.player_profiles.includes(:stats).each do |profile|
        if profile.handle.present?
          RetiredHandle.find_or_create_by!(server_id: profile.server_id, handle_lower: profile.handle.to_s.downcase) do |r|
            r.freed_at = @at
          end
        end

        # Skip validations: the placeholder uses bracket chars that the
        # handle format regex rejects, but the DB column is citext + the
        # unique index, so this is safe.
        profile.update_columns(
          handle: "#{DELETED_HANDLE_PREFIX} ##{profile.id}]",
          real_name: nil
        )

        PlayerProfileStats
          .where(player_profile_id: profile.id)
          .update_all(PlayerProfileStats::COUNTER_COLUMNS.map { |c| "#{c} = 0" }.join(", "))

        PlayerTitle.where(player_profile_id: profile.id).delete_all
      end
    end

    def scrub_leaderboards(player)
      profile_ids = player.player_profiles.pluck(:id)
      return if profile_ids.empty?

      LeaderboardSnapshot.find_each do |snapshot|
        original = snapshot.entries
        next unless original.is_a?(Array)
        kept = original.reject { |entry| entry.is_a?(Hash) && profile_ids.include?(entry["player_profile_id"]) }
        snapshot.update!(entries: kept) if kept.size != original.size
      end
    end

    def tombstone_player(player)
      player.update!(
        deleted_at: @at,
        email: "deleted-#{player.id}@#{TOMBSTONE_EMAIL_HOST}",
        name: "[deleted]"
      )
    end

    def revoke_api_keys(player)
      ApiKey.where(owner_type: "Player", owner_id: player.id, revoked_at: nil).find_each(&:revoke!)
    end
  end
end
