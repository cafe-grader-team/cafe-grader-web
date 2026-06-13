class AddTimeToContest < ActiveRecord::Migration[7.0]
  def change
    add_column :contests, :start, :datetime
    add_column :contests, :stop, :datetime
  end
end
