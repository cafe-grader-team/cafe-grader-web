ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

#reporter for beautiful result
require "minitest/reporters"
Minitest::Reporters.use!

module SignInHelper
  def sign_in_as(user,password)
    post login_login_path, {login: user, password: password }
  end
end

class ActiveSupport::TestCase
  include SignInHelper
  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...

  self.use_transactional_fixtures = true
  self.use_instantiated_fixtures  = false
end
