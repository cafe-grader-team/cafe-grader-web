class Group < ApplicationRecord
  # need pluralize helper function
  delegate :pluralize, to: 'ActionController::Base.helpers'

  has_many :groups_problems, class_name: 'GroupProblem', dependent: :destroy
  has_many :problems, through: :groups_problems

  has_many :groups_users, class_name: 'GroupUser', dependent: :destroy
  has_many :users, through: :groups_users

  scope :editable_by_user, ->(user_id) {
    joins(:groups_users).where(groups_users: { user_id: user_id, enabled: true, role: 'editor' })
  }

  scope :reportable_by_user, ->(user_id) {
    joins(:groups_users).where(groups_users: { user_id: user_id, enabled: true, role: ['editor', 'reporter'] })
  }

  scope :submittable_by_user, ->(user_id) {
    joins(:groups_users).where(groups_users: { user_id: user_id, enabled: true })
  }

  scope :enabled, -> { where(enabled: true) }

  # validates the name, (also using custom validator)
  validates :name, presence: true, uniqueness: true, name_format: true


  # has_and_belongs_to_many :problems
  # has_and_belongs_to_many :users

  def add_users_skip_existing(new_users)
    # new_list = []
    # users_list.uniq.each do |u|
    #  new_list << u unless users.include? u
    # end
    # users << new_list

    return {title: 'Group users are NOT changed', body: 'No new users given.'} if new_users.count == 0

    # remove already existing users
    to_be_added = new_users.where.not(id: self.users)
    num_actual_add = to_be_added.count
    num_request_add = new_users.count

    self.users << to_be_added
    if num_actual_add == 0
      return {title: 'Group users are NOT changed', body: 'All users given are already in the group.'}
    elsif num_actual_add == num_request_add
      return {title: 'Group users changed', body: "All given #{pluralize num_actual_add, 'user'} were added to the group."}
    else
      return {title: 'Group users changed',
              body: %Q(
                From given #{pluralize num_request_add, 'user'},
                #{pluralize num_actual_add, 'user'} were added to the group
                while the other #{pluralize (num_request_add - num_actual_add), 'user'} are already in the group.
              )}
    end
  end
end
