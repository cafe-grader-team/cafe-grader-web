class MainController < ApplicationController
  before_action :check_valid_login, except: [:login]

  before_action :default_stimulus_controller

  # reset login, clear session
  # front page
  def login
    @remote_ip = request.remote_ip

    @announcements = Announcement.frontpage.consider_contest.default_order
    render action: 'login', locals: {skip_header: true}
  end

  def logout
    reset_session
    redirect_to root_path
  end

  # this is the main page for users
  def list
    prepare_list_information

    @announcements = Announcement.mainpage.consider_contest.viewable_by_user(@current_user).default_order

    if GraderConfiguration.contest_mode?
      @contests = @current_user.contests.enabled
    else
      @contests = nil
    end


    @groups = [['All', -1]] + @current_user.groups.pluck(:name, :id)
    @primary_tags = Tag.where(kind: 'topic')
  end

  def prob_group
  end

  def help
    @user = User.find(session[:user_id])
  end

  # handle post of new submission either by
  #   1. submit via a form in the main file
  #   2. submit via "new" button
  #   4. submit vis "edit" button
  def submit
    # parameter validation
    problem = Problem.where(id: params[:submission][:problem_id]).first
    unless problem
      redirect_to list_main_path, alert: 'You must specify a problem' and return
    end

    # check if the problem is submittable
    # the problems_for_action already include the logic for admin privilege
    unless @current_user.problems_for_action(:submit).where(id: problem).any? || @current_user.problems_for_action(:edit).where(id: problem).any?
      redirect_to list_main_path, alert: "Problem #{problem.name} is currently not available for you" and return
    end

    # set language
    if params['file'] && params['file']!=''
      language = Language.find_by_extension params['file'].original_filename.ext
    end
    language = Language.find(params[:language_id]) rescue nil
    permitted_ids = problem.get_permitted_lang_as_ids
    # The language dropdown only offers permitted languages; reject a crafted or
    # stale POST whose language_id is outside the problem's permitted set.
    # (Skipped when exactly one language is permitted — it is force-set below.)
    if params[:language_id].present? && permitted_ids.count != 1 && !permitted_ids.include?(language&.id)
      redirect_to list_main_path, alert: 'The selected language is not permitted for this problem.' and return
    end
    language = Language.find(permitted_ids[0]) if permitted_ids.count == 1   # if permitted only 1 language, we will use it
    language = Language.where(name: 'cpp').first if language.nil?

    @submission = Submission.new(user: @current_user,
                                 language: language,
                                 problem: problem,
                                 submitted_at: Time.zone.now,
                                 cookie: cookies.encrypted[:uuid],
                                 ip_address: request.remote_ip)
    # if a file is submitted, without editor_text
    if params['file'] && params['file']!='' && params[:editor_text].blank?
      if language.binary?
        @submission.binary = params['file'].read
        @submission.content_type = params['file'].content_type
        @submission.source_filename = params['file'].original_filename
      else
        @submission.source = File.open(params['file'].path, 'r:UTF-8', &:read)
        @submission.source.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '')
        @submission.source_filename = params['file'].original_filename
      end
    end

    # this will overwrite @sub.source by th editor_text (if exsists)
    # we prioritize editor_text if it exists
    # because a user might choose a file and it is loaded to the editor_text and then
    # the user might edit the editor text later
    if params[:editor_text] && !language.binary?
      @submission.language = language
      @submission.source = params[:editor_text]
      @submission.source_filename = "live_edit.#{language.ext}"
    end

    if @submission.source.blank? && @submission.binary.blank?
      redirect_to list_main_path, alert: 'You must add a source code' and return
    end


    if @submission.valid? && @submission.save
      @submission.add_judge_job
      redirect_to edit_submission_path(@submission)
    else
      redirect_to list_main_path, alert: "Error saving your submission: #{@submission.errors.full_messages.join(', ')}" and return
    end
  end

  def source
    submission = Submission.find(params[:id])
    if (submission.user_id == session[:user_id]) and
        (submission.problem != nil) and
        (submission.problem.available)
      send_data(submission.source,
                {filename: submission.download_filename,
                  type: 'text/plain'})
    else
      flash[:notice] = 'Error viewing source'
      redirect_to action: 'list'
    end
  end

  def load_output
    if !GraderConfiguration.show_grading_result or params[:num]==nil
      redirect_to action: 'list' and return
    end
    @user = User.find(session[:user_id])
    @submission = Submission.find(params[:id])
    if @submission.user!=@user
      flash[:notice] = 'You are not allowed to view result of other users.'
      redirect_to action: 'list' and return
    end
    case_num = params[:num].to_i
    out_filename = output_filename(@user.login,
                                   @submission.problem.name,
                                   @submission.id,
                                   case_num)
    if !FileTest.exists?(out_filename)
      flash[:notice] = 'Output not found.'
      redirect_to action: 'list' and return
    end

    if defined?(USE_APACHE_XSENDFILE) and USE_APACHE_XSENDFILE
      response.headers['Content-Type'] = "application/force-download"
      response.headers['Content-Disposition'] = "attachment; filename=\"output-#{case_num}.txt\""
      response.headers["X-Sendfile"] = out_filename
      response.headers['Content-length'] = File.size(out_filename)
      render nothing: true
    else
      send_file out_filename, stream: false, filename: "output-#{case_num}.txt", type: "text/plain"
    end
  end

  def error
    @user = User.find(session[:user_id])
  end

  def confirm_contest_start
    user = User.find(session[:user_id])
    if request.method == 'POST'
      user.update_start_time
      redirect_to action: 'list'
    else
      @contests = user.contests
      @user = user
    end
  end

  protected

  def prepare_list_information
    # list of problems for this user, considering the current mode
    @problems = @current_user.problems_for_action(:submit, respect_admin: false).with_attached_statement.with_attached_attachment.includes(:public_tags).default_order

    # calculate range of time (in contest mode)
    submissions = Submission.where(user: @current_user, problem: @problems)
    submissions = submissions.where(submitted_at: @current_user.active_contests_range) if GraderConfiguration.contest_mode?

    # calculate latest submission & submission count
    # Filter on viva_archived_at IS NULL: a viva that an admin set aside
    # shouldn't gate the "Start Viva" button for the same user-problem.
    # Non-viva submissions always have viva_archived_at = nil, so this is
    # a no-op for them.
    @prob_submissions = Hash.new { |h, k| h[k] = {count: 0, submission: nil} }
    last_sub_ids = submissions.where(viva_archived_at: nil).group(:problem_id).pluck('max(id)')
    Submission.where(id: last_sub_ids).each do |sub|
      @prob_submissions[sub.problem_id] = { count: sub.number, submission: sub }
    end

    # calculate max score
    submissions
      .group(:problem_id)
      .pluck('problem_id', 'max(points)').each { |data| @prob_submissions[data[0]][:max_score] = data[1] }

    # calculate ai assist used for the problems
    submissions.with_llm_stat_by_problem.each do |row|
        @prob_submissions[row.problem_id][:ai_assist_count] = row.count
        @prob_submissions[row.problem_id][:ai_assist_cost] = row.cost
      end

    # calculate hint acquired
    Problem.joins(comments: :comment_reveals)
      .where(id: @problems.ids, comment_reveals: {user: @current_user})
      .group(:id)
      .select('problems.id', 'count(comments.id) as count', 'sum(comments.cost) as cost')
      .each do |row|
        @prob_submissions[row.id][:hint_count] = row.count
        @prob_submissions[row.id][:hint_cost] = row.cost
      end
  end

  def prepare_grading_result(submission)
    if GraderConfiguration.task_grading_info.has_key? submission.problem.name
      grading_info = GraderConfiguration.task_grading_info[submission.problem.name]
    else
      # guess task info from problem.full_score
      cases = submission.problem.live_dataset.testcases.count
      grading_info = {
        'testruns' => cases,
        'testcases' => cases
      }
    end
    @test_runs = []
    if grading_info['testruns'].is_a? Integer
      trun_count = grading_info['testruns']
      trun_count.times do |i|
        @test_runs << [ read_grading_result(@user.login,
                                            submission.problem.name,
                                            submission.id,
                                            i+1) ]
      end
    else
      grading_info['testruns'].keys.sort.each do |num|
        run = []
        testrun = grading_info['testruns'][num]
        testrun.each do |c|
          run << read_grading_result(@user.login,
                                     submission.problem.name,
                                     submission.id,
                                     c)
        end
        @test_runs << run
      end
    end
  end

  def grading_result_dir(user_name, problem_name, submission_id, case_num)
    return "#{GRADING_RESULT_DIR}/#{user_name}/#{problem_name}/#{submission_id}/test-result/#{case_num}"
  end

  def output_filename(user_name, problem_name, submission_id, case_num)
    dir = grading_result_dir(user_name, problem_name, submission_id, case_num)
    return "#{dir}/output.txt"
  end

  def read_grading_result(user_name, problem_name, submission_id, case_num)
    dir = grading_result_dir(user_name, problem_name, submission_id, case_num)
    result_file_name = "#{dir}/result"
    if !FileTest.exists?(result_file_name)
      return {num: case_num, msg: 'program did not run'}
    else
      results = File.open(result_file_name).readlines
      run_stat = extract_running_stat(results)
      output_filename = "#{dir}/output.txt"
      if FileTest.exists?(output_filename)
        output_file = true
        output_size = File.size(output_filename)
      else
        output_file = false
        output_size = 0
      end

      return {
        num: case_num,
        msg: results[0],
        run_stat: run_stat,
        output: output_file,
        output_size: output_size
      }
    end
  end

  # copied from grader/script/lib/test_request_helper.rb
  def extract_running_stat(results)
    running_stat_line = results[-1]

    # extract exit status line
    run_stat = ""
    if !(/[Cc]orrect/.match(results[0]))
      run_stat = results[0].chomp
    else
      run_stat = 'Program exited normally'
    end

    logger.info "Stat line: #{running_stat_line}"

    # extract running time
    if res = /r(.*)u(.*)s/.match(running_stat_line)
      seconds = (res[1].to_f + res[2].to_f)
      time_stat = "Time used: #{seconds} sec."
    else
      seconds = nil
      time_stat = "Time used: n/a sec."
    end

    # extract memory usage
    if res = /s(.*)m/.match(running_stat_line)
      memory_used = res[1].to_i
    else
      memory_used = -1
    end

    return {
      msg: "#{run_stat}\n#{time_stat}",
      running_time: seconds,
      exit_status: run_stat,
      memory_usage: memory_used
    }
  end
end
