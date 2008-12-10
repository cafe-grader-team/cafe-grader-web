require 'yaml'

#
# This class also contains various login of the system.
#
class Configuration < ActiveRecord::Base

  SYSTEM_MODE_CONF_KEY = 'system.mode'

  # set @@cache = true to only reload once.
  @@cache = false

  @@configurations = nil
  @@task_grading_info = nil

  def self.get(key)
    if @@cache
      if @@configurations == nil
        self.read_config
      end
      return @@configurations[key]
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
    @@configurations = nil
  end

  def self.enable_caching
    @@cache = true
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
    mode = get(SYSTEM_MODE_CONF_KEY)
    if (mode=='contest') 
      return false if (user.site!=nil) and (user.site.started!=true)
    end
    return true
  end

  def self.show_grading_result
    return (get(SYSTEM_MODE_CONF_KEY)=='analysis')
  end

  def self.allow_test_request(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    if (mode=='contest') 
      return false if (user.site!=nil) and ((user.site.started!=true) or (user.site.time_left < 30.minutes))
    end
    return false if mode=='analysis'
    return true
  end

  def self.task_grading_info
    if @@task_grading_info==nil
      read_grading_info
    end
    return @@task_grading_info
  end
  
  protected

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
    @@configurations = {}
    Configuration.find(:all).each do |conf|
      key = conf.key
      val = conf.value
      @@configurations[key] = Configuration.convert_type(val,conf.value_type)
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
    @@task_grading_info = YAML.load(f)
    f.close
  end
  
end
