class NewTestcaseSystem < ActiveRecord::Migration[7.0]
  def change
    create_table :datasets do |t|
      t.references :problem
      t.string  :name
      t.decimal :time_limit, default: 1, precision: 10, scale: 2
      t.integer :memory_limit
      t.integer :score_type, limit: 1, default: 0
      t.integer :evaluation_type, limit: 1, default: 0
      t.string  :score_param
      t.string  :main_filename
      t.timestamps
    end

    create_table :evaluations do |t|
      t.references :submission
      t.references :testcase
      t.integer :result
      t.integer :time
      t.integer :memory
      t.decimal :score, precision: 8, scale: 6 # from 0.xxxxxx to 1.xxxxxx, 6 decimal points
      t.string  :result_text
      t.string  :isolate_message
    end

    add_reference :testcases, :dataset
    add_column :testcases, :group_name, :string
    add_column :testcases, :code_name, :string

    add_reference :problems, :live_dataset
    add_column :problems, :submission_filename, :string
    add_column :problems, :task_type, :integer, limit: 1, default: 0
    add_column :problems, :compilation_type, :integer, limit: 1, default: 0

    add_column :submissions, :status, :integer, limit: 1, default: 0

    reversible do |dir|
      dir.up do
        change_column :submissions, :points, :decimal, precision: 8, scale: 4
      end
      dir.down do
        change_column :submissions, :points, :integer
      end
    end

  end
end
