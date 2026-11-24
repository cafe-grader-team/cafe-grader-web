class SeedLlmAssistSpendingLimitConfiguration < ActiveRecord::Migration[8.0]
  # Data migration, same reason as SeedLlmAssistCostConfiguration: a deployed
  # server only runs db:migrate, so without this the new setting would never
  # appear on the Configuration page of an existing host. Created at 100, the
  # constant it replaces. Idempotent: a key already present is left
  # untouched, value included.
  KEY = 'system.llm_assist_spending_limit'.freeze
  DESCRIPTION = "The most points of AI help a student can spend on one problem before further " \
                "requests are refused (hints are not counted). A contest can set its own.".freeze

  def up
    return if GraderConfiguration.exists?(key: KEY)

    ::Current.actor_note = "Migration: #{self.class.name}"
    GraderConfiguration.create!(key: KEY, value_type: 'integer', value: '100', description: DESCRIPTION)
  end

  def down
    # Leave the row: the code falls back to 100 when the key is absent, and an
    # operator may have changed the value. Nothing to undo.
  end
end
