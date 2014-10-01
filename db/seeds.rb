CONFIGURATIONS = 
  [
   { 
     :key => 'system.single_user_mode',
     :value_type => 'boolean',
     :default_value => 'false',
     :description => 'Only admins can log in to the system when running under single user mode.'
   },

   { 
     :key => 'ui.front.title',
     :value_type => 'string',
     :default_value => 'Grader' 
   },

   { 
     :key => 'ui.front.welcome_message',
     :value_type => 'string',
     :default_value => 'Welcome!' 
   },

   { 
     :key => 'ui.show_score',
     :value_type => 'boolean',
     :default_value => 'true' 
   },

   { 
     :key => 'contest.time_limit',
     :value_type => 'string',
     :default_value => 'unlimited',
     :description => 'Time limit in format hh:mm, or "unlimited" for contests with no time limits.  This config is CACHED.  Restart the server before the change can take effect.'
   },

   { 
     :key => 'system.mode',
     :value_type => 'string',
     :default_value => 'standard',
     :description => 'Current modes are "standard", "contest", "indv-contest", and "analysis".'
   },

   { 
     :key => 'contest.name',
     :value_type => 'string',
     :default_value => 'Grader',
     :description => 'This name will be shown on the user header bar.'
   },

   {
     :key => 'contest.multisites',
     :value_type => 'boolean',
     :default_value => 'false',
     :description => 'If the server is in contest mode and this option is true, on the log in of the admin a menu for site selections is shown.'
   },

   {
     :key => 'right.user_hall_of_fame',
     :value_type => 'boolean',
     :default_value => 'false',
     :description => 'If true, any user can access hall of fame page.'
   },

   {
     :key => 'right.user_view_submission',
     :value_type => 'boolean',
     :default_value => 'false',
     :description => 'If true, any user can view submissions of every one.'
   },

   # If Configuration['system.online_registration'] is true, the
   # system allows online registration, and will use these
   # information for sending confirmation emails.
   {
     :key => 'system.online_registration.smtp',
     :value_type => 'string',
     :default_value => 'smtp.somehost.com' 
   },

   {
     :key => 'system.online_registration.from',
     :value_type => 'string',
     :default_value => 'your.email@address'
   },

   {
     :key => 'system.admin_email',
     :value_type => 'string',
     :default_value => 'admin@admin.email'
   },

   { 
     :key => 'system.user_setting_enabled',
     :value_type => 'boolean',
     :default_value => 'true',
     :description => 'If this option is true, users can change their settings'
   },

   {
     :key => 'system.user_setting_enabled',
     :value_type => 'boolean',
     :default_value => 'true',
     :description => 'If this option is true, users can change their settings'
   },

   # If Configuration['contest.test_request.early_timeout'] is true
   # the user will not be able to use test request at 30 minutes
   # before the contest ends.
   {
     :key => 'contest.test_request.early_timeout',
     :value_type => 'boolean',
     :default_value => 'false'
   },

   {
     :key => 'system.multicontests',
     :value_type => 'boolean',
     :default_value => 'false'
   },

   {
     :key => 'contest.confirm_indv_contest_start',
     :value_type => 'boolean',
     :default_value => 'false'
   },

   {
     :key => 'contest.default_contest_name',
     :value_type => 'string',
     :default_value => 'none',
     :description => "New user will be assigned to this contest automatically, if it exists.  Set to 'none' if there is no default contest."
   }

  ]


def create_configuration_key(key, 
                             value_type, 
                             default_value, 
                             description='')
  conf = (GraderConfiguration.find_by_key(key) || 
          GraderConfiguration.new(:key => key,
                            :value_type => value_type,
                            :value => default_value))
  conf.description = description
  conf.save
end

def seed_config
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
end

def seed_roles
  return if Role.find_by_name('admin')

  role = Role.create(:name => 'admin')
  user_admin_right = Right.create(:name => 'user_admin',
                                  :controller => 'user_admin',
                                  :action => 'all')
  problem_admin_right = Right.create(:name=> 'problem_admin',
                                     :controller => 'problems',
                                     :action => 'all')

  graders_right = Right.create(:name => 'graders_admin',
                               :controller => 'graders',
                               :action => 'all')
    
  role.rights << user_admin_right;
  role.rights << problem_admin_right;
  role.rights << graders_right;
  role.save
end

def seed_root
  return if User.find_by_login('root')
  
  root = User.new(:login => 'root',
                  :full_name => 'Administrator',
                  :alias => 'root')
  root.password = 'ioionrails';
  
  class << root
    public :encrypt_new_password
    def valid?(context=nil)
      true
    end
  end

  root.encrypt_new_password

  root.roles << Role.find_by_name('admin')

  root.activated = true
  root.save
end

def seed_users_and_roles
  seed_roles
  seed_root
end

def seed_more_languages
  Language.delete_all
  Language.create( name: 'c', pretty_name: 'C', ext: 'c', common_ext: 'c' )
  Language.create( name: 'cpp', pretty_name: 'C++', ext: 'cpp', common_ext: 'cpp,cc' )
  Language.create( name: 'pas', pretty_name: 'Pascal', ext: 'pas', common_ext: 'pas' )
  Language.create( name: 'ruby', pretty_name: 'Ruby', ext: 'rb', common_ext: 'rb' )
  Language.create( name: 'python', pretty_name: 'Python', ext: 'py', common_ext: 'py' )
  Language.create( name: 'java', pretty_name: 'Java', ext: 'java', common_ext: 'java' )
end

seed_config
seed_users_and_roles
seed_more_languages
