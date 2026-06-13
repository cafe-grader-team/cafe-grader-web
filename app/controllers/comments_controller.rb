class CommentsController < ApplicationController
  include ProblemAuthorization
  include SubmissionAuthorization

  HINT_VIEW_METHOD = %i[ show_hint acquire ]
  HINT_EDIT_METHOD = %i[ edit update ]
  PROBLEM_METHOD = HINT_VIEW_METHOD + HINT_EDIT_METHOD + %i[ manage_problem ]


  SUB_COMMENT_VIEW_METHOD = %i[ show_for_submission index_partial ]
  SUB_COMMENT_EDIT_METHOD = %i[ update_for_submission destroy_for_submission ]
  SUB_COMMENT_METHOD = SUB_COMMENT_VIEW_METHOD + SUB_COMMENT_EDIT_METHOD + %i[ create_for_submission llm_assist ]

  before_action :check_valid_login

  # for problem hint
  before_action :set_problem, only: PROBLEM_METHOD
  before_action :set_hint, only: HINT_EDIT_METHOD + HINT_VIEW_METHOD

  # for submission comment
  before_action :set_submission, only: SUB_COMMENT_METHOD
  before_action :set_sub_comment, only: SUB_COMMENT_VIEW_METHOD + SUB_COMMENT_EDIT_METHOD

  # authorization
  # only editor is allowed to create a comment, but a user can create llm_assist
  before_action :can_edit_problem, only: HINT_EDIT_METHOD + SUB_COMMENT_EDIT_METHOD + %i[ create_for_submission ]
  before_action :can_view_problem, only: HINT_VIEW_METHOD + SUB_COMMENT_VIEW_METHOD
  before_action :can_view_submission, only: SUB_COMMENT_VIEW_METHOD
  before_action :can_request_llm, only: %i[ llm_assist ]

  # render comments partial
  def index_partial
    if params[:for] == 'edit'
      # this one renders for the submission edit page
      render turbo_stream: [
        turbo_stream.update(:problem_hints, partial: 'problems/hints', locals: {problem: @submission.problem}),
        turbo_stream.update(:submission_comments, partial: 'submissions/comments', locals: {submission: @submission, show_edit: false, has_processing: @submission.has_processing_comments?})
      ]
    else
      # this one renders for the submission view pages
      render turbo_stream: turbo_stream.update(:submission_comments, partial: 'submissions/comments', locals: {submission: @submission, show_edit: true, has_processing: @submission.has_processing_comments?})
    end
  end

  # -- problem comment section --
  # -- (this is mainly about hints) --
  def manage_problem
    @hint = Comment.find(params[:null][:hint_id]) rescue nil
    @hint = @problem.hints.first unless @hint
    if params[:button] == 'add'
      # create without title (this will fail to be saved unless we set a title)
      @hint = @problem.hints.new(user: @current_user, kind: 'hint')

      @hint.set_default_hint_title
      @hint.save
    elsif params[:button] == 'delete'
      @hint.destroy if @hint
      @hint = @problem.hints.first
    end
  end

  def edit
    render turbo_stream: [
      turbo_stream.update("hint_detail", partial: 'hint_edit', locals: {hint: @hint})
    ]
  end

  def update
    hint_params = params.require(:comment).permit(:body, :title, :cost, :kind)
    if @hint.update(hint_params)
      @toast = {title: "Problem #{@problem.name}'s hint", body: "Hint #{@hint.title} updated"}
    else
      error_html = "<ul>#{@hint.errors.full_messages.map { |m| "<li>#{m}</li>" }.join}</ul>"
      render partial: 'msg_modal_show', locals: {do_popup: true,
                                                 header_msg: 'Hint update error',
                                                 header_class: 'bg-danger-subtle',
                                                 body_msg: error_html.html_safe}
      return
    end
    render :manage_problem
  end

  def acquire
    if @hint.acquirable_by?(@current_user)
      @hint.comment_reveals.create(user: @current_user)
      @toast = {title: "Hint acquired", body: "You received the hint. It can now be viewed at any time."}
      render turbo_stream: [
        turbo_stream.update('problem_hints', partial: 'problems/hints', locals: {problem: @problem}),
        turbo_stream.append('toast-area', partial: 'toast', locals: {toast: @toast})
      ]
    else
      render partial: 'msg_modal_show', locals: {do_popup: true,
                                                 header_msg: 'Hint acquisition failed',
                                                 header_class: 'bg-danger-subtle',
                                                 body_msg: "You don't have permission to acquire this hint"}
    end
  end

  # show hint as a modal
  def show_hint
    # TODO: need to check whether the user can view this hint
    @header_msg = "Hint: #{@hint.title}"
    @body_msg = (@hint.body || '-- blank --').html_safe
    render :show
  end

  # unified show for submissions comment as a modal
  def show_for_submission
    @header_msg = "Comment: #{@comment.title}".html_safe
    if @comment.kind == 'llm_assist'
      @body_msg = render_to_string(partial: 'llm_assist_header') + "\n" +
                  (@comment.body.html_safe || '-- blank --')
    else
      @body_msg = (@comment.body.html_safe || '-- blank --')
    end
    render :show
  end

  def create_for_submission
    title = params[:comment_title]
    @comment = @submission.comments.new({
      kind: 'comment',
      user: @current_user,
      title: title,
      body: params[:comment_body]
    })
    @show_edit = true

    if @comment.save
      @toast = {title: 'Submission Comment', body: "A comment titled: #{title} was successfully created for submission ##{@submission.id}" }
      render 'submission_and_toast', status: :created
    else
      @toast = {title: 'Submission Comment', body: "Could not create a comment.", errors: @comment.errors.full_messages, type: 'alert' }
      render 'submission_and_toast', status: :unprocessable_entity
    end
  end

  def destroy_for_submission
    @toast = {title: 'Submission Comment', body: "Comment \"#{@comment.title}\" was deleted successfully"}
    @comment.destroy
    @show_edit = true
    render 'submission_and_toast'
  end

  def update_for_submission
    @comment.title = params[:comment_title]
    @comment.body = params[:comment_body]
    @show_edit = true
    if @comment.save
      @toast = {title: 'Submission Comment', body: "The comment '#{@comment.title}' was successfully updated for submission ##{@submission.id}" }
      render 'submission_and_toast'
    else
      @toast = {title: 'Submission Comment', body: "Could not update the comment.", errors: @comment.errors.full_messages, type: 'alert' }
      render 'submission_and_toast', status: :unprocessable_entity
    end
  end

  # request the llm assist via job
  def llm_assist
    # get the service class that responsible for the model
    model_id = params[:model].to_i
    model_name = Rails.configuration.llm[:provider].keys[model_id]
    llm_assist_job_class = (Rails.configuration.llm[:provider][model_name] + 'Job').constantize


    @record = @submission.comments.create!({
      user: @current_user,
      kind: 'llm_assist',
      llm_model: model_name,
      title: "AI #{model_name} is thinking <span class='spinner-border spinner-border-sm'></span>",
      body: <<~TEXT,
        ## AI is thinking, please wait
        * Request started at `#{Time.zone.now}`, using the model `#{model_name}`
        * Request initiated by `#{@current_user.full_name}`
      TEXT
      cost: 0,    # default to 0 but should be adjusted when the request finished
      status: 'processing'
    })

    # model_name is also validated by the actual service class
    llm_assist_job_class.perform_later(@submission, model: model_name, comment: @record)
    render 'submission_and_toast'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_problem
      @problem = Problem.find(params[:problem_id])
    end

    def set_submission
      @submission = Submission.find(params[:submission_id])
      @problem = @submission.problem
    end

    def set_hint
      @hint = @problem.hints.where(id: params[:id]).take
    end

    def set_sub_comment
      @comment = @submission.comments.where(id: params[:id]).take
    end

    def can_request_llm
      # check global allow llm
      unless GraderConfiguration['system.llm_assist']
        @toast = {title: 'LLM Assist Error', body: "The system does not allow LLM Assist at the moment", type: 'alert' }
        render 'submission_and_toast' and return
      end

      # in contest mode, we also check if allow_llm is true
      if GraderConfiguration.contest_mode? && ContestProblem.from_available_contests_problems_for_user(@current_user.id).where(problem: @submission.problem).pluck(:allow_llm).select { |x| x == true }.blank?
        @toast = {title: 'LLM Assist Error', body: "LLM Assist are not allow for this problem", type: 'alert' }
        render 'submission_and_toast' and return
      end

      # check whether the problem has attached llm_prompt
      unless @submission.problem.tags.where(kind: 'llm_prompt').any?
        @toast = {title: 'LLM Assist Error', body: "There is no <code>llm_prompt</code> tag associated with this problem.".html_safe, errors: ['Please notify the staff'], type: 'alert' }
        render 'submission_and_toast' and return
      end
    end
end
