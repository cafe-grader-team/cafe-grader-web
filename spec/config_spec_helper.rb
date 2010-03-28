
module ConfigSpecHelperMethods

  def find_or_create_and_set_config(key, type, value)
    c = Configuration.find_by_key(key)
    c ||= Configuration.new(:key => key,
                            :value_type => type)
    c.value = value
    c.save!
  end

  def enable_multicontest
    find_or_create_and_set_config('system.multicontests','boolean','true')
  end

  def disable_multicontest
    find_or_create_and_set_config('system.multicontests','boolean','false')
  end

end
