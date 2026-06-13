class AddMoreToContest < ActiveRecord::Migration[7.0]
  def change
    rename_column :contests, :name, :description
    rename_column :contests, :title, :name
    add_column :contests, :freeze, :bool, default: false
    add_column :contests, :remark, :text
    add_column :contests, :pre_contest_seconds, :integer, default: 0
    add_column :contests, :post_contest_seconds, :integer, default: 0
    add_column :contests, :log, :text

    remove_column :contests_users, :last_heartbeat, :datetime
  end
end
