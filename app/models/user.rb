require 'digest/sha1'

class User < ActiveRecord::Base

  has_and_belongs_to_many :roles

  has_many :test_requests, :order => "submitted_at DESC"

  has_many :messages, 
           :class_name => "Message",
           :foreign_key => "sender_id", 
           :order => 'created_at DESC'

  has_many :replied_messages, 
           :class_name => "Message",
           :foreign_key => "receiver_id", 
           :order => 'created_at DESC'

  has_one :contest_stat, :class_name => "UserContestStat", :dependent => :destroy

  belongs_to :site
  belongs_to :country

  has_and_belongs_to_many :contests, :uniq => true

  named_scope :activated_users, :conditions => {:activated => true}

  validates_presence_of :login
  validates_uniqueness_of :login
  validates_format_of :login, :with => /^[\_A-Za-z0-9]+$/
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

  def self.authenticate(login, password)
    user = find_by_login(login)
    return user if user && user.authenticated?(password)
  end

  def authenticated?(password)
    if self.activated
      hashed_password == User.encrypt(password,self.salt)
    else
      false
    end
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
    users = User.find(:all)
    return users.find_all { |u| !(u.admin?) and u.login.index(prefix)==0 }
  end

  # Contest information

  def contest_time_left
    if Configuration.contest_mode?
      return nil if site==nil
      return site.time_left
    elsif Configuration.indv_contest_mode?
      time_limit = Configuration.contest_time_limit
      if time_limit == nil
        return nil
      end
      if contest_stat==nil
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
    if Configuration.contest_mode?
      return false if site==nil
      return site.finished?
    elsif Configuration.indv_contest_mode?
      time_limit = Configuration.contest_time_limit

      return false if contest_stat==nil

      return contest_time_left == 0
    else
      return false
    end
  end

  def contest_started?
    if Configuration.contest_mode?
      return true if site==nil
      return site.started
    else
      return true
    end
  end

  def update_start_time
    stat = self.contest_stat
    if stat == nil
      stat = UserContestStat.new(:user => self,
                                 :started_at => Time.now.gmtime)
      stat.save
    end
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

    def password_required?
      self.hashed_password.blank? || !self.password.blank?
    end
  
    def self.encrypt(string,salt)
      Digest::SHA1.hexdigest(salt + string)
    end

    def uniqueness_of_email_from_activated_users
      user = User.activated_users.find_by_email(self.email)
      if user and (user.login != self.login)
        self.errors.add_to_base("Email has already been taken")
      end
    end
    
    def enough_time_interval_between_same_email_registrations
      return if !self.new_record?
      return if self.activated
      open_user = User.find_by_email(self.email,
                                     :order => 'created_at DESC')
      if open_user and open_user.created_at and 
          (open_user.created_at > Time.now.gmtime - 5.minutes)
        self.errors.add_to_base("There are already unactivated registrations with this e-mail address (please wait for 5 minutes)")
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
