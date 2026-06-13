class ContestFinalize < ActiveRecord::Migration[7.0]
  def change
    rename_column :contests, :freeze, :finalized
    add_column :contests_users, :last_heartbeat, :datetime
    add_column :problems, :log, :text, limit: 4_000_000    #so that we get MEDIUMTEXT in mysql (3-byte lengths)
    add_column :evaluations, :output, :text, limit: 15000  #so that we get TEXT in mysql (2-byte lengths)
  end
end
