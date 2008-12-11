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

  belongs_to :site
  belongs_to :country

  named_scope :activated_users, :conditions => {:activated => true}

  validates_presence_of :login
  validates_uniqueness_of :login
  validates_format_of :login, :with => /^[\_a-z0-9]+$/
  validates_length_of :login, :within => 3..10

  validates_presence_of :full_name
  validates_length_of :full_name, :minimum => 1
  
  validates_presence_of :password, :if => :password_required?
  validates_length_of :password, :within => 4..20, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?

  validates_format_of :email, :with => /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i, :allow_blank => true

  validate :uniqueness_of_email_from_activated_users
  validate :enough_time_interval_between_same_email_registrations

  attr_accessor :password

  before_save :encrypt_new_password

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

  protected
    def encrypt_new_password
      return if password.blank?
      self.salt = (10+rand(90)).to_s
      self.hashed_password = User.encrypt(self.password,self.salt)
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
      open_user = User.find_by_email(self.email,
                                     :order => 'created_at DESC')
      if open_user and open_user.created_at and 
          (open_user.created_at > Time.now.gmtime - 5.minutes)
        self.errors.add_to_base("There are already unactivated registrations with this e-mail address (please wait for 5 minutes)")
      end
    end
end
