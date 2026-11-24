module Auditable
  extend ActiveSupport::Concern

  IGNORED_ATTRS = %w[id created_at updated_at].freeze

  class_methods do
    # Usage:
    #   audited only: [:name, :available, ...], redact: [:description]
    # Omit `only:` to audit every attribute except id/timestamps.
    #
    # Stage at save time, write at commit time. `saved_changes` describes only
    # the LAST save of a record and `reload` clears it, so reading it in the
    # commit callback lost the whole diff whenever anything happened between
    # the save and the commit — viva:import's post_check reloads every touched
    # problem inside its transaction, and on 2026-09-09 an APPLY run that
    # rewrote a live briefing left no audit row. Staging in after_save also
    # merges several saves of one record in one transaction into the single
    # row the commit writes (first old value, last new value; a field changed
    # and changed back is dropped), and a rollback discards what it staged.
    # A save made while AuditLog.paused stages nothing, so pausing works the
    # same inside or outside a transaction.
    def audited(only: nil, redact: [])
      class_attribute :_audited_fields,   default: only&.map(&:to_s)
      class_attribute :_audited_redacted, default: redact.map(&:to_s)

      after_save           :stage_audit_changes
      after_rollback       :discard_staged_audit_changes
      after_create_commit  -> { flush_staged_audit!("create") }
      after_update_commit  -> { flush_staged_audit!("update") }
      after_destroy_commit -> { write_audit!("destroy", snapshot_on_destroy) }
    end
  end

  private

  def audited_attribute_names
    _audited_fields || (attributes.keys - IGNORED_ATTRS)
  end

  def stage_audit_changes
    return if Current.audit_disabled
    @_audit_staged ||= {}
    saved_changes.slice(*audited_attribute_names).each do |field, (old, new)|
      first_old = @_audit_staged.key?(field) ? @_audit_staged[field].first : old
      @_audit_staged[field] = [first_old, new]
    end
  end

  def discard_staged_audit_changes
    @_audit_staged = nil
  end

  def flush_staged_audit!(action)
    staged = @_audit_staged
    @_audit_staged = nil
    return if staged.nil? || Current.audit_disabled
    diff = staged.each_with_object({}) do |(field, (old, new)), h|
      next if old == new
      h[field] = _audited_redacted.include?(field) ? [AuditLog::REDACTED, AuditLog::REDACTED] : [old, new]
    end
    return if action == "update" && diff.empty?
    write_audit!(action, diff)
  end

  def write_audit!(action, diff)
    return if Current.audit_disabled
    return unless AuditLog.table_exists?

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

  def snapshot_on_destroy
    audited_attribute_names.each_with_object({}) do |field, h|
      val = attributes[field]
      val = AuditLog::REDACTED if _audited_redacted.include?(field) && val.present?
      h[field] = [val, nil]
    end
  end
end
