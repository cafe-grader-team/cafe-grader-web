class JobTypeEnable < ActiveRecord::Migration[7.0]
  def change
    add_column :problems, :permitted_lang, :string
    add_column :groups_users, :role, :integer, default: 0
    add_column :submissions, :cookie, :string
    add_column :logins, :cookie, :string
    rename_column :grader_processes, :task_type, :job_type
    add_index :submissions, :tag
  end
end
