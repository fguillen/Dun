module Players
  class SetRealName
    def self.call(profile, real_name)
      profile.update!(real_name: real_name)
      profile
    end
  end
end
