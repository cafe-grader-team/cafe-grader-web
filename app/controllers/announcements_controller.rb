class AnnouncementsController < ApplicationController
  MEMBER_METHOD = %i[show edit destroy update delete_file
                     toggle_front toggle_published
                    ]

  before_action :set_announcement, only: MEMBER_METHOD
  before_action :check_valid_login

  before_action :group_editor_authorization
  before_action :can_edit_announcement, only: MEMBER_METHOD
  before_action :stimulus_controller

  # GET /announcements
  # GET /announcements.xml
  def index
    @announcements = Announcement.editable_by_user(@current_user).default_order

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render xml: @announcements }
    end
  end

  # GET /announcements/1
  # GET /announcements/1.xml
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render xml: @announcement }
    end
  end

  # GET /announcements/new
  # GET /announcements/new.xml
  def new
    @announcement = Announcement.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render xml: @announcement }
    end
  end

  # GET /announcements/1/edit
  def edit
  end

  def delete_file
    @announcement.file.purge
    redirect_to(@announcement)
  end

  # POST /announcements
  # POST /announcements.xml
  def create
    @announcement = Announcement.new(announcement_params)

    # check if the user can, and has, set group
    unless @current_user.admin?
      editor_groups = @current_user.groups_for_action(:edit)
      unless !@announcement.nil? || editor_groups.include?(@announcement.group)
        @announcement.group = editor_groups.take
      end
    end
    respond_to do |format|
      if @announcement.save
        flash[:notice] = 'Announcement was successfully created.'
        format.html { redirect_to(@announcement) }
        format.xml  { render xml: @announcement, status: :created, location: @announcement }
      else
        format.html { render action: "new" }
        format.xml  { render xml: @announcement.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /announcements/1
  # PUT /announcements/1.xml
  def update
    respond_to do |format|
      if @announcement.update(announcement_params)
        format.html { redirect_to(@announcement) }
        format.js   { }
        format.xml  { head :ok }
      else
        format.html { render action: "edit" }
        format.js   { }
        format.xml  { render xml: @announcement.errors, status: :unprocessable_entity }
      end
    end
  end

  def toggle_published
    @announcement.update(published:  !@announcement.published?)
    @toast = {title: "Annnouncement", body: "published updated"}
    render 'toggle'
  end

  def toggle_front
    @announcement.update(frontpage:  !@announcement.frontpage?)
    @toast = {title: "Announcement", body: "front updated"}
    render 'toggle'
  end

  # DELETE /announcements/1
  # DELETE /announcements/1.xml
  def destroy
    @announcement.destroy

    respond_to do |format|
      format.html { redirect_to(announcements_url) }
      format.xml  { head :ok }
    end
  end

  private
    def set_announcement
      @announcement = Announcement.find(params[:id])
    end

    def announcement_params
      params.require(:announcement).permit(:author, :body, :published, :frontpage, :contest_only, :title, :on_nav_bar, :file, :group_id, :notes)
    end

    def can_edit_announcement
      return true if @current_user.can_edit_announcement(@announcement)
      unauthorized_redirect(msg: 'You are not authorized to edit this announcement')
    end

    def stimulus_controller
      @stimulus_controller = 'announcement'
    end
end
