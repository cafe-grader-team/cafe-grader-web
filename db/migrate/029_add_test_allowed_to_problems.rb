class AddTestAllowedToProblems < ActiveRecord::Migration
  def self.up
    add_column :problems, :test_allowed, :boolean
    Problem.reset_column_information

    Problem.all.each do |problem|
      problem.test_allowed = true
      problem.save
    end
  end

  def self.down
    remove_column :problems, :test_allowed
  end
end
