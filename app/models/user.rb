require 'digest/sha1'
require 'net/pop'
require 'net/https'
require 'net/http'
require 'json'

class User < ActiveRecord::Base

  has_and_belongs_to_many :roles
  has_and_belongs_to_many :groups

  has_many :test_requests, -> {order(submitted_at: DESC)}

  has_many :messages, -> { order(created_at: DESC) },
           :class_name => "Message",
           :foreign_key => "sender_id"

  has_many :replied_messages, -> { order(created_at: DESC) },
           :class_name => "Message",
           :foreign_key => "receiver_id"

  has_one :contest_stat, :class_name => "UserContestStat", :dependent => :destroy

  belongs_to :site
  belongs_to :country

  has_and_belongs_to_many :contests, -> { order(:name); uniq}

  scope :activated_users, -> {where activated: true}

  validates_presence_of :login
  validates_uniqueness_of :login
  validates_format_of :login, :with => /\A[\_A-Za-z0-9]+\z/
  validates_length_of :login, :within => 3..30

  validates_presence_of :full_name
  validates_length_of :full_name, :minimum => 1
  
  validates_presence_of :password, :if => :password_required?
  validates_length_of :password, :within => 4..20, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?

  validates_format_of :email, 
                      :with => /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i, 
                      :if => :email_validation?
  validate :uniqueness_of_email_from_activated_users, 
           :if => :email_validation?
  validate :enough_time_interval_between_same_email_registrations, 
           :if => :email_validation?

  # these are for ytopc
  # disable for now
  #validates_presence_of :province

  attr_accessor :password

  before_save :encrypt_new_password
  before_save :assign_default_site
  before_save :assign_default_contest

  # this is for will_paginate
  cattr_reader :per_page
  @@per_page = 50

  def self.authenticate(login, password)
    user = find_by_login(login)
    if user
      return user if user.authenticated?(password)
      if user.authenticated_by_cucas?(password) or user.authenticated_by_pop3?(password)
        user.password = password
        user.save
        return user
      end
    end
  end

  def authenticated?(password)
    if self.activated
      hashed_password == User.encrypt(password,self.salt)
    else
      false
    end
  end

  def authenticated_by_pop3?(password)
    Net::POP3.enable_ssl
    pop = Net::POP3.new('pops.it.chula.ac.th')
    authen = true
    begin
      pop.start(login, password)
      pop.finish
      return true
    rescue 
      return false
    end
  end

  def authenticated_by_cucas?(password)
    url = URI.parse('https://www.cas.chula.ac.th/cas/api/?q=studentAuthenticate')
    appid = '41508763e340d5858c00f8c1a0f5a2bb'
    appsecret ='d9cbb5863091dbe186fded85722a1e31'
    post_args = {
      'appid' => appid,
      'appsecret' => appsecret,
      'username' => login,
      'password' => password
    }

    #simple call
    begin
      http = Net::HTTP.new('www.cas.chula.ac.th', 443)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      result = [ ]
      http.start do |http|
        req = Net::HTTP::Post.new('/cas/api/?q=studentAuthenticate')
        param = "appid=#{appid}&appsecret=#{appsecret}&username=#{login}&password=#{password}"
        resp = http.request(req,param)
        result = JSON.parse resp.body
      end
      return true if result["type"] == "beanStudent"
    rescue => e
      return false
    end
    return false
  end

  def admin?
    self.roles.detect {|r| r.name == 'admin' }
  end

  def email_for_editing
    if self.email==nil
      "(unknown)"
    elsif self.email==''
      "(blank)"
    else
      self.email
    end
  end

  def email_for_editing=(e)
    self.email=e
  end

  def alias_for_editing
    if self.alias==nil
      "(unknown)"
    elsif self.alias==''
      "(blank)"
    else
      self.alias
    end
  end

  def alias_for_editing=(e)
    self.alias=e
  end

  def activation_key
    if self.hashed_password==nil
      encrypt_new_password
    end
    Digest::SHA1.hexdigest(self.hashed_password)[0..7]
  end

  def verify_activation_key(key)
    key == activation_key
  end

  def self.random_password(length=5)
    chars = 'abcdefghjkmnopqrstuvwxyz'
    password = ''
    length.times { password << chars[rand(chars.length - 1)] }
    password
  end

  def self.find_non_admin_with_prefix(prefix='')
    users = User.all
    return users.find_all { |u| !(u.admin?) and u.login.index(prefix)==0 }
  end

  # Contest information

  def self.find_users_with_no_contest()
    users = User.all
    return users.find_all { |u| u.contests.length == 0 }
  end


  def contest_time_left
    if GraderConfiguration.contest_mode?
      return nil if site==nil
      return site.time_left
    elsif GraderConfiguration.indv_contest_mode?
      time_limit = GraderConfiguration.contest_time_limit
      if time_limit == nil
        return nil
      end
      if contest_stat==nil or contest_stat.started_at==nil
        return (Time.now.gmtime + time_limit) - Time.now.gmtime
      else
        finish_time = contest_stat.started_at + time_limit
        current_time = Time.now.gmtime
        if current_time > finish_time
          return 0
        else
          return finish_time - current_time
        end
      end
    else
      return nil
    end
  end

  def contest_finished?
    if GraderConfiguration.contest_mode?
      return false if site==nil
      return site.finished?
    elsif GraderConfiguration.indv_contest_mode?
      return false if self.contest_stat(true)==nil
      return contest_time_left == 0
    else
      return false
    end
  end

  def contest_started?
    if GraderConfiguration.indv_contest_mode?
      stat = self.contest_stat
      return ((stat != nil) and (stat.started_at != nil))
    elsif GraderConfiguration.contest_mode?
      return true if site==nil
      return site.started
    else
      return true
    end
  end

  def update_start_time
    stat = self.contest_stat
    if stat.nil? or stat.started_at.nil?
      stat ||= UserContestStat.new(:user => self)
      stat.started_at = Time.now.gmtime
      stat.save
    end
  end

  def problem_in_user_contests?(problem)
    problem_contests = problem.contests.all

    if problem_contests.length == 0   # this is public contest
      return true
    end

    contests.each do |contest|
      if problem_contests.find {|c| c.id == contest.id }
        return true
      end
    end
    return false
  end

  def available_problems_group_by_contests
    contest_problems = []
    pin = {}
    contests.enabled.each do |contest|
      available_problems = contest.problems.available
      contest_problems << {
        :contest => contest,
        :problems => available_problems
      }
      available_problems.each {|p| pin[p.id] = true}
    end
    other_avaiable_problems = Problem.available.find_all {|p| pin[p.id]==nil and p.contests.length==0}
    contest_problems << {
      :contest => nil,
      :problems => other_avaiable_problems
    }
    return contest_problems
  end

  def solve_all_available_problems?
    available_problems.each do |p|
      u = self
      sub = Submission.find_last_by_user_and_problem(u.id,p.id)
      return false if !p or !sub or sub.points < p.full_score
    end
    return true
  end

  def available_problems
    if not GraderConfiguration.multicontests?
      if GraderConfiguration.use_problem_group?
        return available_problems_in_group
      else
        return Problem.available_problems
      end
    else
      contest_problems = []
      pin = {}
      contests.enabled.each do |contest|
        contest.problems.available.each do |problem|
          if not pin.has_key? problem.id
            contest_problems << problem
          end
          pin[problem.id] = true
        end
      end
      other_avaiable_problems = Problem.available.find_all {|p| pin[p.id]==nil and p.contests.length==0}
      return contest_problems + other_avaiable_problems
    end
  end

  def available_problems_in_group
    problem = []
    self.groups.each do |group|
      group.problems.where(available: true).each { |p| problem << p }
    end
    problem.uniq!.sort! do |a,b|
      case
      when a.date_added < b.date_added
        -1
      when a.date_added > b.date_added
        1
      else
        a.name <=> b.name
      end
    end
    return problem
  end

  def can_view_problem?(problem)
    if not GraderConfiguration.multicontests?
      return problem.available
    else
      return problem_in_user_contests? problem
    end
  end

  def self.clear_last_login
    User.update_all(:last_ip => nil)
  end

  protected
    def encrypt_new_password
      return if password.blank?
      self.salt = (10+rand(90)).to_s
      self.hashed_password = User.encrypt(self.password,self.salt)
    end
  
    def assign_default_site
      # have to catch error when migrating (because self.site is not available).
      begin
        if self.site==nil
          self.site = Site.find_by_name('default')
          if self.site==nil
            self.site = Site.find(1)  # when 'default has be renamed'
          end
        end
      rescue
      end
    end

    def assign_default_contest
      # have to catch error when migrating (because self.site is not available).
      begin
        if self.contests.length == 0
          default_contest = Contest.find_by_name(GraderConfiguration['contest.default_contest_name'])
          if default_contest
            self.contests = [default_contest]
          end
        end
      rescue
      end
    end

    def password_required?
      self.hashed_password.blank? || !self.password.blank?
    end
  
    def self.encrypt(string,salt)
      Digest::SHA1.hexdigest(salt + string)
    end

    def uniqueness_of_email_from_activated_users
      user = User.activated_users.find_by_email(self.email)
      if user and (user.login != self.login)
        self.errors.add(:base,"Email has already been taken")
      end
    end
    
    def enough_time_interval_between_same_email_registrations
      return if !self.new_record?
      return if self.activated
      open_user = User.find_by_email(self.email,
                                     :order => 'created_at DESC')
      if open_user and open_user.created_at and 
          (open_user.created_at > Time.now.gmtime - 5.minutes)
        self.errors.add(:base,"There are already unactivated registrations with this e-mail address (please wait for 5 minutes)")
      end
    end

    def email_validation?
      begin
        return VALIDATE_USER_EMAILS
      rescue
        return false
      end
    end
end
