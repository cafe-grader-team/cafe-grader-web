require 'yaml'

#
# This class also contains various login of the system.
#
class GraderConfiguration < ApplicationRecord
  include Auditable
  audited

  SYSTEM_MODE_CONF_KEY = 'system.mode'
  TEST_REQUEST_EARLY_TIMEOUT_KEY = 'contest.test_request.early_timeout'
  MULTICONTESTS_KEY = 'system.multicontests'
  CONTEST_TIME_LIMIT_KEY = 'contest.time_limit'
  MULTIPLE_IP_LOGIN_KEY = 'right.multiple_ip_login'
  VIEW_TESTCASE = 'right.view_testcase'
  SINGLE_USER_KEY = 'system.single_user_mode'
  SYSTEM_USE_PROBLEM_GROUP = 'system.use_problem_group'
  SYSTEM_MINIMUM_LAST_LOGIN_TIME = 'system.min_last_login_time'

  # class_attribute :config_cache
  cattr_accessor :task_grading_info_cache
  cattr_accessor :contest_time_str
  cattr_accessor :contest_time

  # GraderConfiguration.config_cache = nil
  GraderConfiguration.task_grading_info_cache = nil

  def self.get(key)
    if @config_cache.nil?
      self.read_config
    end

    # return GraderConfiguration.config_cache[key]
    return @config_cache[key]
  end

  def self.[](key)
    self.get(key)
  end

  def self.minimum_last_login_time
    time_text = self.get(SYSTEM_MINIMUM_LAST_LOGIN_TIME)
    return Time.new(time_text) if time_text
    return Date.new(1, 1, 1)
  end

  def self.update_min_last_login
    conf = GraderConfiguration.find_or_create_by(key: SYSTEM_MINIMUM_LAST_LOGIN_TIME)
    conf.update(value: Time.zone.now, value_type: 'string')
  end

  def self.site_name
    return GraderConfiguration.get('ui.site_name')
  end

  #
  # View decision
  #
  def self.show_submitbox_to?(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    return false if mode=='analysis'
    return true
  end

  def self.show_tasks_to?(user)
    # if time_limit_mode?
    #  return false if not user.contest_started?
    # end
    return true
  end

  def self.show_grading_result
    return (get(SYSTEM_MODE_CONF_KEY)=='analysis')
  end

  def  self.show_testcase
    return get(VIEW_TESTCASE)
  end

  def self.allow_test_request(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    early_timeout = get(TEST_REQUEST_EARLY_TIMEOUT_KEY)
    if mode=='contest'
      return false if (user.site!=nil) and
        ((user.site.started!=true) or
         (early_timeout and (user.site.time_left < 30.minutes)))
    end
    return false if mode=='analysis'
    return true
  end

  def self.task_grading_info
    if GraderConfiguration.task_grading_info_cache==nil
      read_grading_info
    end
    return GraderConfiguration.task_grading_info_cache
  end

  def self.standard_mode?
    return get(SYSTEM_MODE_CONF_KEY) == 'standard'
  end

  def self.contest_mode?
    return get(SYSTEM_MODE_CONF_KEY) == 'contest'
  end

  def self.indv_contest_mode?
    return get(SYSTEM_MODE_CONF_KEY) == 'indv-contest'
  end

  def self.multicontests?
    return get(MULTICONTESTS_KEY) == true
  end

  def self.time_limit_mode?
    mode = get(SYSTEM_MODE_CONF_KEY)
    return ((mode == 'contest') or (mode == 'indv-contest'))
  end

  def self.analysis_mode?
    return get(SYSTEM_MODE_CONF_KEY) == 'analysis'
  end

  def self.use_problem_group?
    return get(SYSTEM_USE_PROBLEM_GROUP)
  end

  def self.single_user_mode?
    return get(SINGLE_USER_KEY)
  end

  def self.contest_time_limit
    contest_time_str = GraderConfiguration[CONTEST_TIME_LIMIT_KEY]

    if not defined? GraderConfiguration.contest_time_str
      GraderConfiguration.contest_time_str = nil
    end

    if GraderConfiguration.contest_time_str != contest_time_str
      GraderConfiguration.contest_time_str = contest_time_str
      if tmatch = /(\d+):(\d+)/.match(contest_time_str)
        h = tmatch[1].to_i
        m = tmatch[2].to_i

        GraderConfiguration.contest_time = h.hour + m.minute
      else
        GraderConfiguration.contest_time = nil
      end
    end
    return GraderConfiguration.contest_time
  end

  def self.set_exam_mode(exam = true)
    value = exam ? 'false' : 'true'

    GraderConfiguration.where(key: "right.bypass_agreement").update(value: value)
    GraderConfiguration.where(key: "right.multiple_ip_login").update(value: value)
    GraderConfiguration.where(key: "right.user_hall_of_fame").update(value: value)
    GraderConfiguration.where(key: "right.user_view_submission").update(value: value)
    GraderConfiguration.where(key: "right.view_testcase").update(value: value)

    User.update_all(last_ip: false)
  end

  protected

  def self.convert_type(val, type)
    case type
    when 'string'
      return val

    when 'integer'
      return val.to_i

    when 'boolean'
      return (val=='true')
    end
  end

  def self.read_config
    @config_cache = {}
    # GraderConfiguration.config_cache = {}
    GraderConfiguration.all.each do |conf|
      key = conf.key
      val = conf.value
      # GraderConfiguration.config_cache[key] = GraderConfiguration.convert_type(val, conf.value_type)
      @config_cache[key] = GraderConfiguration.convert_type(val, conf.value_type)
    end
    return @config_cache
    # return GraderConfiguration.config_cache
  end

  # def self.read_one_key(key)
  #  conf = GraderConfiguration.find_by_key(key)
  #  if conf
  #    return GraderConfiguration.convert_type(conf.value,conf.value_type)
  #  else
  #    return nil
  #  end
  # end

  def self.read_grading_info
    f = File.open(TASK_GRADING_INFO_FILENAME)
    GraderConfiguration.task_grading_info_cache = YAML.load(f)
    f.close
  end
end
