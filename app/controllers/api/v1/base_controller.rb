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

  def jwt_secret
    Rails.application.secret_key_base
  end

  def render_not_found(resource = "Resource", hint: nil)
    body = { error: "#{resource} not found" }
    body[:hint] = hint if hint
    render json: body, status: :not_found
  end
end
