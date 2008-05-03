class GradersController < ApplicationController

  before_filter :admin_authorization

  verify :method => :post, :only => ['clear_all'], 
         :redirect_to => {:action => 'index'}

  def index
    redirect_to :action => 'list'
  end

  def list
    @grader_processes = GraderProcess.find(:all, 
                                           :order => 'updated_at desc')
    @stalled_processes = GraderProcess.find_stalled_process
  end

  def clear
    grader_proc = GraderProcess.find(params[:id])
    grader_proc.destroy if grader_proc!=nil
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
