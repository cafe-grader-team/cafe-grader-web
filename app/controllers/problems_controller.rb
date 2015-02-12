class ProblemsController < ApplicationController

  before_filter :authenticate, :authorization

  in_place_edit_for :problem, :name
  in_place_edit_for :problem, :full_name
  in_place_edit_for :problem, :full_score

  def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, 
                                      :create, :quick_create,
                                      :do_manage,
                                      :do_import,
                                      :update ],
         :redirect_to => { :action => :list }

  def list
    @problems = Problem.find(:all, :order => 'date_added DESC')
  end

  def show
    @problem = Problem.find(params[:id])
  end

  def new
    @problem = Problem.new
    @description = nil
  end

  def create
    @problem = Problem.new(params[:problem])
    @description = Description.new(params[:description])
    if @description.body!=''
      if !@description.save
        render :action => new and return
      end
    else
      @description = nil
    end
    @problem.description = @description
    if @problem.save
      flash[:notice] = 'Problem was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def quick_create
    @problem = Problem.new(params[:problem])
    @problem.full_name = @problem.name if @problem.full_name == ''
    @problem.full_score = 100
    @problem.available = false
    @problem.test_allowed = true
    @problem.output_only = false
    @problem.date_added = Time.new
    if @problem.save
      flash[:notice] = 'Problem was successfully created.'
      redirect_to :action => 'list'
    else
      flash[:notice] = 'Error saving problem'
      redirect_to :action => 'list'
    end
  end

  def edit
    @problem = Problem.find(params[:id])
    @description = @problem.description
  end

  def update
    @problem = Problem.find(params[:id])
    @description = @problem.description
    if @description == nil and params[:description][:body]!=''
      @description = Description.new(params[:description])
      if !@description.save
        flash[:notice] = 'Error saving description'
        render :action => 'edit' and return
      end
      @problem.description = @description
    elsif @description!=nil
      if !@description.update_attributes(params[:description])
        flash[:notice] = 'Error saving description'
        render :action => 'edit' and return
      end
    end
    if params[:file] and params[:file].content_type != 'application/pdf'
        flash[:notice] = 'Error: Uploaded file is not PDF'
        render :action => 'edit' and return
    end
    if @problem.update_attributes(params[:problem])
      flash[:notice] = 'Problem was successfully updated.'
      unless params[:file] == nil or params[:file] == ''
        flash[:notice] = 'Problem was successfully updated and a new PDF file is uploaded.'
        out_dirname = "#{Problem.download_file_basedir}/#{@problem.id}"
        if not FileTest.exists? out_dirname
          Dir.mkdir out_dirname
        end

        out_filename = "#{out_dirname}/#{@problem.name}.pdf"
        if FileTest.exists? out_filename
          File.delete out_filename
        end

        File.open(out_filename,"wb") do |file|
          file.write(params[:file].read)
        end
        @problem.description_filename = "#{@problem.name}.pdf"
        @problem.save
      end
      redirect_to :action => 'show', :id => @problem
    else
      render :action => 'edit'
    end
  end

  def destroy
    Problem.find(params[:id]).destroy
    redirect_to :action => 'list'
  end

  def toggle
    @problem = Problem.find(params[:id])
    @problem.available = !(@problem.available)
    @problem.save
  end

  def turn_all_off
    Problem.find(:all,
                 :conditions => "available = 1").each do |problem|
      problem.available = false
      problem.save
    end
    redirect_to :action => 'list'
  end

  def turn_all_on
    Problem.find(:all,
                 :conditions => "available = 0").each do |problem|
      problem.available = true
      problem.save
    end
    redirect_to :action => 'list'
  end

  def stat
    @problem = Problem.find(params[:id])
    unless @problem.available or session[:admin]
      redirect_to :controller => 'main', :action => 'list'
      return
    end
    @submissions = Submission.includes(:user).where(problem_id: params[:id]).order(:user_id,:id)

    #stat summary
    range =65
    @histogram = { data: Array.new(range,0), summary: {} }
    user = Hash.new(0)
    @submissions.find_each do |sub|
      d = (DateTime.now.in_time_zone - sub.submitted_at) / 24 / 60 / 60
      @histogram[:data][d.to_i] += 1 if d < range
      user[sub.user_id] = [user[sub.user_id], ( sub.try(:points) >= @problem.full_score) ? 1 : 0].max
    end
    @histogram[:summary][:max] = [@histogram[:data].max,1].max

    @summary = { attempt: user.count, solve: 0 }
    user.each_value { |v| @summary[:solve] += 1 if v == 1 }
  end

  def manage
    @problems = Problem.find(:all, :order => 'date_added DESC')
  end

  def do_manage
    if params.has_key? 'change_date_added'
      change_date_added
    elsif params.has_key? 'add_to_contest'
      add_to_contest
    elsif params.has_key? 'enable_problem'
      set_available(true)
    elsif params.has_key? 'disable_problem'
      set_available(false)
    end
    redirect_to :action => 'manage'
  end

  def import
    @allow_test_pair_import = allow_test_pair_import?
  end

  def do_import
    old_problem = Problem.find_by_name(params[:name])
    if !allow_test_pair_import? and params.has_key? :import_to_db
      params.delete :import_to_db
    end
    @problem, import_log = Problem.create_from_import_form_params(params,
                                                                  old_problem)

    if !@problem.errors.empty?
      render :action => 'import' and return
    end

    if old_problem!=nil
      flash[:notice] = "The test data has been replaced for problem #{@problem.name}"
    end
    @log = import_log
  end

  def remove_contest
    problem = Problem.find(params[:id])
    contest = Contest.find(params[:contest_id])
    if problem!=nil and contest!=nil
      problem.contests.delete(contest)
    end
    redirect_to :action => 'manage'
  end

  ##################################
  protected

  def allow_test_pair_import?
    if defined? ALLOW_TEST_PAIR_IMPORT
      return ALLOW_TEST_PAIR_IMPORT
    else
      return false
    end
  end

  def change_date_added
    problems = get_problems_from_params
    year = params[:date_added][:year].to_i
    month = params[:date_added][:month].to_i
    day = params[:date_added][:day].to_i
    date = Date.new(year,month,day)
    problems.each do |p|
      p.date_added = date
      p.save
    end
  end

  def add_to_contest
    problems = get_problems_from_params
    contest = Contest.find(params[:contest][:id])
    if contest!=nil and contest.enabled
      problems.each do |p|
        p.contests << contest
      end
    end
  end

  def set_available(avail)
    problems = get_problems_from_params
    problems.each do |p|
      p.available = avail
      p.save
    end
  end

  def get_problems_from_params
    problems = []
    params.keys.each do |k|
      if k.index('prob-')==0
        name, id, order = k.split('-')
        problems << Problem.find(id)
      end
    end
    problems
  end

  def get_problems_stat
  end

end
