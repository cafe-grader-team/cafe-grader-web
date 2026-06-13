class Announcement < ApplicationRecord
  has_one_attached :file
  belongs_to :group, optional: true
  validates :title, presence: true

  scope :published, -> { where(published: true) }
  scope :frontpage, -> { published.where(frontpage: true) }
  scope :mainpage, -> { published.where(frontpage: false) }
  scope :default_order, -> { order(created_at: :desc) }
  scope :consider_contest, -> { GraderConfiguration.contest_mode? ? all : where(contest_only: false) }

  scope :viewable_by_user, ->(user) {
    return published.consider_contest.where(group: nil).or(where(group: user.groups_for_action(:submit)))
  }

  scope :editable_by_user, ->(user) {
    if user.admin?
      # admin can edit any announcement
      return all
    elsif user.groups_for_action(:edit).any?
      # for editor, can only edit announcements of their editable groups
      return where(group: user.groups_for_action(:edit)).or(where(group: nil))
    else
      return none
    end
  }
end
