class ReportController < ApplicationController
  include ProblemAuthorization

  before_action :check_valid_login
  before_action :selected_problems, only: [ :show_max_score, :max_score_table, :submission_query, :max_score_query, :ai_query ]
  before_action :selected_users, only: [ :show_max_score, :max_score_table, :submission_query, :max_score_query, :ai_query ]

  # for all action except hall of fame (which is viewable by any user if the feature is enabled)
  before_action(except: [:problem_hof, :problem_hof_view, :problem_hof_query]) {
    group_action_authorization(:report)
  }

  # for hall of fame
  before_action :set_problem, only: [:problem_hof_view]
  before_action :hall_of_fame_authorization, only: [:problem_hof, :problem_hof_query, :problem_hof_view]
  before_action :admin_authorization, only: [:problem_hof_recompute]
  before_action :can_view_problem, only: [:problem_hof_view]

  # render the UI for filtering and the initial blank table
  def max_score
    # this is for rendering the filter selection
    @problems = @current_user.problems_for_action(:report)
    @groups = @current_user.groups_for_action(:report)
  end

  # turbo update the table (also with blank table but with columns)
  def max_score_table
    render turbo_stream: turbo_stream.update(:max_score_result, partial: 'score_table', locals: {problems: @problems, link_for_data: max_score_query_report_path, refresh_submit_form_id: 'max-score-filter-form' })
  end

  def max_score_query
    # when @problems is blank, it is very likely that the user hasn't select anything in the form at all
    # which default to showing all user with no problem selected. We then force the user to be blank as well to speed up

    @users = User.none if @problems.blank?
    submissions = submission_in_range(params[:sub_range]).where(user: @users, problem: @problems)

    # the max score report need range of time to check for hint acquiring,
    # we use the time from the first submission to the last submission of the filtered submission
    start = submissions.minimum(:submitted_at)
    stop = submissions.maximum(:submitted_at)
    records = submissions.max_score_report(@problems, start, stop)

    # calculate the maximum score
    @result = Submission.calculate_max_score(records, @users, @problems)

    render json: {
      # for data, we need some alias as we use the same render for both the report and contest stat,
      # these fields are required in the contest view but not in the report view
      # we also have to alias the user.id to user_id as well
      data: @users.select(:id, :login, :full_name, :remark)
        .select(' NULL as seat').select('NULL as last_heartbeat').select(' id as user_id'),
      result: @result,
      problem: @problems
    }
  end

  # post max_score
  def show_max_score
    # calculate submission with max score
    max_records = submission_in_range(params[:sub_range])
      .where(user_id: @users.ids, problem_id: @problems).group('user_id,problem_id')
      .select('MAX(submissions.points) as max_score, user_id, problem_id')

    records = submission_in_range(params[:sub_range])
      .joins("JOIN (#{max_records.to_sql}) MAX_RECORD ON " +
             'submissions.points = MAX_RECORD.max_score AND ' +
             'submissions.user_id = MAX_RECORD.user_id AND ' +
             'submissions.problem_id = MAX_RECORD.problem_id ')
      .joins(:user).joins(:problem)
      .select('users.id,users.login,users.full_name,users.remark')
      .select('problems.name')
      .select('max_score')
      .select('submissions.submitted_at')
      .select('submissions.problem_id')
      .select('submissions.id as sub_id')

    @show_time = params['show-time'] == 'on'

    # calculate the score
    @result = Submission.calculate_max_score(records, @users, @problems, with_comments: false)

    # this only render as turbo stream
    # see show_max_score.turbo_stream
  end

  def login
  end

  def login_summary_query
    @users = Array.new
    @since_time = Time.zone.parse(params[:since_datetime]) || Time.zone.now rescue Time.zone.now
    @until_time = Time.zone.parse(params[:until_datetime]) || DateTime.new(3000, 1, 1) rescue DateTime.new(3000, 1, 1)
    record = User
      .left_outer_joins(:logins).group('users.id')
      .where("logins.created_at >= ? AND logins.created_at <= ?", @since_time, @until_time)
    case params[:users]
    when 'enabled'
      record = record.where(enabled: true)
    when 'group'
      record = record.joins(:groups).where(groups: {id: params[:groups]}) if params[:groups]
    end

    record = record.pluck("users.id,users.login,users.full_name,count(logins.created_at),min(logins.created_at),max(logins.created_at)")
    record.each do |user|
      query = Login.where("user_id = ? AND created_at >= ? AND created_at <= ?", user[0], @since_time, @until_time)
      ips =  query.pluck(:ip_address).uniq
      cookie = query.pluck(:cookie).uniq

      @users << { id: user[0],
                   login: user[1],
                   full_name: user[2],
                   count: user[3],
                   min: user[4].in_time_zone,
                   max: user[5].in_time_zone,
                   ip: ips,
                   cookie: cookie
                 }
    end
  end

  def login_detail_query
    @logins = Array.new
    @since_time = Time.zone.parse(params[:since_datetime]) || Time.zone.now rescue Time.zone.now
    @until_time = Time.zone.parse(params[:until_datetime]) || DateTime.new(3000, 1, 1) rescue DateTime.new(3000, 1, 1)

    @logins = Login.includes(:user).where("logins.created_at >= ? AND logins.created_at <= ?", @since_time, @until_time)
    case params[:users]
    when 'enabled'
      @logins = @logins.where(users: {enabled: true})
    when 'group'
      @logins = @logins.joins(user: :groups).where(user: {groups: {id: params[:groups]}}) if params[:groups]
    end
  end

  def submission
    @problems = @current_user.problems_for_action(:report)
    @groups = @current_user.groups_for_action(:report)
  end

  def submission_query
    @submissions = submission_in_range(params[:sub_range])
      .joins(:problem).joins(:language).joins(:user)

    # filter users
    unless @users = User.all
      @submissions = @submissions.where(user: @users)
    end

    # filter submissions
    @submissions = @submissions.where(problem: @problems)


    @submissions.limit(100_000)
    @submissions = @submissions.select('submissions.id,points,ip_address,submitted_at,grader_comment')
      .select('users.login, users.full_name as user_full_name, users.id as user_id')
      .select('problems.full_name, problems.name, problems.id as problem_id')
      .select('languages.pretty_name')

    # build day sum

    # render json:  {data: @submissions,sub_count_by_date: {a:1}}
  end

  def ai
    # this is "selectable" problems, groups and for rendering the filter selection
    @problems = @current_user.problems_for_action(:report)
    @groups = @current_user.groups_for_action(:report)
  end

  def ai_query
    submissions = submission_in_range(params[:sub_range]).order(:submitted_at)
    first_sub = submissions.first
    last_sub = submissions.last

    first_submission_datetime = first_sub&.submitted_at
    first_sub_id = first_sub&.id
    last_sub_id = last_sub&.id


    # We can't efficiently filter only for the job inside the selected submissions id range
    # because we then need to unserialize the argument first.
    # Therefore, we just use the first submission date to filter the "start" submission
    # and then use select at the end to actually filtering out the submissions
    jobs_scope = SolidQueue::Job
      .where('created_at > ?', first_submission_datetime)
      .where('class_name LIKE "Llm::%"')
      .order(created_at: :desc)

    # We need to eager load the submission, else this will be N+1 queries
    # First, we need all gid of the submission

    job_submission_map = {} # { job_id => gid_string }
    all_gids = []

    jobs_scope.each do |job|
      arguments = job.arguments['arguments']
      if job.class_name.safe_constantize&.<(Llm::RequestJob) && arguments.present?
        gid_string = arguments.first.values.last
        if gid_string.is_a?(String)
          job_submission_map[job.id] = gid_string
          all_gids << gid_string
        end
      end
    end

    # load these submissions, also eager load the user and problem
    submissions_hash = GlobalID::Locator.locate_many(all_gids, includes: [:user, :problem]).index_by { |submission| submission.to_gid.to_s }


    @jobs = jobs_scope.map do |job|
      gid_string = job_submission_map[job.id]
      # Pass the pre-loaded submission (or nil) to the presenter
      submission = gid_string ? submissions_hash[gid_string] : nil
      Llm::RequestJobPresenter.new(job, submission)
    end

    # @jobs[i] is now a presenter object of the job
    # We will do filtering here
    selected_problem_ids = @problems.ids
    selected_user_ids = @users.ids
    @jobs = @jobs
      .select { |job| selected_problem_ids.include? job.problem_id }
      .select { |job| selected_user_ids.include? job.user_id }
      .select { |job| job.submission_id >= first_sub_id && job.submission_id <= last_sub_id }
  end


  # -- not used --
  # def progress
  # end

  # def progress_query
  # end

  def problem_hof
  end

  def problem_hof_query
    @user = User.find(session[:user_id])
    problem_ids = @user.problems_for_action(:submit).pluck(:id)

    @problems = Problem.where(id: problem_ids)
      .left_joins(:problem_stat)
      .select(
        "problems.id, problems.name, problems.full_name",
        "COALESCE(problem_stats.sub_count, 0) as sub_count",
        "COALESCE(problem_stats.attempted_count, 0) as attempted_count",
        "COALESCE(problem_stats.solved_count, 0) as solved_count"
      )
  end

  def problem_hof_recompute
    ProblemStat.recompute_all
    @toast = { title: "Hall of Fame", body: "Statistics recomputed for #{ProblemStat.count} problems." }
    render "turbo_toast"
  end

  def problem_hof_view
    @user = User.find(session[:user_id])

    # model submission
    @model_subs = Submission.where(problem: @problem, tag: Submission.tags[:model])


    # calculate best submission
    @by_lang = {} # aggregrate by language

    @summary = {count: 0, solve: 0, attempt: 0}
    user = Hash.new(0)
    Submission.where(problem_id: @problem.id).includes(:language).each do |sub|
      # histogram

      next unless sub.points
      @summary[:count] += 1
      user[sub.user_id] = [user[sub.user_id], (sub.points >= 100) ? 1 : 0].max

      # lang = Language.find_by_id(sub.language_id)
      lang = sub.language
      next unless lang
      next unless sub.points >= 100

      # initialize
      unless @by_lang.has_key?(lang.pretty_name)
        @by_lang[lang.pretty_name] = {
          runtime: { avail: false, value: 2**30-1 },
          memory: { avail: false, value: 2**30-1 },
          length: { avail: false, value: 2**30-1 },
          first: { avail: false, value: DateTime.new(3000, 1, 1) }
        }
      end

      if sub.max_runtime and sub.max_runtime < @by_lang[lang.pretty_name][:runtime][:value]
        @by_lang[lang.pretty_name][:runtime] = { avail: true, user_id: sub.user_id, value: sub.max_runtime, sub_id: sub.id }
      end

      if sub.peak_memory and sub.peak_memory < @by_lang[lang.pretty_name][:memory][:value]
        @by_lang[lang.pretty_name][:memory] = { avail: true, user_id: sub.user_id, value: sub.peak_memory, sub_id: sub.id }
      end

      if sub.submitted_at and sub.submitted_at < @by_lang[lang.pretty_name][:first][:value] and sub.user and
          !sub.user.admin?
        @by_lang[lang.pretty_name][:first] = { avail: true, user_id: sub.user_id, value: sub.submitted_at, sub_id: sub.id }
      end

      if @by_lang[lang.pretty_name][:length][:value] > (sub.source.length || 2**30-1)
        @by_lang[lang.pretty_name][:length] = { avail: true, user_id: sub.user_id, value: (sub.source.length || 2**30-1), sub_id: sub.id }
      end
    end

    # process user_id
    @by_lang.each do |lang, prop|
      prop.each do |k, v|
        v[:user] = User.exists?(v[:user_id]) ? User.find(v[:user_id]).full_name : "(NULL)"
      end
    end

    # sum into best
    if @by_lang and @by_lang.first
      @best = @by_lang.first[1].clone
      @by_lang.each do |lang, prop|
        if @best[:runtime][:value] >= prop[:runtime][:value]
          @best[:runtime] = prop[:runtime]
          @best[:runtime][:lang] = lang
        end
        if @best[:memory][:value] >= prop[:memory][:value]
          @best[:memory] = prop[:memory]
          @best[:memory][:lang] = lang
        end
        if @best[:length][:value] >= prop[:length][:value]
          @best[:length] = prop[:length]
          @best[:length][:lang] = lang
        end
        if @best[:first][:value] >= prop[:first][:value]
          @best[:first] = prop[:first]
          @best[:first][:lang] = lang
        end
      end
    end

    @summary[:attempt] = user.count
    user.each_value { |v| @summary[:solve] += 1 if v == 1 }

    # for new graph
    @chart_dataset = @problem.get_jschart_history.to_json.html_safe

  end

  def stuck # report struggling user,problem
    # init
    user, problem = nil
    solve = true
    tries = 0
    @struggle = Array.new
    record = {}
    Submission.includes(:problem, :user).order(:problem_id, :user_id).find_each do |sub|
      next unless sub.problem and sub.user
      if user != sub.user_id or problem != sub.problem_id
        @struggle << { user: record[:user], problem: record[:problem], tries: tries } unless solve
        record = {user: sub.user, problem: sub.problem}
        user, problem = sub.user_id, sub.problem_id
        solve = false
        tries = 0
      end
      if sub.points >= 100
        solve = true
      else
        tries += 1
      end
    end
    @struggle.sort! { |a, b| b[:tries] <=> a[:tries] }
    @struggle = @struggle[0..50]
  end


  def multiple_login
    # user with multiple IP
    raw = Submission.joins(:user).joins(:problem).where("problems.available != 0").group("login,ip_address").order(:login)
    last, count = 0, 0
    first = 0
    @users = []
    raw.each do |r|
      if last != r.user.login
        count = 1
        last = r.user.login
        first = r
      else
        @users << first if count == 1
        @users << r
        count += 1
      end
    end

    # IP with multiple user
    raw = Submission.joins(:user).joins(:problem).where("problems.available != 0").group("login,ip_address").order(:ip_address)
    last, count = 0, 0
    first = 0
    @ip = []
    raw.each do |r|
      if last != r.ip_address
        count = 1
        last = r.ip_address
        first = r
      else
        @ip << first if count == 1
        @ip << r
        count += 1
      end
    end
  end

  def cheat_report
    date_and_time = '%Y-%m-%d %H:%M'
    begin
      md = params[:since_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @since_time = Time.zone.local(md[1].to_i, md[2].to_i, md[3].to_i, md[4].to_i, md[5].to_i)
    rescue
      @since_time = Time.zone.now.ago(90.minutes)
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i, md[2].to_i, md[3].to_i, md[4].to_i, md[5].to_i)
    rescue
      @until_time = Time.zone.now
    end

    # multi login
    @ml = Login.joins(:user).where("logins.created_at >= ? and logins.created_at <= ?", @since_time, @until_time).select('users.login,count(distinct ip_address) as count,users.full_name').group("users.id").having("count > 1")

    st = <<-SQL
  SELECT l2.*
    FROM logins l2 INNER JOIN
    (SELECT u.id,COUNT(DISTINCT ip_address) as count,u.login,u.full_name
      FROM logins l
      INNER JOIN users u ON l.user_id =  u.id
      WHERE l.created_at >= '#{@since_time.in_time_zone("UTC")}' and l.created_at <= '#{@until_time.in_time_zone("UTC")}'
      GROUP BY u.id
      HAVING count > 1
    ) ml ON l2.user_id = ml.id
    WHERE l2.created_at >= '#{@since_time.in_time_zone("UTC")}' and l2.created_at <= '#{@until_time.in_time_zone("UTC")}'
