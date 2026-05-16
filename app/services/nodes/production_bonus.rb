module Nodes
  # Per-resource flat production bonus from a kingdom's owned nodes. Mirrors
  # the inline sum used by `Production::RateFor`; exposed as a service so the
  # kingdom show endpoint can render the bonus alongside the building rate
  # without duplicating the query.
  class ProductionBonus
    def self.call(kingdom)
      Kingdom::RESOURCES.index_with do |resource|
        kingdom.owned_nodes.where(resource: resource).sum(:base_rate).to_i
      end
    end
  end
end
