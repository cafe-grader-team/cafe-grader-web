class ReportController < ApplicationController
  def login_stat
    @logins = Array.new
    login = Login.all
    User.all.each do |user|
      @logins << { login: user.login, 
                   full_name: user.full_name, 
                   count: Login.where(user_id: user.id).count(:id), 
                   min: Login.where(user_id: user.id).maximum(:created_at),
                   max: Login.where(user_id: user.id).minimum(:created_at) }
    end
  end
end
