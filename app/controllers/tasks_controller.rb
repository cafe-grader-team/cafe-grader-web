class TasksController < ApplicationController

  before_filter :authenticate, :check_viewability

  def index
    redirect_to :action => 'list'
  end

  def list
    @problems = Problem.find_available_problems
  end

  # this has contest-wide access control
  def view
    base_name = params[:file]
    base_filename = File.basename("#{base_name}.#{params[:ext]}")
    filename = "#{Problem.download_file_basedir}/#{base_filename}"

    if !FileTest.exists?(filename)
      redirect_to :action => 'index' and return
    end

    send_file_to_user(filename, base_filename)
  end

  # this has problem-level access control
  def download
    problem = Problem.find(params[:id])
    if !problem or !problem.available or !@user.can_view_problem? problem
      redirect_to :action => 'index' and return
    end

    base_name = params[:file]
    base_filename = File.basename("#{base_name}.#{params[:ext]}")
    filename = "#{Problem.download_file_basedir}/#{params[:id]}/#{base_filename}"
    puts "SENDING: #{filename}"

    if !FileTest.exists?(filename)
      redirect_to :action => 'index' and return
    end

    puts "SENDING: #{filename}"

    send_file_to_user(filename, base_filename)
  end

  protected

  def send_file_to_user(filename, base_filename)
    if defined?(USE_APACHE_XSENDFILE) and USE_APACHE_XSENDFILE
      response.headers['Content-Type'] = "application/force-download" 
      response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(filename)}\"" 
      response.headers["X-Sendfile"] = filename
      response.headers['Content-length'] = File.size(filename)
      render :nothing => true
    else
      if params[:ext]=='pdf'
        content_type = 'application/pdf'
      else
        content_type = 'application/octet-stream'
      end

      send_file filename, :stream => false, :filename => base_filename, :type => content_type
    end
  end

  def check_viewability
    @user = User.find(session[:user_id])
    if @user==nil or !Configuration.show_tasks_to?(@user)
      redirect_to :controller => 'main', :action => 'list'
      return false
    end
  end

end
