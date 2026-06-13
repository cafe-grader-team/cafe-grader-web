class WorkerDataset < ApplicationRecord
  belongs_to :dataset
  #should belong to worker but we don't have the hosts table yet
  #belongs_to :worker

  enum :testcases_status, {created: 0, downloading: 1, ready: 3}, prefix: :ts
  enum :managers_status, {created: 0, downloading: 1, ready: 3}, prefix: :ms


end
