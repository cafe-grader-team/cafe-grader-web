class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_user!, only: [:login]

  # Bearer tokens cannot be revoked server-side (no jti/token-version
  # check), so the TTL is the entire exposure window for a leaked token.
  # Keep it within a working day.
  TOKEN_TTL = 12.hours

  # Brute-force throttle, per client IP. The session login form is not
  # scriptable in the same way; this endpoint is.
  rate_limit to: 10, within: 1.minute, only: :login,
             with: -> { render json: { error: "Too many login attempts; try again later" }, status: :too_many_requests }

  def login
    user = User.authenticate(params[:login], params[:password])
    unless user
      render json: { error: "Invalid login or password" }, status: :unauthorized and return
    end

    # The web flow lets a disabled user authenticate and then blocks every
    # request (check_valid_login); issuing no token at all is the API
    # equivalent. BaseController enforces the same gate per-request.
    unless user.enabled? || user.admin?
      render json: { error: "Account is disabled" }, status: :forbidden and return
    end

    expires_at = TOKEN_TTL.from_now
    token = JWT.encode(
      { user_id: user.id, exp: expires_at.to_i, iat: Time.now.to_i },
      jwt_secret,
      "HS256"
    )

    render json: {
      token: token,
      expires_at: expires_at.iso8601,
      user: {
        id: user.id,
        login: user.login,
        full_name: user.full_name
      }
    }
  end
end
