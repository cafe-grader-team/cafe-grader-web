class GradersController < ApplicationController

  
  before_filter :authenticate

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

end
