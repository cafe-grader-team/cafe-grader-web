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
  verify :method => :post, :only => [ :destroy, :create, :update ],
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
    if @problem.update_attributes(params[:problem])
      flash[:notice] = 'Problem was successfully updated.'
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
    respond_to do |wants|
      wants.js {
        @problem = Problem.find(params[:id])
        @problem.available = !(@problem.available)
        @problem.save
      }
    end
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
    if !@problem.available
      redirect_to :controller => 'main', :action => 'list'
    else
      @submissions = Submission.find_all_last_by_problem(params[:id])
    end
  end
end
