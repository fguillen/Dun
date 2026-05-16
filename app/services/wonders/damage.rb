module Wonders
  # Applies Trebuchet damage to a Wonder. 50 HP per surviving Trebuchet
  # (§16.2). Records an audit row and destroys the Wonder if HP reaches 0.
  class Damage
    DAMAGE_PER_TREBUCHET = 50

    def self.call(wonder:, attacker_kingdom:, trebuchets_surviving:, battle: nil)
      new(
        wonder: wonder,
        attacker_kingdom: attacker_kingdom,
        trebuchets_surviving: trebuchets_surviving.to_i,
        battle: battle
      ).call
    end

    def initialize(wonder:, attacker_kingdom:, trebuchets_surviving:, battle:)
      @wonder = wonder
      @attacker_kingdom = attacker_kingdom
      @trebuchets_surviving = trebuchets_surviving
      @battle = battle
    end

    def call
      return @wonder if @trebuchets_surviving <= 0

      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        return wonder unless Wonder::LIVE_STATUSES.include?(wonder.status)

        Wonders::ApplyConstruction.call(wonder: wonder)
        wonder.reload

        damage = DAMAGE_PER_TREBUCHET * @trebuchets_surviving
        hp_before = wonder.hp
        hp_after = [ hp_before - damage, 0 ].max

        WonderDamageEvent.create!(
          wonder: wonder,
          attacker_kingdom: @attacker_kingdom,
          battle: @battle,
          trebuchets_surviving: @trebuchets_surviving,
          hp_before: hp_before,
          hp_after: hp_after,
          occurred_at: Time.current
        )

        wonder.update!(hp: hp_after)

        ActiveSupport::Notifications.instrument(
          "dun.wonder.damaged",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          attacker_kingdom_id: @attacker_kingdom.id,
          hp_before: hp_before,
          hp_after: hp_after,
          damage: hp_before - hp_after
        )

        Wonders::Destroy.call(wonder: wonder, reason: "damage") if hp_after.zero?

        wonder.reload
      end
    end
  end
end
