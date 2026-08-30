class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_user!, only: [:login]

  # Bearer tokens cannot be revoked server-side (no jti/token-version
  # check), so the TTL is the entire exposure window for a leaked token.
  # Keep it within a working day.
  TOKEN_TTL = 12.hours

  # Brute-force protection shared with the web login: one pooled per-IP /
  # per-account failure budget across both doors (see LoginThrottling).
  include LoginThrottling

  def login
    if login_throttled?
      render json: { error: "Too many failed login attempts; try again later" },
             status: :too_many_requests and return
    end

    user = User.authenticate(params[:login], params[:password])
    unless user
      record_login_failure!
      render json: { error: "Invalid login or password" }, status: :unauthorized and return
    end
    clear_login_failures!

    # The web flow lets a disabled user authenticate and then blocks every
    # request (check_valid_login); issuing no token at all is the API
    # equivalent. BaseController enforces the same gate per-request.
    unless user.enabled? || user.admin?
      render json: { error: "Account is disabled" }, status: :forbidden and return
    end

    # Single-user lockdown: don't issue tokens to non-admins at all.
    # BaseController enforces the same gate per-request for tokens that
    # already exist.
    if GraderConfiguration.single_user_mode? && !user.admin?
      render json: { error: "The system is in single-user mode and does not permit usage at this time" },
             status: :forbidden and return
    end

    # IP whitelist: the web lets the login succeed and then blocks every
    # request from a non-whitelisted IP (check_valid_login); issuing no token
    # is the API equivalent. BaseController re-checks on every request.
    unless user.allowed_from_ip?(request.remote_ip)
      render json: { error: "Your IP is not allowed to log in at this time" },
             status: :forbidden and return
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
