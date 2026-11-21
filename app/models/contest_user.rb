class ContestUser < ApplicationRecord
  include Auditable
  audited only: %i[contest_id user_id start_offset_second extra_time_second
                   remark seat enabled role]

  self.table_name = 'contests_users'
  belongs_to :contest
  belongs_to :user

  enum :role, {user: 0, editor: 2}

  # Whole seconds, never negative. allow_nil only so a legacy NULL row can still
  # be enabled/disabled; the extra-time dialog saves a blank as 0, and every
  # window query reads NULL as 0.
  validates :start_offset_second, :extra_time_second,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Student rows of contests with the outside login turned off, still inside
  # stop + that row's extra time. Ignores both `enabled` flags on purpose.
  scope :blocking_outside_login, ->(now = Time.zone.now) {
    user.joins(:contest)
        .where(contests: { outside_login_off: true })
        .where('DATE_ADD(contests.stop, INTERVAL IFNULL(contests_users.extra_time_second, 0) SECOND) > ?', now)
  }

  #validates_uniqueness_of :user_id, scope: :contest_id, message: ->(object, data) { "'#{User.find(data[:value]).full_name}' is already in the contest" }
end
