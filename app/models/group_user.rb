class GroupUser < ActiveRecord::Base
  self.table_name = 'groups_users'
  
  belongs_to :user
  belongs_to :group
  validates_uniqueness_of :user_id, scope: :group_id, message: ->(object, data) { "'#{User.find(data[:value]).full_name}' is already in the group" }
end
