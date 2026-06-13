class CreateContestsProblemsJoinTable < ActiveRecord::Migration[4.2]
  def self.up
    create_table :contests_problems, :id => false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.integer :contest_id
      t.integer :problem_id
    end
  end

  def self.down
    drop_table :contests_problems
  end
end
