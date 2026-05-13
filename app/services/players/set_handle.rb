module Players
  class SetHandle
    def self.call(profile, handle)
      new(profile, handle).call
    end

    def initialize(profile, handle)
      @profile = profile
      @handle = handle
    end

    def call
      raise HandleLockedError if @profile.locked?

      @profile.update!(handle: @handle)
      @profile
    end
  end
end
