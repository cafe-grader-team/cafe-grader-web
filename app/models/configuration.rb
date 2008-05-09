#
# This class also contains various login of the system.
#
class Configuration < ActiveRecord::Base

  SYSTEM_MODE_CONF_KEY = 'system.mode'

  @@configurations = nil

  def self.get(key)
    if @@configurations == nil
      self.read_config
    end
    return @@configurations[key]
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

  def self.allow_test_request(user)
    mode = get(SYSTEM_MODE_CONF_KEY)
    if (mode=='contest') 
      return false if (user.site!=nil) and ((user.site.started!=true) or (user.site.time_left < 30.minutes))
    end
    return false if mode=='analysis'
    return true
  end

  protected
  def self.read_config
    @@configurations = {}
    Configuration.find(:all).each do |conf|
      key = conf.key
      val = conf.value
      case conf.value_type
      when 'string'
        @@configurations[key] = val

      when 'integer'
        @@configurations[key] = val.to_i

      when 'boolean'
        @@configurations[key] = (val=='true')
      end
    end
  end
  
end
