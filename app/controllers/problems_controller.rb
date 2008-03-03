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
  end

  def create
    @problem = Problem.new(params[:problem])
    if @problem.save
      flash[:notice] = 'Problem was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def edit
    @problem = Problem.find(params[:id])
  end

  def update
    @problem = Problem.find(params[:id])
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

  def toggle_avail
    problem = Problem.find(params[:id])
    problem.available = !(problem.available)
    problem.save
    redirect_to :action => 'list'
  end

  def stat
    @problem = Problem.find(params[:id])
    @submissions = Submission.find_all_last_by_problem(params[:id])
  end
end
