module Players
  class SetHandle
    class HandleReservedError < StandardError; end

    def self.call(profile, handle)
      new(profile, handle).call
    end

    def initialize(profile, handle)
      @profile = profile
      @handle = handle
    end

    def call
      raise HandleLockedError if @profile.locked?
      raise HandleReservedError, "handle was retired by a deleted account; available again after 30 days" if reserved_for_deletion?

      @profile.update!(handle: @handle)
      @profile
    end

    private

    def reserved_for_deletion?
      RetiredHandle.reserved?(server_id: @profile.server_id, handle: @handle)
    end
  end
end
