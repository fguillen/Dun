module Servers
  class Configure
    ALLOWED = %i[name max_concurrent_worlds max_worlds_per_account].freeze

    def self.call(server, attrs)
      new(server, attrs).call
    end

    def initialize(server, attrs)
      @server = server
      @attrs = attrs.to_h.symbolize_keys.slice(*ALLOWED)
    end

    def call
      @server.update!(@attrs)
      @server
    end
  end
end
