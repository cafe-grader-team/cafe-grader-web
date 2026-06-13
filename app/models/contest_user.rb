class ContestUser < ApplicationRecord
  include Auditable
  audited only: %i[contest_id user_id start_offset_second extra_time_second
                   remark seat enabled role]

  self.table_name = 'contests_users'
  belongs_to :contest
  belongs_to :user

  enum :role, {user: 0, editor: 2}

  #validates_uniqueness_of :user_id, scope: :contest_id, message: ->(object, data) { "'#{User.find(data[:value]).full_name}' is already in the contest" }
end
