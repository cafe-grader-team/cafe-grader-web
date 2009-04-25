class TasksController < ApplicationController

  before_filter :authenticate, :check_viewability

  def index
    redirect_to :action => 'list'
  end

  def list
    @problems = Problem.find_available_problems
    @user = User.find(session[:user_id])
  end

  def view
    base_filename = File.basename("#{params[:file]}.#{params[:ext]}")
    filename = "#{RAILS_ROOT}/data/tasks/#{base_filename}"
    #filename = "/home/ioi/web_grader/data/tasks/#{base_filename}"
    #filename = "/home/ioi/web_grader/public/images/rails.png"
    if !FileTest.exists?(filename)
      redirect_to :action => 'index' and return
    end

    if defined?(USE_APACHE_XSENDFILE) and USE_APACHE_XSENDFILE
      response.headers['Content-Type'] = "application/force-download" 
      response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(filename)}\"" 
      response.headers["X-Sendfile"] = filename
      response.headers['Content-length'] = File.size(filename)
      render :nothing => true
    else
      send_file filename, :stream => false, :filename => base_filename
    end
  end

  protected

  def check_viewability
    user = User.find(session[:user_id])
    if user==nil or !Configuration.show_tasks_to?(user)
      redirect_to :controller => 'main', :action => 'list'
      return false
    end
  end

end
