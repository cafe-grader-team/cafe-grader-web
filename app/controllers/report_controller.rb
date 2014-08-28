class ReportController < ApplicationController
  def login_stat
    @logins = Array.new

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
    
    User.all.each do |user|
      @logins << { login: user.login, 
                   full_name: user.full_name, 
                   count: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .count(:id),
                   min: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .minimum(:created_at),
                   max: Login.where("user_id = ? AND created_at >= ? AND created_at <= ?",
                                      user.id,@since_time,@until_time)
                          .maximum(:created_at)
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
