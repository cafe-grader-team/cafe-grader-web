
module ConfigSpecHelperMethods

  def find_or_create_and_set_config(key, type, value)
    c = Configuration.find_by_key(key)
    c ||= Configuration.new(:key => key,
                            :value_type => type)
    c.value = value
    c.save!
  end

  def enable_multicontest
    find_or_create_and_set_config(Configuration::MULTICONTESTS_KEY,
                                  'boolean','true')
  end

  def disable_multicontest
    find_or_create_and_set_config(Configuration::MULTICONTESTS_KEY,
                                  'boolean','false')
  end

  def set_indv_contest_mode
    find_or_create_and_set_config(Configuration::SYSTEM_MODE_CONF_KEY,
                                  'string','indv-contest')
  end

  def set_standard_mode
    find_or_create_and_set_config(Configuration::SYSTEM_MODE_CONF_KEY,
                                  'string','standard')
  end

  def set_contest_time_limit(limit)
    find_or_create_and_set_config(Configuration::CONTEST_TIME_LIMIT_KEY,
                                  'string',limit)
    # clear old value
    Configuration.contest_time_str = nil
  end
end
