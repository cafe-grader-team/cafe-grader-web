class AddGroupToAnnouncement < ActiveRecord::Migration[7.0]
  def change
    add_reference :announcements, :group, null: true
  end
end
