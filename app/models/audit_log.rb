class AuditLog < ApplicationRecord
  REDACTED = "[redacted]".freeze

  belongs_to :user, optional: true
  # Audit rows must outlive their target — the whole point of a destroy entry
  # is that the auditable record is gone. With the Rails default (required),
  # after_destroy_commit -> AuditLog.create! fails "Auditable must exist".
  belongs_to :auditable, polymorphic: true, optional: true

  alias_attribute :diff, :object_changes

  scope :recent,   -> { order(created_at: :desc) }
  scope :for,      ->(record) { where(auditable: record) }
  scope :by_user,  ->(user)   { where(user: user) }

  def self.cleanup!(older_than: 6.months.ago)
    where("created_at < ?", older_than).delete_all
  end

  # Suppress auto-logging from the Auditable concern within the block.
  # Restores the previous state even on exception. Nest safely.
  def self.paused
    previous = Current.audit_disabled
    Current.audit_disabled = true
    yield
  ensure
    Current.audit_disabled = previous
  end

  # Write a manual, high-level entry. Use together with `paused` to replace
  # a cascade of auto-logs with a single semantic record.
  def self.record!(auditable:, action:, object_changes: nil, actor_note: nil)
    create!(
      user_id:        Current.user&.id,
      actor_note:     actor_note || Current.actor_note,
      auditable_type: auditable.class.name,
      auditable_id:   auditable.id,
      action:         action.to_s,
      object_changes: object_changes,
      ip_address:     Current.ip
    )
  end
end
