class AddTimestampsToGroups < ActiveRecord::Migration[8.0]
  def change
    # Groups created before this migration have no creation record anywhere
    # (groups_users / groups_problems carry no timestamps and Group is not
    # audited), so the columns stay nullable and existing rows are left blank
    # rather than stamped with an invented date. Rails fills both on new rows;
    # the groups index shows created_at and sorts on it, newest first.
    add_timestamps :groups, null: true
  end
end
