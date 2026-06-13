class AddOnNavBarToAnnouncement < ActiveRecord::Migration[5.2]
  def change
    add_column :announcements, :on_nav_bar, :boolean, default: false
  end
end
