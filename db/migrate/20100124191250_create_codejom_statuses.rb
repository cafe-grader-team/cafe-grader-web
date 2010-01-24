class CreateCodejomStatuses < ActiveRecord::Migration
  def self.up
    create_table :codejom_statuses do |t|
      t.integer :user_id
      t.boolean :alive
      t.integer :num_problems_passed

      t.timestamps
    end
  end

  def self.down
    drop_table :codejom_statuses
  end
end