UNION
  SELECT l2.*
    FROM logins l2 INNER JOIN
    (SELECT l.ip_address,COUNT(DISTINCT u.id) as count
      FROM logins l
      INNER JOIN users u ON l.user_id =  u.id
      WHERE l.created_at >= '#{@since_time.in_time_zone("UTC")}' and l.created_at <= '#{@until_time.in_time_zone("UTC")}'
      GROUP BY l.ip_address
      HAVING count > 1
    ) ml on ml.ip_address = l2.ip_address
    INNER JOIN users u ON l2.user_id = u.id
    WHERE l2.created_at >= '#{@since_time.in_time_zone("UTC")}' and l2.created_at <= '#{@until_time.in_time_zone("UTC")}'
ORDER BY ip_address,created_at
              SQL
    @mld = Login.find_by_sql(st)

    st = <<-SQL
  SELECT s.id,s.user_id,s.ip_address,s.submitted_at,s.problem_id
    FROM submissions s INNER JOIN
    (SELECT u.id,COUNT(DISTINCT ip_address) as count,u.login,u.full_name
      FROM logins l
      INNER JOIN users u ON l.user_id =  u.id
      WHERE l.created_at >= ? and l.created_at <= ?
      GROUP BY u.id
      HAVING count > 1
    ) ml ON s.user_id = ml.id
    WHERE s.submitted_at >= ? and s.submitted_at <= ?
