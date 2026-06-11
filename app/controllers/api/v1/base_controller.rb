class Api::V1::BaseController < ActionController::API
  include ActiveStorage::SetCurrent

  before_action :read_grader_configuration
  before_action :authenticate_api_user!

  private

  def read_grader_configuration
    @grader_configuration = GraderConfiguration.read_config if @grader_configuration.nil?
  end

  def authenticate_api_user!
    token = request.headers["Authorization"]&.split(" ")&.last
    unless token
      render json: { error: "Missing authorization token" }, status: :unauthorized and return
    end

    payload = JWT.decode(token, jwt_secret, true, algorithm: "HS256").first
    @current_user = User.includes(:roles).find(payload["user_id"])

    # Same per-request gate as the web side (ApplicationController#check_valid_login):
    # a disabled account holds a decodable token until it expires, so the flag
    # must be enforced on every request, not only at login.
    unless @current_user.enabled? || @current_user.admin?
      @current_user = nil
      render json: { error: "Account is disabled" }, status: :forbidden and return
    end

    # Actor for AuditLog rows created during this request (Auditable reads
    # Current.user / Current.ip). Mirrors ApplicationController#set_current_audit_context;
    # without this every API mutation of an audited model is anonymous.
    Current.user = @current_user
    Current.ip = request.remote_ip
  rescue JWT::ExpiredSignature
    render json: { error: "Token has expired" }, status: :unauthorized
  rescue JWT::DecodeError
    render json: { error: "Invalid token" }, status: :unauthorized
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User not found" }, status: :unauthorized
  end

  def current_user
    @current_user
  end

  # Mirrors the web admin_authorization filter. Works both as a
  # before_action and inline (`return unless require_admin!`).
  def require_admin!
    return true if current_user.admin?
    render json: { error: "Admin role required" }, status: :forbidden
    false
  end

  # Mirrors the web group_editor_authorization filter: admins or editors
  # of at least one group.
  def require_editor!
    return true if current_user.admin? || current_user.groups_for_action(:edit).any?
    render json: { error: "Group editor role required" }, status: :forbidden
    false
  end

  def render_validation_errors(record)
    render json: { error: "Validation failed", details: record.errors.full_messages },
           status: :unprocessable_entity
  end

  def jwt_secret
    Rails.application.secret_key_base
  end

  def render_not_found(resource = "Resource", hint: nil)
    body = { error: "#{resource} not found" }
    body[:hint] = hint if hint
    render json: body, status: :not_found
  end
end
