require 'yaml'

#
# This class also contains various login of the system.
#
class Configuration < ActiveRecord::Base

  SYSTEM_MODE_CONF_KEY = 'system.mode'
  TEST_REQUEST_EARLY_TIMEOUT_KEY = 'contest.test_request.early_timeout'
  MULTICONTESTS_KEY = 'system.multicontests'
  CONTEST_TIME_LIMIT_KEY = 'contest.time_limit'

  cattr_accessor :config_cache
  cattr_accessor :task_grading_info_cache
  cattr_accessor :contest_time_str
  cattr_accessor :contest_time

  Configuration.config_cache = nil
  Configuration.task_grading_info_cache = nil

  def self.get(key)
    if Configuration.config_cached?
      if Configuration.config_cache == nil
        self.read_config
      end
      return Configuration.config_cache[key]
    else
      return Configuration.read_one_key(key)
    end
  end

  def self.[](key)
    self.get(key)
  end

  def self.reload
    self.read_config
  end

  def self.clear
    Configuration.config_cache = nil
  end

  #
  # View decision
  #
  def self.show_submitbox_to?(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    return false if mode=='analysis'
    if (mode=='contest') 
      return false if (user.site!=nil) and 
        ((user.site.started!=true) or (user.site.finished?))
    end
    return true
  end

  def self.show_tasks_to?(user)
    if time_limit_mode?
      return false if not user.contest_started?
    end
    return true
  end

  def self.show_grading_result
    return (get(SYSTEM_MODE_CONF_KEY)=='analysis')
  end

  def self.allow_test_request(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    early_timeout = get(TEST_REQUEST_EARLY_TIMEOUT_KEY)
    if (mode=='contest') 
      return false if ((user.site!=nil) and 
        ((user.site.started!=true) or 
         (early_timeout and (user.site.time_left < 30.minutes))))
    end
    return false if mode=='analysis'
    return true
  end

  def self.task_grading_info
    if Configuration.task_grading_info_cache==nil
      read_grading_info
    end
    return Configuration.task_grading_info_cache
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
  
  def self.contest_time_limit
    contest_time_str = Configuration[CONTEST_TIME_LIMIT_KEY]

    if not defined? Configuration.contest_time_str
      Configuration.contest_time_str = nil
    end

    if Configuration.contest_time_str != contest_time_str
      Configuration.contest_time_str = contest_time_str
      if tmatch = /(\d+):(\d+)/.match(contest_time_str)
        h = tmatch[1].to_i
        m = tmatch[2].to_i
        
        Configuration.contest_time = h.hour + m.minute
      else
        Configuration.contest_time = nil
      end
    end  
    return Configuration.contest_time
  end

  protected

  def self.config_cached?
    (defined? CONFIGURATION_CACHE_ENABLED) and (CONFIGURATION_CACHE_ENABLED)
  end

  def self.convert_type(val,type)
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
    Configuration.config_cache = {}
    Configuration.find(:all).each do |conf|
      key = conf.key
      val = conf.value
      Configuration.config_cache[key] = Configuration.convert_type(val,conf.value_type)
    end
  end

  def self.read_one_key(key)
    conf = Configuration.find_by_key(key)
    if conf
      return Configuration.convert_type(conf.value,conf.value_type)
    else
      return nil
    end
  end

  def self.read_grading_info
    f = File.open(TASK_GRADING_INFO_FILENAME)
    Configuration.task_grading_info_cache = YAML.load(f)
    f.close
  end
  
end
