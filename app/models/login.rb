class Login < ApplicationRecord
  # Failed attempts (success: false) may not match any user; the attempted
  # login string is kept in attempted_login instead.
  belongs_to :user, optional: true

  scope :successful, -> { where(success: true) }
end
