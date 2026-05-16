# frozen_string_literal: true

class BackfillPlayerProfileStats < ActiveRecord::Migration[8.1]
  def up
    PlayerProfile.find_each do |profile|
      next if PlayerProfileStats.exists?(player_profile_id: profile.id)
      PlayerProfileStats.create!(player_profile_id: profile.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
