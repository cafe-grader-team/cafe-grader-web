class AddMoreDetailToSubmission < ActiveRecord::Migration
  def change
    add_column :submissions, :max_runtime, :float
    add_column :submissions, :peak_memory, :integer
    add_column :submissions, :effective_code_length, :integer
  end
end
