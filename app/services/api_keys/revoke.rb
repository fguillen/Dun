module ApiKeys
  class Revoke
    def self.call(api_key)
      api_key.revoke!
      api_key
    end
  end
end
