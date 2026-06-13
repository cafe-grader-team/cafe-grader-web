class Api::V1::UsersController < Api::V1::BaseController
  before_action :require_admin!, except: [:me]
  before_action :set_user, only: [:show, :update, :destroy]

  def me
    render json: {
      id: current_user.id,
      login: current_user.login,
      full_name: current_user.full_name,
      alias: current_user.alias,
      email: current_user.email,
      section: current_user.section,
      remark: current_user.remark,
      admin: current_user.admin?
    }
  end

  # GET /api/v1/users — admin only
  def index
    users = User.order(:login)
    if params[:q].present?
      q = "%#{User.sanitize_sql_like(params[:q])}%"
      users = users.where("login LIKE :q OR full_name LIKE :q", q: q)
    end

    page = params[:page].to_i.clamp(1, 1_000_000)
    per_page = (params[:per_page].presence || 50).to_i.clamp(1, 200)
    total = users.count

    render json: {
      users: users.offset((page - 1) * per_page).limit(per_page).includes(:roles).map { |u| user_json(u) },
      meta: { page: page, per_page: per_page, total: total }
    }
  end

  # GET /api/v1/users/:id
  def show
    render json: user_json(@user)
  end

  # POST /api/v1/users
  def create
    @user = User.new(user_params)
    @user.activated = true # mirrors the web UserAdminController#create

    if @user.save
      render json: user_json(@user), status: :created
    else
      render_validation_errors(@user)
    end
  end

  # PATCH /api/v1/users/:id
  def update
    attrs = user_params
    # a blank password means "don't change it", not "set it to blank"
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    if @user.update(attrs)
      render json: user_json(@user)
    else
      render_validation_errors(@user)
    end
  end

  # DELETE /api/v1/users/:id
  def destroy
    if @user == current_user
      render json: { error: "You cannot delete your own account" },
             status: :unprocessable_entity and return
    end

    @user.destroy
    head :no_content
  rescue ActiveRecord::InvalidForeignKey
    render json: { error: "User has dependent records and cannot be deleted" }, status: :conflict
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end

  # same whitelist as the web UserAdminController. Roles are deliberately
  # not settable through the API (web modify_role only).
  def user_params
    params.require(:user).permit(:login, :password, :password_confirmation,
                                 :email, :alias, :full_name, :remark, :enabled,
                                 group_ids: [])
  end

  def user_json(user)
    {
      id: user.id,
      login: user.login,
      full_name: user.full_name,
      alias: user.alias,
      email: user.email,
      remark: user.remark,
      enabled: user.enabled,
      activated: user.activated,
      roles: user.roles.map(&:name),
      group_ids: user.group_ids
    }
  end
end
