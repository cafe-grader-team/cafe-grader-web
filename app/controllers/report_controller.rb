require 'csv'

class ReportController < ApplicationController

  before_filter :authenticate

  before_filter :admin_authorization, only: [:login_stat,:submission_stat, :stuck, :cheat_report, :cheat_scruntinize, :show_max_score, :current_score]

  before_filter(only: [:problem_hof]) { |c|
    return false unless authenticate

    admin_authorization unless GraderConfiguration["right.user_view_submission"]
  }

  def max_score
  end

  def current_score
    @problems = Problem.available_problems
    @users = User.includes(:contests).includes(:contest_stat).where(enabled: true)
    @scorearray = calculate_max_score(@problems, @users,0,0,true)

    #rencer accordingly
    if params[:button] == 'download' then
      csv = gen_csv_from_scorearray(@scorearray,@problems)
      send_data csv, filename: 'max_score.csv'
    else
      #render template: 'user_admin/user_stat'
      render 'current_score'
    end
  end

  def show_max_score
    #process parameters
    #problems
    @problems = []
    if params[:problem_id]
      params[:problem_id].each do |id|
        next unless id.strip != ""
        pid = Problem.find_by_id(id.to_i)
        @problems << pid if pid
      end
    end

    #users
    @users = if params[:user] == "all" then 
               User.includes(:contests).includes(:contest_stat)
             else 
               User.includes(:contests).includes(:contest_stat).where(enabled: true)
             end

    #set up range from param
    @since_id = params.fetch(:from_id, 0).to_i
    @until_id = params.fetch(:to_id, 0).to_i
    @since_id = nil if @since_id == 0
    @until_id = nil if @until_id == 0

    #calculate the routine
    @scorearray = calculate_max_score(@problems, @users, @since_id, @until_id)

    #rencer accordingly
    if params[:button] == 'download' then
      csv = gen_csv_from_scorearray(@scorearray,@problems)
      send_data csv, filename: 'max_score.csv'
    else
      #render template: 'user_admin/user_stat'
      render 'max_score'
    end

  end

  def score
    if params[:commit] == 'download csv'
      @problems = Problem.all
    else
      @problems = Problem.available_problems
    end
    @users = User.includes(:contests, :contest_stat).where(enabled: true) 
    @scorearray = Array.new
    @users.each do |u|
      ustat = Array.new
      ustat[0] = u
      @problems.each do |p|
        sub = Submission.find_last_by_user_and_problem(u.id,p.id)
        if (sub!=nil) and (sub.points!=nil) and p and p.full_score
          ustat << [(sub.points.to_f*100/p.full_score).round, (sub.points>=p.full_score)]
        else
          ustat << [0,false]
        end
      end
      @scorearray << ustat
    end
    if params[:commit] == 'download csv' then
      csv = gen_csv_from_scorearray(@scorearray,@problems)
      send_data csv, filename: 'last_score.csv'
    else
      render template: 'user_admin/user_stat'
    end

  end

  def login_stat
    @logins = Array.new

    date_and_time = '%Y-%m-%d %H:%M'
    begin
      md = params[:since_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @since_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @since_time = DateTime.new(1000,1,1)
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @until_time = DateTime.new(3000,1,1)
    end
    
    User.all.each do |user|
      @logins << { id: user.id,
                   login: user.login, 
                   full_name: user.full_name, 
                   count: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .count(:id),
                   min: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .minimum(:created_at),
                   max: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .maximum(:created_at),
                    ip: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .select(:ip_address).uniq

                 }
    end
  end

  def submission_stat

    date_and_time = '%Y-%m-%d %H:%M'
    begin
      @since_time = DateTime.strptime(params[:since_datetime],date_and_time)
    rescue
      @since_time = DateTime.new(1000,1,1)
    end
    begin
      @until_time = DateTime.strptime(params[:until_datetime],date_and_time)
    rescue
      @until_time = DateTime.new(3000,1,1)
    end

    @submissions = {}

    User.find_each do |user|
      @submissions[user.id] = { login: user.login, full_name: user.full_name, count: 0, sub: { } }
    end

    Submission.where("submitted_at >= ? AND submitted_at <= ?",@since_time,@until_time).find_each do |s|
      if @submissions[s.user_id]
        if not @submissions[s.user_id][:sub].has_key?(s.problem_id)
          a = Problem.find_by_id(s.problem_id)
          @submissions[s.user_id][:sub][s.problem_id] = 
            { prob_name: (a ? a.full_name : '(NULL)'),
              sub_ids: [s.id] } 
        else
          @submissions[s.user_id][:sub][s.problem_id][:sub_ids] << s.id
        end
        @submissions[s.user_id][:count] += 1
      end
    end
  end

  def problem_hof
    # gen problem list
    @user = User.find(session[:user_id])
    @problems = @user.available_problems

    # get selected problems or the default
    if params[:id]
      begin
        @problem = Problem.available.find(params[:id])
      rescue
        redirect_to action: :problem_hof
        flash[:notice] = 'Error: submissions for that problem are not viewable.'
        return
      end
    end

    return unless @problem

    @by_lang = {} #aggregrate by language

    range =65
    @histogram = { data: Array.new(range,0), summary: {} }
    @summary = {count: 0, solve: 0, attempt: 0}
    user = Hash.new(0)
    Submission.where(problem_id: @problem.id).find_each do |sub|
      #histogram
      d = (DateTime.now.in_time_zone - sub.submitted_at) / 24 / 60 / 60
      @histogram[:data][d.to_i] += 1 if d < range

      next unless sub.points
      @summary[:count] += 1
      user[sub.user_id] = [user[sub.user_id], (sub.points >= @problem.full_score) ? 1 : 0].max

      lang = Language.find_by_id(sub.language_id)
      next unless lang
      next unless sub.points >= @problem.full_score

      #initialize
      unless @by_lang.has_key?(lang.pretty_name)
        @by_lang[lang.pretty_name] = {
          runtime: { avail: false, value: 2**30-1 },
          memory: { avail: false, value: 2**30-1 },
          length: { avail: false, value: 2**30-1 },
          first: { avail: false, value: DateTime.new(3000,1,1) }
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

      if @by_lang[lang.pretty_name][:length][:value] > sub.effective_code_length
        @by_lang[lang.pretty_name][:length] = { avail: true, user_id: sub.user_id, value: sub.effective_code_length, sub_id: sub.id }
      end
    end

    #process user_id
    @by_lang.each do |lang,prop|
      prop.each do |k,v|
        v[:user] = User.exists?(v[:user_id]) ? User.find(v[:user_id]).full_name : "(NULL)"
      end
    end

    #sum into best
    if @by_lang and @by_lang.first
      @best = @by_lang.first[1].clone
      @by_lang.each do |lang,prop|
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

    @histogram[:summary][:max] = [@histogram[:data].max,1].max
    @summary[:attempt] = user.count
    user.each_value { |v| @summary[:solve] += 1 if v == 1 }
  end

  def stuck #report struggling user,problem
    # init
    user,problem = nil
    solve = true
    tries = 0
    @struggle = Array.new
    record = {}
    Submission.includes(:problem,:user).order(:problem_id,:user_id).find_each do |sub|
      next unless sub.problem and sub.user
      if user != sub.user_id or problem != sub.problem_id
        @struggle << { user: record[:user], problem: record[:problem], tries: tries } unless solve
        record = {user: sub.user, problem: sub.problem}
        user,problem = sub.user_id, sub.problem_id
        solve = false
        tries = 0
      end
      if sub.points >= sub.problem.full_score
        solve = true
      else
        tries += 1
      end
    end
    @struggle.sort!{|a,b| b[:tries] <=> a[:tries] }
    @struggle = @struggle[0..50]
  end


  def multiple_login
    #user with multiple IP
    raw = Submission.joins(:user).joins(:problem).where("problems.available != 0").group("login,ip_address").order(:login)
    last,count = 0,0
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

    #IP with multiple user
    raw = Submission.joins(:user).joins(:problem).where("problems.available != 0").group("login,ip_address").order(:ip_address)
    last,count = 0,0
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
      @since_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @since_time = Time.zone.now.ago( 90.minutes)
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @until_time = Time.zone.now
    end

    #multi login
    @ml = Login.joins(:user).where("logins.created_at >= ? and logins.created_at <= ?",@since_time,@until_time).select('users.login,count(distinct ip_address) as count,users.full_name').group("users.id").having("count > 1")

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
    @subs = Submission.joins(:problem).find_by_sql([st,@since_time,@until_time,
                                       @since_time,@until_time,
                                       @since_time,@until_time,
                                       @since_time,@until_time])

  end

  def cheat_scruntinize
    #convert date & time
    date_and_time = '%Y-%m-%d %H:%M'
    begin
      md = params[:since_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @since_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @since_time = Time.zone.now.ago( 90.minutes)
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @until_time = Time.zone.now
    end

    #convert sid
    @sid = params[:SID].split(/[,\s]/) if params[:SID]
    unless @sid and @sid.size > 0
      return 
      redirect_to actoin: :cheat_scruntinize
      flash[:notice] = 'Please enter at least 1 student id'
    end
    mark = Array.new(@sid.size,'?')
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
    
    p = [@st,@since_time,@until_time] + @sid + [@since_time,@until_time] + @sid
    @logs = Submission.joins(:problem).find_by_sql(p)





  end

  protected

  def calculate_max_score(problems, users,since_id,until_id, get_last_score = false)
    scorearray = Array.new
    users.each do |u|
      ustat = Array.new
      ustat[0] = u
      problems.each do |p|
        unless get_last_score
          #get max score
          max_points = 0
          Submission.find_in_range_by_user_and_problem(u.id,p.id,since_id,until_id).each do |sub|
            max_points = sub.points if sub and sub.points and (sub.points > max_points)
          end
          ustat << [(max_points.to_f*100/p.full_score).round, (max_points>=p.full_score)]
        else
          #get latest score
          sub = Submission.find_last_by_user_and_problem(u.id,p.id)
          if (sub!=nil) and (sub.points!=nil) and p and p.full_score
            ustat << [(sub.points.to_f*100/p.full_score).round, (sub.points>=p.full_score)]
          else
            ustat << [0,false]
          end
        end
      end
      scorearray << ustat
    end
    return scorearray
  end

  def gen_csv_from_scorearray(scorearray,problem)
    CSV.generate do |csv|
      #add header
      header = ['User','Name', 'Activated?', 'Logged in', 'Contest']
      problem.each { |p| header << p.name }
      header += ['Total','Passed']
      csv << header
      #add data
      scorearray.each do |sc|
        total = num_passed = 0
        row = Array.new
        sc.each_index do |i|
          if i == 0
            row << sc[i].login
            row << sc[i].full_name
            row << sc[i].activated
            row << (sc[i].try(:contest_stat).try(:started_at)!=nil ? 'yes' : 'no')
            row << sc[i].contests.collect {|c| c.name}.join(', ')
          else
            row << sc[i][0]
            total += sc[i][0]
            num_passed += 1 if sc[i][1]
          end
        end
        row << total 
        row << num_passed
        csv << row
      end
    end
  end

end
