module Auditable
  extend ActiveSupport::Concern

  IGNORED_ATTRS = %w[id created_at updated_at].freeze

  class_methods do
    # Usage:
    #   audited only: [:name, :available, ...], redact: [:description]
    # Omit `only:` to audit every attribute except id/timestamps.
    def audited(only: nil, redact: [])
      class_attribute :_audited_fields,   default: only&.map(&:to_s)
      class_attribute :_audited_redacted, default: redact.map(&:to_s)

      after_create_commit  -> { write_audit!("create") }
      after_update_commit  -> { write_audit!("update") }
      after_destroy_commit -> { write_audit!("destroy") }
    end
  end

  private

  def write_audit!(action)
    return if Current.audit_disabled
    return unless AuditLog.table_exists?
    diff = build_audit_diff(action)
    return if action == "update" && diff.empty?

    AuditLog.create!(
      user_id:        Current.user&.id,
      actor_note:     Current.actor_note,
      auditable_type: self.class.name,
      auditable_id:   id,
      action:         action,
      object_changes: diff,
      ip_address:     Current.ip
    )
  end

  def build_audit_diff(action)
    case action
    when "create", "update" then filter_saved_changes
    when "destroy"          then snapshot_on_destroy
    end
  end

  def filter_saved_changes
    tracked = _audited_fields || (attributes.keys - IGNORED_ATTRS)
    saved_changes.slice(*tracked).each_with_object({}) do |(field, (old, new)), h|
      if _audited_redacted.include?(field)
        h[field] = [AuditLog::REDACTED, AuditLog::REDACTED] if old != new
      else
        h[field] = [old, new]
      end
    end
  end

  def snapshot_on_destroy
    tracked = _audited_fields || (attributes.keys - IGNORED_ATTRS)
    tracked.each_with_object({}) do |field, h|
      val = attributes[field]
      val = AuditLog::REDACTED if _audited_redacted.include?(field) && val.present?
      h[field] = [val, nil]
    end
  end
end
