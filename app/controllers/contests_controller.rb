class ContestsController < ApplicationController

  before_filter :admin_authorization

  in_place_edit_for :contest, :title
  in_place_edit_for :contest, :enabled

  # GET /contests
  # GET /contests.xml
  def index
    @contests = Contest.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @contests }
    end
  end

  # GET /contests/1
  # GET /contests/1.xml
  def show
    @contest = Contest.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @contest }
    end
  end

  # GET /contests/new
  # GET /contests/new.xml
  def new
    @contest = Contest.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @contest }
    end
  end

  # GET /contests/1/edit
  def edit
    @contest = Contest.find(params[:id])
  end

  # POST /contests
  # POST /contests.xml
  def create
    @contest = Contest.new(params[:contest].permit( :name, :title, :enabled, :commit))

    respond_to do |format|
      if @contest.save
        flash[:notice] = 'Contest was successfully created.'
        format.html { redirect_to(@contest) }
        format.xml  { render :xml => @contest, :status => :created, :location => @contest }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @contest.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /contests/1
  # PUT /contests/1.xml
  def update
    @contest = Contest.find(params[:id])

    respond_to do |format|
      if @contest.update_attributes(contests_params)
        flash[:notice] = 'Contest was successfully updated.'
        format.html { redirect_to(@contest) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @contest.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /contests/1
  # DELETE /contests/1.xml
  def destroy
    @contest = Contest.find(params[:id])
    @contest.destroy

    respond_to do |format|
      format.html { redirect_to(contests_url) }
      format.xml  { head :ok }
    end
  end

  private

    def contests_params
      params.require(:contest).permit(:title,:enabled,:name)
    end

end
