module Api
  class BattlesController < Api::BaseController
    def show
      battle = Battle.find(params[:id])
      ensure_visible!(battle)
      render json: {
        battle: self.class.serialize(battle),
        participants: battle.participants.map { |p| self.class.serialize_participant(p) }
      }
    end

    def self.serialize(battle)
      {
        id: battle.id,
        world_id: battle.world_id,
        region_id: battle.region_id,
        attacker_kingdom_id: battle.attacker_kingdom_id,
        defender_kingdom_id: battle.defender_kingdom_id,
        attacker_title: title_for(battle.attacker_kingdom),
        defender_title: title_for(battle.defender_kingdom),
        march_order_id: battle.march_order_id,
        outcome: battle.outcome,
        loot: battle.loot,
        log: battle.log,
        started_at: battle.started_at&.iso8601,
        ended_at: battle.ended_at&.iso8601
      }
    end

    def self.title_for(kingdom)
      return nil if kingdom.nil?
      profile = kingdom.player_profile
      return nil if profile.nil?
      ::Titles::Render.call(profile)
    end

    def self.serialize_participant(participant)
      {
        id: participant.id,
        battle_id: participant.battle_id,
        kingdom_id: participant.kingdom_id,
        army_id: participant.army_id,
        side: participant.side,
        starting_composition: participant.starting_composition,
        ending_composition: participant.ending_composition,
        casualties: participant.casualties
      }
    end

    private

    def ensure_visible!(battle)
      profile = PlayerProfile.find_by(server_id: battle.world.server_id, player_id: Current.player.id)
      raise ActiveRecord::RecordNotFound, "battle not visible" if profile.nil?

      owned_kingdom_ids = Kingdom.where(world_id: battle.world_id, player_profile_id: profile.id).pluck(:id)
      visible = owned_kingdom_ids.include?(battle.attacker_kingdom_id) ||
                owned_kingdom_ids.include?(battle.defender_kingdom_id)
      raise ActiveRecord::RecordNotFound, "battle not visible" unless visible
    end
  end
end
