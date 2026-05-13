module AuthenticationHelpers
  # Issues a fresh ApiKey for the given Player and sets the Authorization header
  # for subsequent requests in the same test. Returns the raw token.
  def authenticate_as_player(player)
    _key, raw = ApiKey.generate_for(owner: player)
    @_auth_header = { "Authorization" => "Bearer #{raw}" }
    raw
  end

  def authenticate_as_admin(admin)
    _key, raw = ApiKey.generate_for(owner: admin)
    @_auth_header = { "Authorization" => "Bearer #{raw}" }
    raw
  end

  def auth_headers
    @_auth_header || {}
  end

  %i[get post patch put delete].each do |verb|
    define_method("#{verb}_auth") do |path, **opts|
      headers = opts.fetch(:headers, {}).merge(auth_headers)
      send(verb, path, **opts.merge(headers: headers))
    end
  end
end
