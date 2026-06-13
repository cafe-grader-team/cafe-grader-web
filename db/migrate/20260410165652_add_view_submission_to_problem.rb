class AddViewSubmissionToProblem < ActiveRecord::Migration[8.0]
  def change
    add_column :problems, :view_submission, :boolean, default: true
  end
end
