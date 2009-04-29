# Rails app directory
RAILS_ROOT = File.join(File.dirname(__FILE__),"../../..")

GRADER_ROOT = File.join(File.dirname(__FILE__),"..")

# This load all required codes
require File.join(File.dirname(__FILE__),'../lib/boot')

# load the required environment file
require File.dirname(__FILE__) + "/env_#{GRADER_ENV}.rb"
