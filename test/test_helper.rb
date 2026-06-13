ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

#reporter for beautiful result
require "minitest/reporters"
Minitest::Reporters.use!

module SignInHelper
  def sign_in_as(user, password)
    post login_login_path, params: { login: user, password: password }
  end
end

module GraderConfigHelper
  def reset_grader_config_cache
    GraderConfiguration.instance_variable_set(:@config_cache, nil)
  end

  def set_grader_config(key, value)
    conf = GraderConfiguration.find_by(key: key)
    conf.update!(value: value.to_s) if conf
    reset_grader_config_cache
  end
end

class ActiveSupport::TestCase
  include SignInHelper
  include GraderConfigHelper

  # Map fixture filenames to their model classes (needed for join tables with custom table_name)
  set_fixture_class groups_users: GroupUser,
                    groups_problems: GroupProblem,
                    contests_users: ContestUser,
                    contests_problems: ContestProblem

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  fixtures :all

  self.use_transactional_tests = true
  self.use_instantiated_fixtures = false

  setup do
    GraderConfiguration.instance_variable_set(:@config_cache, nil)
  end
end
