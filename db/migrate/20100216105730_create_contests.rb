class CreateContests < ActiveRecord::Migration
  def self.up
    create_table :contests do |t|
      t.string :title
      t.boolean :enabled

      t.timestamps
    end
  end

  def self.down
    drop_table :contests
  end
end
