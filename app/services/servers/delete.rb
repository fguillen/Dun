module Servers
  class Delete
    def self.call(server)
      new(server).call
    end

    def initialize(server)
      @server = server
    end

    def call
      ActiveRecord::Base.transaction { @server.destroy! }
    end
  end
end
