class GroupsController < ApplicationController
  before_action :set_group, only: [:show, :edit, :update, :destroy,
                                   :add_user, :remove_user,
                                   :add_problem, :remove_problem,
                                  ]
  before_action :authenticate, :admin_authorization

  # GET /groups
  def index
    @groups = Group.all
  end

  # GET /groups/1
  def show
  end

  # GET /groups/new
  def new
    @group = Group.new
  end

  # GET /groups/1/edit
  def edit
  end

  # POST /groups
  def create
    @group = Group.new(group_params)

    if @group.save
      redirect_to @group, notice: 'Group was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /groups/1
  def update
    if @group.update(group_params)
      redirect_to @group, notice: 'Group was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /groups/1
  def destroy
    @group.destroy
    redirect_to groups_url, notice: 'Group was successfully destroyed.'
  end

  def remove_user
    user = User.find(params[:user_id])
    @group.users.delete(user)
    redirect_to group_path(@group), flash: {success: "User #{user.login} was removed from the group #{@group.name}"}
  end

  def add_user
    user = User.find(params[:user_id])
    begin
      @group.users << user
      redirect_to group_path(@group), flash: { success: "User #{user.login} was add to the group #{@group.name}"}
    rescue => e
      redirect_to group_path(@group), alert: e.message
    end
  end

  def remove_problem
    problem = Problem.find(params[:problem_id])
    @group.problems.delete(problem)
    redirect_to group_path(@group), flash: {success: "Problem #{problem.name} was removed from the group #{@group.name}" }
  end

  def add_problem
    problem = Problem.find(params[:problem_id])
    begin
      @group.problems << problem
      redirect_to group_path(@group), flash: {success: "Problem #{problem.name} was add to the group #{@group.name}" }
    rescue => e
      redirect_to group_path(@group), alert: e.message
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_group
      @group = Group.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def group_params
      params.require(:group).permit(:name, :description)
    end
end
