class AddVivaPhase1Fields < ActiveRecord::Migration[8.0]
  def change
    add_column :problems, :viva_mode, :integer, limit: 1, default: 0, null: false
    add_column :problems, :viva_prompt, :text, size: :medium
    add_column :problems, :viva_soft_cap, :integer, default: 10, null: false
    add_column :problems, :viva_hard_cap, :integer, default: 15, null: false
    add_column :viva_turns, :alerted, :boolean, default: false, null: false
  end
end
