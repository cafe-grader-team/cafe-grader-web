class CreateJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :jobs do |t|
      t.integer :status, limit: 1, default: 0
      t.integer :grader_process_id
      t.integer :job_type
      t.integer :arg
      t.string :param
      t.string :result
      t.references :parent_job
      t.datetime :finished

      t.timestamps
    end
  end
end
