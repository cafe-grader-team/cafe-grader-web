
# This test helper loads the grader's environment and rails environment

GRADER_ENV = 'test'
require File.join(File.dirname(__FILE__),'../config/environment')


# this shall be removed soon
RAILS_ENV = Grader::Configuration.get_instance.rails_env
require RAILS_ROOT + '/config/environment'

# make sure not to access real database!
# taken from http://blog.jayfields.com/2006/06/ruby-on-rails-unit-tests.html

class UnitTest
  def self.TestCase
    class << ActiveRecord::Base
      def connection
        raise 'You cannot access the database from a unit test'
#        raise InvalidActionError, 'You cannot access the database from a unit test', caller
      end
    end
    Test::Unit::TestCase
  end
end