UNION
  SELECT s.id,s.user_id,s.ip_address,s.submitted_at,s.problem_id
    FROM submissions s INNER JOIN
    (SELECT l.ip_address,COUNT(DISTINCT u.id) as count
      FROM logins l
      INNER JOIN users u ON l.user_id =  u.id
      WHERE l.created_at >= ? and l.created_at <= ?
      GROUP BY l.ip_address
      HAVING count > 1
    ) ml on ml.ip_address = s.ip_address
    WHERE s.submitted_at >= ? and s.submitted_at <= ?
ORDER BY ip_address,submitted_at
            SQL
    @subs = Submission.joins(:problem).find_by_sql([st, @since_time, @until_time,
                                       @since_time, @until_time,
                                       @since_time, @until_time,
                                       @since_time, @until_time])
  end

  def cheat_scrutinize
    # convert date & time
    date_and_time = '%Y-%m-%d %H:%M'
    begin
      md = params[:since_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @since_time = Time.zone.local(md[1].to_i, md[2].to_i, md[3].to_i, md[4].to_i, md[5].to_i)
    rescue
      @since_time = Time.zone.now.ago(90.minutes)
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i, md[2].to_i, md[3].to_i, md[4].to_i, md[5].to_i)
    rescue
      @until_time = Time.zone.now
    end

    # convert sid
    @sid = params[:SID].split(/[,\s]/) if params[:SID]
    unless @sid and @sid.size > 0
      return
      redirect_to actoin: :cheat_scrutinize
      flash[:notice] = 'Please enter at least 1 student id'
    end
    mark = Array.new(@sid.size, '?')
    condition = "(u.login = " + mark.join(' OR u.login = ') + ')'

    @st = <<-SQL
  SELECT l.created_at as submitted_at ,-1 as id,u.login,u.full_name,l.ip_address,"" as problem_id,"" as points,l.user_id
  FROM logins l INNER JOIN users u on l.user_id  = u.id
  WHERE l.created_at >= ? AND l.created_at <= ? AND #{condition}
