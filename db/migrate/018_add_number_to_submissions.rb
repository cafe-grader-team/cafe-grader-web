class AddNumberToSubmissions < ActiveRecord::Migration
  def self.up
    add_column :submissions, :number, :integer

    # add number field for all records
    Submission.reset_column_information

    last_user_id = nil
    last_problem_id = nil
    current_number = 0

    Submission.order('user_id, problem_id, submitted_at').each do |submission|
      if submission.user_id==last_user_id and submission.problem_id==last_problem_id
        current_number += 1
      else
        current_number = 1
      end
      submission.number = current_number
      submission.save

      last_user_id = submission.user_id
      last_problem_id = submission.problem_id
    end

    add_index :submissions, [:user_id, :problem_id, :number], :unique => true
  end

  def self.down
    remove_index :submissions, :column => [:user_id, :problem_id, :number]
    remove_column :submissions, :number
  end
end
