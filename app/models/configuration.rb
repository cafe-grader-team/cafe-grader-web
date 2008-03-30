class Configuration < ActiveRecord::Base

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
