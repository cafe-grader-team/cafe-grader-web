class SeedLlmAssistCostConfiguration < ActiveRecord::Migration[8.0]
  # Data migration. The assist price became a site setting in rev 2100 and
  # db/seeds.rb creates the key on a fresh install — but a deployed server only
  # runs db:migrate (the deploy job never seeds), so without this every existing
  # host would need a manual `bin/rails db:seed` to get the knob on the
  # Configuration page. Idempotent: a key an operator already created (by seed
  # or by hand) is left untouched, value included.
  KEY = 'system.llm_assist_cost'.freeze
  DESCRIPTION = "Score penalty, in points off the problem's full score, charged for each " \
                "LLM assist request. Read when the request is made and recorded on it, so " \
                "changing this never alters past charges. 0 makes assistance free.".freeze

  def up
    return if GraderConfiguration.exists?(key: KEY)

    ::Current.actor_note = "Migration: #{self.class.name}"
    GraderConfiguration.create!(key: KEY, value_type: 'integer', value: '10', description: DESCRIPTION)
  end

  def down
    # Leave the row: the code falls back to 10 when the key is absent, and an
    # operator may have changed the value. Nothing to undo.
  end
end
