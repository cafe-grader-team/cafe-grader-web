class AddOutsideLoginOffToContests < ActiveRecord::Migration[8.0]
  def change
    add_column :contests, :outside_login_off, :boolean, default: false, null: false
  end
end
