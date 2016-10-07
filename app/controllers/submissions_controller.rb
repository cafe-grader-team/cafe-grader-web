class SubmissionsController < ApplicationController
  before_filter :authenticate
  before_filter :submission_authorization, only: [:show, :direct_edit_submission]

  # GET /submissions
  # GET /submissions.json
  # Show problem selection and user's submission of that problem
  def index
    @user = @current_user
    @problems = @user.available_problems

    if params[:problem_id]==nil
      @problem = nil
      @submissions = nil
    else
      @problem = Problem.find_by_id(params[:problem_id])
      if (@problem == nil) or (not @problem.available)
        redirect_to main_list_path
        flash[:notice] = 'Error: submissions for that problem are not viewable.'
        return
      end
      @submissions = Submission.find_all_by_user_problem(@user.id, @problem.id)
    end
  end

  # GET /submissions/1
  # GET /submissions/1.json
  def show
    @submission = Submission.find(params[:id])

    #log the viewing
    user = User.find(session[:user_id])
    SubmissionViewLog.create(user_id: session[:user_id],submission_id: @submission.id) unless user.admin?
  end

  #on-site new submission on specific problem
  def direct_edit_problem
    @problem = Problem.find(params[:problem_id])
    @source = ''
    render 'edit'
  end

  # GET /submissions/1/edit
  def edit
    @submission = Submission.find(params[:id])
    @source = @submission.source.to_s
    @problem = @submission.problem
    @lang_id = @submission.language.id
  end


  def get_latest_submission_status
    @problem = Problem.find(params[:pid])
    @submission = Submission.find_last_by_user_and_problem(params[:uid],params[:pid])
    puts User.find(params[:uid]).login
    puts Problem.find(params[:pid]).name
    puts 'nil' unless @submission
    respond_to do |format|
      format.js
    end
  end

#  # GET /submissions/new
#  # GET /submissions/new.json
#  def new
#    @submission = Submission.new
#
#    respond_to do |format|
#      format.html # new.html.erb
#      format.json { render json: @submission }
#    end
#  end
#
#
#  # POST /submissions
#  # POST /submissions.json
#  def create
#    @submission = Submission.new(params[:submission])
#
#    respond_to do |format|
#      if @submission.save
#        format.html { redirect_to @submission, notice: 'Submission was successfully created.' }
#        format.json { render json: @submission, status: :created, location: @submission }
#      else
#        format.html { render action: "new" }
#        format.json { render json: @submission.errors, status: :unprocessable_entity }
#      end
#    end
#  end
#
#  # PUT /submissions/1
#  # PUT /submissions/1.json
#  def update
#    @submission = Submission.find(params[:id])
#
#    respond_to do |format|
#      if @submission.update_attributes(params[:submission])
#        format.html { redirect_to @submission, notice: 'Submission was successfully updated.' }
#        format.json { head :no_content }
#      else
#        format.html { render action: "edit" }
#        format.json { render json: @submission.errors, status: :unprocessable_entity }
#      end
#    end
#  end
#
#  # DELETE /submissions/1
#  # DELETE /submissions/1.json
#  def destroy
#    @submission = Submission.find(params[:id])
#    @submission.destroy
#
#    respond_to do |format|
#      format.html { redirect_to submissions_url }
#      format.json { head :no_content }
#    end
#  end

protected
  def submission_authorization
    #admin always has privileged
    if @current_user.admin?
      return true
    end

    sub = Submission.find(params[:id])
    if sub.problem.available?
      puts "sub = #{sub.user.id}, current = #{@current_user.id}"
      return true if GraderConfiguration["right.user_view_submission"] or sub.user == @current_user
    end

    #default to NO
    unauthorized_redirect
    return false
  end
    
end
