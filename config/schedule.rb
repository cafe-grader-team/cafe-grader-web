# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

# Grader.watchdog stays in cron deliberately. It supervises the judge
# worker processes; putting it inside Solid Queue would mean it dies
# when Solid Queue itself crashes — exactly the failure mode the
# watchdog exists to recover from. Keep this entry here.
every 1.minute do
  runner "Grader.watchdog"
end

# The two cleanup_* tasks moved to config/recurring.yml so they live
# next to AuditLog.cleanup! and viva_turn_failsafe.
#
# Deploy propagation is handled by the CI/CD pipeline
# (gitlab.nattee.net/nattee/cafe-grader-automation), which runs:
#   bundle exec whenever --update-crontab     # rewrites crontab from this file
#   sudo -n systemctl restart solid_queue.service  # reloads recurring.yml
# on every server. The systemctl line relies on a NOPASSWD sudoers
# drop-in — see provision/sudoers.d/README.md in the automation repo.
