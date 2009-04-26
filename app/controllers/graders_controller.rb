class GradersController < ApplicationController

  before_filter :admin_authorization

  verify :method => :post, :only => ['clear_all', 'clear_terminated'], 
         :redirect_to => {:action => 'index'}

  def index
    redirect_to :action => 'list'
  end

  def list
    @grader_processes = GraderProcess.find_running_graders
    @stalled_processes = GraderProcess.find_stalled_process

    @terminated_processes = GraderProcess.find_terminated_graders
    
    @last_task = Task.find(:first,
                           :order => 'created_at DESC')
    @last_test_request = TestRequest.find(:first,
                                          :order => 'created_at DESC')
  end

  def clear
    grader_proc = GraderProcess.find(params[:id])
    grader_proc.destroy if grader_proc!=nil
    redirect_to :action => 'list'
  end

  def clear_terminated
    GraderProcess.find_terminated_graders.each do |p|
      p.destroy
    end
    redirect_to :action => 'list'
  end

  def clear_all
    GraderProcess.find(:all).each do |p|
      p.destroy
    end
    redirect_to :action => 'list'
  end

  def view
    if params[:type]=='Task'
      redirect_to :action => 'task', :id => params[:id]
    else
      redirect_to :action => 'test_request', :id => params[:id]
    end
  end

  def test_request
    @test_request = TestRequest.find(params[:id])
  end

  def task
    @task = Task.find(params[:id])
  end

  def submission
    @submission = Submission.find(params[:id])
  end

end
