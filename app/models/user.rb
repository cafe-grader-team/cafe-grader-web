require 'digest/sha1'

class User < ActiveRecord::Base

  has_and_belongs_to_many :roles

  validates_presence_of :login
  validates_presence_of :full_name
  
  validates_presence_of :password, :if => :password_required?
  validates_length_of :password, :within => 4..20, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?

  attr_accessor :password

  before_save :encrypt_new_password

  def self.authenticate(login, password)
    user = find_by_login(login)
    return user if user && user.authenticated?(password)
  end

  def authenticated?(password)
    hashed_password == encrypt(password,salt)
  end

  def admin?
    self.roles.detect {|r| r.name == 'admin' }
  end

  def email_for_editing
    if self.email!=nil
      self.email
    else
      "unknown"
    end
  end

  def email_for_editing=(e)
    self.email=e
  end

  def alias_for_editing
    if self.alias!=nil
      self.alias
    else
      "unknown"
    end
  end

  def alias_for_editing=(e)
    self.alias=e
  end

  protected
    def encrypt_new_password
      return if password.blank?
      self.salt = (10+rand(90)).to_s
      self.hashed_password = encrypt(password,salt)
    end
  
    def password_required?
      hashed_password.blank? || !password.blank?
    end
  
    def encrypt(string,salt)
      Digest::SHA1.hexdigest(salt + string)
    end
end
