class SeedLoginThrottleExemptIpsConfiguration < ActiveRecord::Migration[8.0]
  # Data migration, same reason as SeedLlmAssistCostConfiguration: a deployed
  # server only runs db:migrate, so without this the new setting would never
  # appear on the Configuration page of an existing host. Created empty (no
  # address exempt — the old behaviour); the operator lists the exam gateway.
  # Idempotent: a key already present is left untouched, value included.
  KEY = 'right.login_throttle_exempt_ips'.freeze
  DESCRIPTION = "Addresses that skip the per-address count of failed logins (comma-separated " \
                "addresses or CIDR ranges, e.g. '10.0.5.40, 10.0.5.41'). List an exam gateway " \
                "that puts a whole room behind one address, so a few minutes of mistyped " \
                "passwords cannot lock the room out. Each account still locks after too many " \
                "failures.".freeze

  def up
    return if GraderConfiguration.exists?(key: KEY)

    ::Current.actor_note = "Migration: #{self.class.name}"
    GraderConfiguration.create!(key: KEY, value_type: 'string', value: '', description: DESCRIPTION)
  end

  def down
    # Leave the row: a missing key and an empty one both mean "none exempt",
    # and an operator may have filled it in. Nothing to undo.
  end
end
