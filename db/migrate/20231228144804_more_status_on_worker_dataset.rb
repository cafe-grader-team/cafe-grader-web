class MoreStatusOnWorkerDataset < ActiveRecord::Migration[7.0]
  def change
    rename_column :worker_datasets, :status, :testcases_status
    add_column :worker_datasets, :managers_status, :integer, limit: 1, default: 0
    add_column :datasets, :initializer_filename, :string
  end
end
