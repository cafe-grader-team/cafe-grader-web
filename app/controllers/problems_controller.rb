class ProblemsController < ApplicationController
  # concern for problem authorization
  include ProblemAuthorization

  MEMBER_METHOD = [:edit, :update, :destroy,
                   :toggle_available, :toggle_view_testcase, :stat,
                   :add_dataset, :import_testcases,
                   :download_archive, :download_by_type, :delete_by_type,
                  ]

  before_action :set_problem, only: MEMBER_METHOD
  before_action :check_valid_login

  # permission
  before_action :group_editor_authorization, except: [:download_by_type]
  before_action :can_view_problem, only: [:download_by_type]

  before_action :admin_authorization, only: [:toggle_available, :turn_all_on, :turn_all_off, :download_archive]
  before_action :can_edit_problem, only: [:edit, :update, :destroy,
                                          :toggle_view_testcase, :stat,
                                          :add_dataset, :import_testcases,
                                          :delete_by_type,
                                         ]
  before_action :can_report_problem, only: [:stat]
  before_action :set_active_tab, only: %i[update]
  before_action :stimulus_controller


  def index
    @problem = problem_for_manage(@current_user)
  end

  def manage_query
    @problem = problem_for_manage(@current_user)
    render 'manage_problem'
  end

  # as turbo
  def add_dataset
    @dataset = @problem.datasets.create(name: @problem.get_next_dataset_name)
    render 'datasets/update'
  end

  def download_by_type
    # Find the attachment on the model
    attachment_type = params[:attachment_type]
    unless %w[statement generated_statement attachment].include? attachment_type
      @error_message = "File is not available in the server."
      render 'error' and return
    end

    # PDF statement is hidden from students for problem modes where the
    # PDF is staff-only (viva). The base can_view_problem before_action
    # has already passed; here we narrow to PDF-specific visibility.
    # Note: 'attachment' is intentionally NOT gated — generic file
    # downloads remain available to anyone who can see the problem.
    if %w[statement generated_statement].include?(attachment_type) &&
       !@current_user.can_view_problem_pdf?(@problem)
      @error_message = "This problem's statement isn't available."
      render 'error' and return
    end

    attachment = @problem.send(attachment_type)

    # build the filename or render error when the type is invalid
    filename =
      case attachment_type
      when 'statement', 'generated_statement' then @problem.name + '.pdf'
      when 'attachment' then attachment.filename.to_s
      end

    begin
      send_data attachment.download,
                filename: filename,
                type: attachment.content_type || 'application/octet-stream',
                disposition: 'inline'
    rescue  ActiveStorage::FileNotFoundError
      @error_message = "File is not found in the server."
      render 'error'
    end
  end

  def delete_by_type
    attachment_to_purge = @problem.send(params[:attachment_type])

    if attachment_to_purge.attached?
      attachment_to_purge.purge
      @toast = {title: "Problem #{@problem.name}", body: "The #{params[:attachment_type].humanize} has been deleted."}
    else
      @toast = {title: "Problem #{@problem.name}", body: "The specified attachment was not found."}
    end
    render :update
  end

  # -- hint and helpers --
  # as turbo
  # render a card displaying all problem helpers (hint, solution, LLM, etc)
  def helpers
    # submission may be null
    @submission = Submission.where(id: params[:submission_id]).take
    @assists = @submission&.comments&.where(kind: 'llm_assist', enabled: true)
    respond_to do |format|
      format.html { render partial: 'helpers' }
      format.turbo_stream { render 'helpers' }
    end
  end
  # -- END hint and helpers --


  def create
    @problem = Problem.new(problem_params)
    if @problem.save
      redirect_to action: :index, notice: 'Problem was successfully created.'
    else
      render action: 'new'
    end
  end

  def quick_create
    @problem = Problem.new(problem_params)
    @problem.full_name = @problem.name if @problem.full_name.blank?
    @problem.available = false
    @problem.test_allowed = true
    @problem.output_only = false
    @problem.date_added = Time.zone.now

    # Wrap problem creation + default dataset + live_dataset assignment in a
    # transaction so a partial half-create can't happen. The default dataset
    # is required because problem_for_manage (used by index/manage) joins on
    # :datasets — a dataset-less problem is invisible to those views.
    success = Problem.transaction do
      next false unless @problem.save
      ds = @problem.datasets.create!(name: @problem.get_next_dataset_name)
      @problem.update!(live_dataset: ds)
      true
    end

    if success
      # /problems/index is server-rendered with non-AJAX DataTables, so a
      # turbo_stream toast can't refresh the row list. Mirror the regular
      # `create` action and let Turbo follow a See Other to re-render the page.
      redirect_to problems_path,
                  notice: "Problem '#{@problem.name}' was successfully created.",
                  status: :see_other
    else
      @toast = {title: 'Quick create failed',
                body:  "Could not create problem.",
                errors: @problem.errors.full_messages,
                type:  :alert}
      render 'turbo_toast', status: :unprocessable_entity
    end
  end

  def edit
    @description = @problem.description

    # if permitted_lang not blank, it means the user has some intent to limit
    # submittible language
    @permitted_lang_ids = @problem.get_permitted_lang_as_ids unless @problem.permitted_lang.blank?
  end

  def update
    if @problem.update(problem_params)
      msg = 'Problem was successfully updated. '
      msg += 'A new statement PDF is uploaded' if problem_params[:statement]

      # permitted lang is updated separately
      permitted_lang_as_string = params[:problem][:permitted_lang].map { |x| Language.find(x.to_i).name unless x.blank? }.join(' ')
      @problem.permitted_lang = permitted_lang_as_string
      @problem.save

      @toast = {title: "Problem #{@problem.name}", body: "Problem settings updated"}
    end
    if problem_params[:statement] && problem_params[:statement].content_type != 'application/pdf'
      @problem.errors.add(:base, ' Uploaded file is not PDF')
    end

    if @problem.errors.any?
      error_html = "<ul>#{@problem.errors.full_messages.map { |m| "<li>#{m}</li>" }.join}</ul>"
      render partial: 'msg_modal_show', locals: {do_popup: true,
                                                 header_msg: 'Problem update error',
                                                 header_class: 'bg-danger-subtle',
                                                 body_msg: error_html.html_safe}
    else
      render :update
    end
  end

  def destroy
    @problem.destroy
    redirect_to action: :index
  end

  def download_archive
    result = @problem.export
    send_file result[:zip], type: 'application/x-zip',  disposition: 'attachment', filename: result[:zip].basename.to_s
  end

  def toggle_available
    @problem.update(available: !@problem.available)
    @toast = {title: "Problem #{@problem.name}", body: "Available updated"}
    render 'toggle'
  end

  def toggle_view_testcase
    @problem.update(view_testcase: !@problem.view_testcase)
    @toast = {title: "Problem #{@problem.name}", body: "View Testcase updated"}
    render 'toggle'
  end

  def turn_all_off
    Problem.where(available: true).update_all(available: false)
    redirect_to action: :index
  end

  def turn_all_on
    Problem.where(available: false).update_all(available: true)
    redirect_to action: :index
  end

  def stat
    unless @problem.available or session[:admin]
      redirect_to controller: 'main', action: 'list'
      return
    end
    @submissions = Submission.includes(:user).includes(:language).where(problem_id: params[:id]).order(:user_id, :id)

    # stat summary
    range =65
    @histogram = { data: Array.new(range, 0), summary: {} }
    user = Hash.new(0)
    @submissions.find_each do |sub|
      d = (DateTime.now.in_time_zone - sub.submitted_at) / 24 / 60 / 60
      @histogram[:data][d.to_i] += 1 if d < range
      user[sub.user_id] = [user[sub.user_id], ((sub.try(:points) || 0) >= 100) ? 1 : 0].max
    end
    @histogram[:summary][:max] = [@histogram[:data].max, 1].max

    @summary = { attempt: user.count, solve: 0 }
    user.each_value { |v| @summary[:solve] += 1 if v == 1 }

    # for new graph
    @chart_dataset = @problem.get_jschart_history.to_json.html_safe
    @can_view_ip =  true
  end

  def manage
    @problems = @current_user.problems_for_action(:edit).order(date_added: :desc).includes(:tags)
  end

  def do_manage
    @result = []
    @error = []
    problems = Problem.where(id: get_problems_from_params.ids).where(id: @current_user.problems_for_action(:edit).ids)

    @toast = {title: "Bulk Manage #{problems.count} #{'problem'.pluralize(problems.count)}"}

    change_date_added(problems) if params[:change_date_added] == '1' && params[:date_added].strip.empty? == false
    add_to_contest(problems) if params.has_key? 'add_to_contest'
    if params[:change_enable] == '1'
      problems.update_all(available: params[:enable] == 'yes')
      @result << "Set \"Available\" to <strong>#{params[:enable]}</strong>"
    end
    if params[:add_tags] == '1'
      problems.each { |p| p.tag_ids += params[:tag_ids] }
      tag_names = Tag.where(id: params[:tag_ids]).pluck(:name).map { |x| "[<strong>#{x}</strong>]" }.join(', ')
      @result << "Add tags #{tag_names}"
    end

    if params[:set_languages] == '1'
      permitted_lang = Language.where(id: params[:lang_ids]).pluck(:name)
      problems.update_all(permitted_lang: permitted_lang.join(' '))
      @result << "Permitted languages are changed to #{permitted_lang.map { |x| "[<strong>#{x}</strong>]" }.join(', ')}"
    end

    # add to groups
    if params[:add_group] == '1'
      Group.where(id: params[:group_id]).each do |group|
        ok = []
        failed = []
        problems.each do |p|
          begin
            group.problems << p
            ok << p.full_name
          rescue
            failed << p.full_name
          end
        end
        @result << "Added to group <strong>#{group.name}</strong>"
        @result << "The following problem are already in the group <strong>#{group.name}</strong>: " + failed.join(', ') if failed.count > 0
      end
      # flash[:success] = "The following problems are added to the group #{group.name}: " + ok.join(', ') if ok.count > 0
      # flash[:alert] = "The following problems are already in the group #{group.name}: " + failed.join(', ') if failed.count > 0
    end

    @toast[:body] = "<ul> #{@result.map { |x| "<li>#{x}</li>" }.join}  </ul>".html_safe
    render 'turbo_toast'


    # redirect_to :action => 'manage'
    # @problems = @current_user.problems_for_action(:edit).order(date_added: :desc).includes(:tags)
    # render :manage
  end

  def import
    @allow_test_pair_import = allow_test_pair_import?
    @allow_blank_group = @current_user.admin?
  end


  # import as a new problem
  def do_import
    # check valid file
    unless params[:problem][:file]
      @errors = ['You must upload a valid ZIP file']
      render :import and return
    end
    name = params[:problem][:name]
    uploaded_file_path = params[:problem][:file].to_path

    # check valid group
    group = Group.find(params[:problem][:groups]) rescue nil
    unless @current_user.admin? || @current_user.groups_for_action(:edit).where(id: group).any?
      @errors = ['You can only upload a problem into a group that you are editor']
      render :import and return
    end

    pi = ProblemImporter.new

    # unzip uploaded file to raw folder
    extracted_path = pi.unzip_to_dir(
      uploaded_file_path,
      name,
      Rails.configuration.worker[:directory][:judge_raw_path]
    )

    if pi.errors.count > 0
      @errors = pi.errors
      render :import and return
    end

    # load data
    memory_limit = params[:problem][:memory_limit]
    memory_limit = 512 if memory_limit.blank?
    time_limit = params[:problem][:time_limit]
    time_limit = 1 if time_limit.blank?

    pi.import_dataset_from_dir(extracted_path, params[:problem][:name],
      full_name: params[:problem][:full_name],
      input_pattern: params[:problem][:input_pattern],
      sol_pattern: params[:problem][:sol_pattern],
      delete_existing: params[:problem][:replace] == '1',
      memory_limit: memory_limit,
      time_limit: time_limit,
    )

    if pi.errors.count > 0
      @errors = pi.errors
      render :import and return
    else
      @log = pi.log
      @problem = pi.problem
      if group && !group.problems.include?(@problem)
        group.problems << @problem
        @log << "The problem was added to the group '#{group.name}'"
      end

      # when non-admin (editor) import a problem, we set available to true
      # (because they cannot set the available) but set the enabled to false
      unless @current_user.admin?
        @problem.update(available: true)
        GroupProblem.where(group: group, problem: @problem).first.update(enabled: false)
      end
    end
  end

  # import into existing problem
  def import_testcases
    unless params[:import][:file]
      @errors = ['There is no uploaded file']
      return
    end

    replacing = params[:import][:target] == 'replace'
    uploaded_file_path = params[:import][:file].to_path

    pi = ProblemImporter.new

    # unzip uploaded file to raw folder
    extracted_path = pi.unzip_to_dir(
      uploaded_file_path,
      @problem.name,
      Rails.configuration.worker[:directory][:judge_raw_path])

    if pi.errors.count > 0
      @errors = pi.errors
      render :import and return
    end

    if replacing
      @dataset = @problem.datasets.where(id: params[:import][:dataset]).first
      WorkerDataset.where(dataset_id: @dataset).delete_all
    end

    # load data
    pi.import_dataset_from_dir(extracted_path, @problem.name,
                                full_name: @problem.full_name,
                                input_pattern: params[:import][:input_pattern],
                                sol_pattern: params[:import][:sol_pattern],
                                dataset: @dataset,
                                do_statement: false,
                                do_checker: false,
                                do_cpp_extras: false,
                                do_solutions: false
                              )
    @updated = 'Testcases has been imported'
    @log = pi.log
    @problem = pi.problem
    @dataset = pi.dataset
    @problem.datasets.reload
  end


  ##################################
  protected
    def stimulus_controller
      @stimulus_controller = 'problem'
    end

    def set_problem
      @problem = Problem.find(params[:id])
    end

    def problem_params
      params.require(:problem).permit(:name, :full_name, :change_date_added, :date_added, :available, :compilation_type,
                                      :submission_filename, :difficulty, :attachment, :statement, :markdown, :view_testcase,
                                      :test_allowed, :output_only, :url, :description, :description, :view_submission, tag_ids: [], group_ids: [])
    end

    def description_params
      params.require(:description).permit(:body, :markdowned)
    end

    def allow_test_pair_import?
      if defined? ALLOW_TEST_PAIR_IMPORT
        return ALLOW_TEST_PAIR_IMPORT
      else
        return false
      end
    end

    # for bulk manage
    def change_date_added(problems)
      date = Date.parse(params[:date_added])
      problems.update_all(date_added: date)
      @result << "Date added changed to <strong>#{date}</strong>"
    end

    def add_to_contest(problems)
      contest = Contest.find(params[:contest][:id])
      if contest!=nil and contest.enabled
        problems.each do |p|
          p.contests << contest
        end
      end
      @result << "Problem added to contest #{contest.title}"
    end


    def get_problems_from_params
      ids = []
      params.keys.each do |k|
        if k.index('prob-')==0
          # name, id, order = k.split('-')
          # problems << Problem.find(id)
          ids << k.split('-')[1]
        end
      end
      return Problem.where(id: ids)
    end

    def problem_for_manage(user)
      tc_count_sql = Testcase.joins(:dataset).group('datasets.problem_id').select('datasets.problem_id,count(testcases.id) as tc_count').to_sql
      ms_count_sql = Submission.where(tag: 'model').group(:problem_id).select('count(*) as ms_count, problem_id').to_sql
      hint_count_sql = Comment.hints.group(:commentable_id).select('commentable_id as problem_id, count(commentable_id) as count').to_sql
      # left_joins (not joins) so that problems without any Dataset still appear
      # in the list with dataset_count = 0, instead of being silently filtered
      # out by an INNER JOIN.
      return @problems = user.problems_for_action(:edit).left_joins(:datasets)
        .joins("LEFT JOIN (#{tc_count_sql}  ) TC ON problems.id = TC.problem_id")
        .joins("LEFT JOIN (#{ms_count_sql}  ) MS ON problems.id = MS.problem_id")
        .joins("LEFT JOIN (#{hint_count_sql}) HC ON problems.id = HC.problem_id")
        .includes(:tags).order(date_added: :desc).group('problems.id')
        .includes(live_dataset: {checker_attachment: :blob})
        .select("problems.*", "count(datasets_problems.id) as dataset_count, MIN(TC.tc_count) as tc_count")
        .select("MIN(MS.ms_count) as ms_count")
        .select("HC.count as hint_count")
        .with_attached_statement
        .with_attached_attachment
    end

    # our 'bs-tab' stimulus controller set the hidden input as the HTML id of the showing tab
    # we set @dataset_active_tab to the id so that we render it, we can activate the correct tab
    def set_active_tab
      @active_problem_tab = params[:active_problem_tab]
    end
end
