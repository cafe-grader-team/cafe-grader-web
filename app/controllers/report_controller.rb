class ReportController < ApplicationController

  before_filter :admin_authorization, only: [:login_stat,:submission_stat, :stuck]
  before_filter(only: [:problem_hof]) { |c|
    return false unless authenticate

    if GraderConfiguration["right.user_view_submission"]
      return true;
    end

    admin_authorization
  }

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
          a = nil
          begin
            a = Problem.find(s.problem_id)
          rescue
            a = nil
          end
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

      if sub.submitted_at and sub.submitted_at < @by_lang[lang.pretty_name][:first][:value] and
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
      @since_time = Time.zone.now
    end
    begin
      md = params[:until_datetime].match(/(\d+)-(\d+)-(\d+) (\d+):(\d+)/)
      @until_time = Time.zone.local(md[1].to_i,md[2].to_i,md[3].to_i,md[4].to_i,md[5].to_i)
    rescue
      @until_time = Time.zone.now.ago( 90.minutes)
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

#  st =
#      " INNER JOIN" +
#      "(SELECT u.id,l.ip_address,COUNT(DISTINCT ip_address) as count " +
#      " FROM logins l INNER JOIN users u ON l.user_id = u.id "+
#      " WHERE l.created_at >= '#{@since_time.in_time_zone("UTC")}' and l.created_at <= '#{@until_time.in_time_zone("UTC")}' " +
#      " GROUP BY u.id" +
#      " HAVING count > 1) ml " 
#  #ml detail
#  @mld = Login.joins(st + "ON logins.user_id = ml.id").
#    where("logins.created_at >= ? and logins.created_at <= ?",@since_time,@until_time).
#    order("ip_address")
#
#  #submissions
#  @subs =  Submission.joins(:problem).joins(st + "ON submissions.user_id = ml.id").
#    where("submissions.submitted_at >= ? and submissions.submitted_at <= ?",@since_time,@until_time).
#    order("submissions.ip_address")
  end


end
