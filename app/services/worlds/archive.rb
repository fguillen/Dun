module Worlds
  class Archive
    class WorldNotArchivable < StandardError; end

    def self.call(world, winner_kingdom: nil, wonder_name: nil)
      new(world, winner_kingdom: winner_kingdom, wonder_name: wonder_name).call
    end

    def initialize(world, winner_kingdom:, wonder_name:)
      @world = world
      @winner_kingdom = winner_kingdom
      @wonder_name = wonder_name
    end

    def call
      raise WorldNotArchivable, "world #{@world.id} is already archived" if @world.archived?
      raise WorldNotArchivable, "world #{@world.id} is #{@world.status}; only active worlds can be archived" unless @world.active?

      @world.update!(
        status: "archived",
        archived_at: Time.current,
        winner_kingdom: @winner_kingdom,
        wonder_name: @wonder_name
      )
      @world
    end
  end
end
