module Wreckers
  # Credits the player who landed the killing blow on a destroyed Wonder
  # with `wonders_destroyed`. Per §17.4, the killing blow is the attack that
  # brings Wonder HP to 0; ties (multiple HP=0 damage events) are broken by
  # (1) larger Trebuchet contribution, then (2) earliest dispatch.
  class Attribute
    def self.call(wonder:)
      new(wonder: wonder).call
    end

    def initialize(wonder:)
      @wonder = wonder
    end

    def call
      killing = WonderDamageEvent
        .where(wonder_id: @wonder.id, hp_after: 0)
        .order(trebuchets_surviving: :desc, occurred_at: :asc)
        .first
      return nil if killing.nil?

      attacker_kingdom = Kingdom.find_by(id: killing.attacker_kingdom_id)
      return nil if attacker_kingdom.nil?

      profile = attacker_kingdom.player_profile
      return nil if profile.nil?

      Profiles::Increment.call(player_profile: profile, deltas: { wonders_destroyed: 1 })
      profile
    end
  end
end
