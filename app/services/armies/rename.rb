module Armies
  class Rename
    class NameTaken < StandardError; end

    def self.call(army:, name:)
      new(army: army, name: name).call
    end

    def initialize(army:, name:)
      @army = army
      @name = name
    end

    def call
      ActiveRecord::Base.transaction do
        army = Army.lock.find(@army.id)
        army.name = @name

        unless army.valid?
          if army.errors[:name].any? { |msg| msg.match?(/taken/i) }
            raise NameTaken, "name '#{@name}' is already used by another army in this kingdom"
          end
          raise ActiveRecord::RecordInvalid.new(army)
        end

        army.save!

        ActiveSupport::Notifications.instrument(
          "dun.army.renamed",
          world_id: army.kingdom.world_id,
          kingdom_id: army.kingdom_id,
          army_id: army.id,
          name: army.name
        )

        army
      end
    end
  end
end
