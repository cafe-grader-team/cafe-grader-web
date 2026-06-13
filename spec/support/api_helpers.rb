module ApiHelpers
  def jwt_token_for(user)
    JWT.encode(
      { user_id: user.id, exp: 7.days.from_now.to_i, iat: Time.now.to_i },
      Rails.application.secret_key_base,
      "HS256"
    )
  end

  def auth_header_for(user)
    { "Authorization" => "Bearer #{jwt_token_for(user)}" }
  end

  def set_grader_config(key, value)
    conf = GraderConfiguration.find_by(key: key)
    conf.update!(value: value.to_s) if conf
    GraderConfiguration.instance_variable_set(:@config_cache, nil)
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
