
def create_configuration_key(key, 
                             value_type, 
                             default_value, 
                             description='')
  conf = (Configuration.find_by_key(key) || 
          Configuration.new(:key => key,
                            :value_type => value_type,
                            :value => default_value))
  conf.description = description
  conf.save
end

CONFIGURATIONS = 
  [
   { 
     :key => 'system.single_user_mode',
     :value_type => 'boolean',
     :value => 'false',
     :description => 'Only admins can log in to the system when running under single user mode.'
   },

   { 
     :key => 'ui.front.title',
     :value_type => 'string',
     :value => 'Grader' 
   },

   { 
     :key => 'ui.front.welcome_message',
     :value_type => 'string',
     :value => 'Welcome!' 
   },

   { 
     :key => 'ui.show_score',
     :value_type => 'boolean',
     :value => 'true' 
   },
   
   { 
     :key => 'contest.time_limit',
     :value_type => 'string',
     :value => 'unlimited',
     :description => 'Time limit in format hh:mm, or "unlimited" for contests with no time limits.'
   },

   { 
     :key => 'system.mode',
     :value_type => 'string',
     :value => 'standard',
     :description => 'Current modes are "standard", "contest", "indv-contest", and "analysis".'
   },

   { 
     :key => 'contest.name',
     :value_type => 'string',
     :value => 'Grader',
     :description => 'This name will be shown on the user header bar.'
   },

   {
     :key => 'contest.multisites',
     :value_type => 'boolean',
     :value => 'false',
     :description => 'If the server is in contest mode and this option is true, on the log in of the admin a menu for site selections is shown.'
   },

   {
     :key => 'system.online_registration',
     :value_type => 'boolean',
     :value => 'false',
     :description => 'This option enables online registration.'
   },

   # If Configuration['system.online_registration'] is true, the
   # system allows online registration, and will use these
   # information for sending confirmation emails.
   {
     :key => 'system.online_registration.smtp',
     :value_type => 'string',
     :value => 'smtp.somehost.com' 
   },

   {
     :key => 'system.online_registration.from',
     :value_type => 'string',
     :value => 'your.email@address'
   },

   {
     :key => 'system.admin_email',
     :value_type => 'string',
     :value => 'admin@admin.email'
   },
   
   { 
     :key => 'system.user_setting_enabled',
     :value_type => 'boolean',
     :value => 'true',
     :description => 'If this option is true, users can change their settings'
   },
   
   # If Configuration['contest.test_request.early_timeout'] is true
   # the user will not be able to use test request at 30 minutes
   # before the contest ends.
   {
     :key => 'contest.test_request.early_timeout',
     :value_type => 'boolean',
     :value => 'false'
   }
  ]

CONFIGURATIONS.each do |conf|
  if conf.has_key? :description
    desc = conf[:description]
  else
    desc = ''
  end
  create_configuration_key(conf[:key], 
                           conf[:value_type],
                           conf[:default_value],
                           desc)
end