UNION
  SELECT s.submitted_at,s.id,u.login,u.full_name,s.ip_address,s.problem_id,s.points,s.user_id
  FROM submissions s INNER JOIN users u ON s.user_id = u.id
  WHERE s.submitted_at >= ? AND s.submitted_at <= ? AND #{condition}
ORDER BY submitted_at
  SQL

    p = [@st, @since_time, @until_time] + @sid + [@since_time, @until_time] + @sid
    @logs = Submission.joins(:problem).find_by_sql(p)
  end

  protected

    # receive an ActiveRecord::AAssociation *query* of submissions
    # and add more where clause limiting the submission to be in the
    # rnage specified only
    def submission_in_range(range_params)
      range_params ||= {}
      if range_params[:use] ==  'sub_id'
        Submission.by_id_range(range_params[:from_id], range_params[:to_id])
      else
        # use sub time
        since_time = Time.zone.parse(range_params[:from_time]) || Time.zone.now.beginning_of_day rescue Time.zone.now.beginning_of_day
        until_time = Time.zone.parse(range_params[:to_time]) || Time.zone.now.end_of_day rescue Time.zone.now.end_of_day
        Submission.by_submitted_at(since_time, until_time)
      end
    end

    # build @problems that matches the given params
    def selected_problems
      # start with reportable problems (this already consider when @current_user is an admin)
      @problems = Problem.where(id: @current_user.problems_for_action(:report).ids)

      # problem
      prob_use = params[:probs][:use] rescue ''
      if prob_use == 'all'
        @problems = Problem.all
      elsif prob_use == 'ids'
        @problems = @problems.where(id: params[:probs][:ids])
      elsif prob_use == 'groups'
        ids = Group.where(id: params[:probs][:group_ids]).joins(:problems).pluck(:problem_id).uniq
        @problems = @problems.where(id: ids)
      elsif prob_use == 'tags'
        ids = Tag.where(id: params[:probs][:tag_ids]).joins(:problems).pluck(:problem_id).uniq
        @problems = @problems.where(id: ids)
      else
        # wrong PARAM
        @problems = Problem.none
      end

      # sort it
      @problems = @current_user.problems_for_action(:report).where(id: @problems.ids).order(:date_added)
    end

    def selected_users
      return (@users = User.none) unless params.has_key? :users
      @users = if params[:users][:use] == "group" then
                 if params[:users][:only_users]
                   User.where(id: Group.where(id: params[:users][:group_ids]).joins(:groups_users).where(groups_users: {role: 'user'}).pluck(:user_id))
                 else
                   User.where(id: Group.where(id: params[:users][:group_ids]).joins(:groups_users).pluck(:user_id))
                 end
      elsif params[:users][:use] == 'enabled'
                 User.where(enabled: true)
      elsif params[:users][:use] == 'all'
                 User.all
      else
                 # wrong PARAM
                 User.none
      end

      # if user is not admin, filter problem to be only that are reportable
      @users = @users.where(id: @current_user.reportable_users) unless @current_user.admin?
    end

    def hall_of_fame_authorization
      return true if @current_user.admin?
      unauthorized_redirect(msg: 'Hall of fame is disabled') unless GraderConfiguration["right.user_hall_of_fame"]
    end

    def set_problem
      @problem = Problem.find(params[:id])
    end
end
