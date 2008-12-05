class UserAdminController < ApplicationController

  before_filter :admin_authorization

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
    @user.activated = true
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
      items = line.chomp.split(',')
      if items.length==4
        user = User.new
        user.login = items[0]
        user.full_name = items[1]
        user.alias = items[2]
        user.password = items[3]
        user.password_confirmation = items[3]
        user.activated = true
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
      ustat[1] = u.full_name
      @problems.each do |p|
	sub = Submission.find_last_by_user_and_problem(u.id,p.id)
	if (sub!=nil) and (sub.points!=nil) 
	  ustat << [(sub.points.to_f*100/p.full_score).round, (sub.points>=p.full_score)]
	else
	  ustat << [0,false]
	end
      end
      @scorearray << ustat
    end
  end

  def import
    if params[:file]==''
      flash[:notice] = 'Error importing no file'
      redirect_to :action => 'list' and return
    end
    import_from_file(params[:file])
  end

  protected

  def import_from_file(f)
    data_hash = YAML.load(f)
    @import_log = ""

    country_data = data_hash[:countries]
    site_data = data_hash[:sites]
    user_data = data_hash[:users]

    # import country
    countries = {}
    country_data.each_pair do |id,country|
      c = Country.find_by_name(country[:name])
      if c!=nil
        countries[id] = c
        @import_log << "Found #{country[:name]}\n"
      else
        countries[id] = Country.new(:name => country[:name])
        countries[id].save
        @import_log << "Created #{country[:name]}\n"
      end
    end

    # import sites
    sites = {}
    site_data.each_pair do |id,site|
      s = Site.find_by_name(site[:name])
      if s!=nil
        @import_log << "Found #{site[:name]}\n"
      else
        s = Site.new(:name => site[:name])
        @import_log << "Created #{site[:name]}\n"
      end
      s.password = site[:password]
      s.country = countries[site[:country_id]]
      s.save
      sites[id] = s
    end

    # import users
    user_data.each_pair do |id,user|
      u = User.find_by_login(user[:login])
      if u!=nil
        @import_log << "Found #{user[:login]}\n"
      else
        u = User.new(:login => user[:login])
        @import_log << "Created #{user[:login]}\n"
      end
      u.full_name = user[:name]
      u.password = user[:password]
      u.country = countries[user[:country_id]]
      u.site = sites[user[:site_id]]
      u.save
    end

  end

end
