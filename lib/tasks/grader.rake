namespace :cafe do
  task :migrate_to_2023 do
    puts "start migrating to 2023"
    Dataset.migrate_old_testcases
    puts "Migrate testcase done..."
  end

  task :restart do
    desc 'Stop any running graders of this worker machine and restart 4 graders'

    Grader.make_enabled(0)
    Grader.watchdog
    sleep(1)
    puts '-------------'
    Grader.make_enabled(4)
    Grader.watchdog
  end

  task setup_chula: :environment do
    desc 'Setup authentication for cu.net'

    conf = GraderConfiguration.find_or_create_by(key: 'chula.allow_cu_net_password')
    conf.description = 'Allow users to use Chula password to login'
    conf.value_type = 'boolean'
    conf.value = 'true'

    conf.save
    puts "Setting up chula.allow_cu_net_password config"
    puts "You must set the api key for cucas in credentials.yml.enc"
    puts "(see credentials.yml.SAMPLE)"
  end
end
