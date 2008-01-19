class UserAdminController < ApplicationController

  before_filter :authenticate, :authorization

  def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, :create, :update ],
         :redirect_to => { :action => :list }

  def list
    @users = User.find(:all)
  end

  def show
    @user = User.find(params[:id])
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = 'User was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def create_from_list
    lines = params[:user_list]
    lines.split("\n").each do |line|
      items = line.split
      if items.length==5
        user = User.new
        user.login = items[0]
        user.full_name = "#{items[1]} #{items[2]}"
        user.alias = items[3]
        user.password = items[4]
        user.password_confirmation = items[4]
        user.save
      end
    end
    redirect_to :action => 'list'
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update_attributes(params[:user])
      flash[:notice] = 'User was successfully updated.'
      redirect_to :action => 'show', :id => @user
    else
      render :action => 'edit'
    end
  end

  def destroy
    User.find(params[:id]).destroy
    redirect_to :action => 'list'
  end

  def user_stat
    @problems = Problem.find_available_problems
    @users = User.find(:all)
    @scorearray = Array.new
    @users.each do |u|
      ustat = Array.new
      ustat[0] = u.login
      @problems.each do |p|
	c, sub = Submission.find_by_user_and_problem(u.id,p.id)
	if (c!=0) and (sub.points!=nil) 
	  ustat << [sub.points, (sub.points>=p.full_score)]
	else
	  ustat << [0,false]
	end
      end
      @scorearray << ustat
    end
  end
end
