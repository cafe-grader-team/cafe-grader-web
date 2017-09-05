class RefactorProblemBodyToDescription < ActiveRecord::Migration
  def self.up
    add_column :problems, :description_id, :integer
    Problem.reset_column_information
    
    Problem.all.each do |problem|
      if problem.body!=nil
        description = Description.new
        description.body = problem.body
        description.markdowned = false
        description.save
        problem.description_id = description.id
        problem.save
      end
    end
    
    remove_column :problems, :body
  end

  def self.down
    add_column :problems, :body, :text
    Problem.reset_column_information

    Problem.all.each do |problem|
      if problem.description_id != nil
        problem.body = Description.find(problem.description_id).body
        problem.save
      end
    end

    remove_column :problems, :description_id
  end
end
