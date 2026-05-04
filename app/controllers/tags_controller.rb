class TagsController < ApplicationController
  before_action :stimulus_controller
  before_action :admin_authorization
  before_action :set_tag, only: [:edit, :update, :destroy, :toggle_public]

  # GET /tags
  def index
    @tags = Tag.all
  end

  def index_query
    @tags = Tag.all
  end

  # GET /tags/new
  def new
    @tag = Tag.new
  end

  # GET /tags/1/edit
  def edit
  end

  # POST /tags
  def create
    @tag = Tag.new(tag_params)

    if @tag.save
      redirect_to tags_path, notice: 'Tag was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /tags/1
  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "Tag #{@tag.name} was successfully updated."
    else
      render :edit
    end
  end

  # POST /tags/1/toggle_public
  def toggle_public
    @tag.update(public: !@tag.public)
    @toast = {title: "Tag #{@tag.name}", body: "public updated"}
    render 'turbo_toast'
  end

  # DELETE /tags/1
  def destroy
    # remove any association
    ProblemTag.where(tag_id: @tag.id).destroy_all
    @tag.destroy
    redirect_to tags_url, notice: 'Tag was successfully destroyed.'
  end

  protected

  private
    def stimulus_controller
      @stimulus_controller = 'tag'
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_tag
      @tag = Tag.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def tag_params
      params.require(:tag).permit(:name, :description, :public, :color, :kind, :params)
    end
end
