module AuditLogsHelper
  # Human-friendly label for the audit target. Falls back to Type #id when
  # the record (or parent association) has been destroyed.
  def audit_target_label(log)
    fallback = "#{log.auditable_type} ##{log.auditable_id}"
    case log.auditable_type
    when 'GraderConfiguration'
      key = grader_configuration_key(log)
      key.present? ? "GraderConfiguration: #{key}" : fallback
    when 'Contest'
      label_for(log, fallback) { |c| c.name }
    when 'Problem'
      label_for(log, fallback) { |p| p.name }
    when 'Dataset'
      label_for(log, fallback) { |d| "#{d.problem&.name} / #{d.name}" }
    when 'Testcase'
      label_for(log, fallback) { |t| "#{t.dataset&.problem&.name} / #{t.code_name.presence || "##{t.num}"}" }
    when 'ContestProblem'
      label_for(log, fallback) { |cp| "#{cp.contest&.name} / #{cp.problem&.name}" }
    when 'ContestUser'
      label_for(log, fallback) { |cu| "#{cu.contest&.name} / #{cu.user&.login}" }
    else
      fallback
    end
  end

  def audit_action_badge(action)
    case action
    when 'create'
      badge 'create',  'bg-success-subtle text-success-emphasis'
    when 'update'
      badge 'update',  'bg-primary-subtle text-primary-emphasis'
    when 'destroy'
      badge 'destroy', 'bg-danger-subtle text-danger-emphasis'
    when 'mode_change'
      icon_badge 'swap_horiz', 'mode change', 'bg-warning-subtle text-warning-emphasis'
    when 'clone'
      bulk_badge 'content_copy', 'clone'
    when 'bulk_add_users'
      bulk_badge 'group_add', 'bulk add users'
    when 'bulk_add_users_by_group'
      bulk_badge 'group_add', 'bulk add users (group)'
    when 'bulk_add_users_by_csv'
      bulk_badge 'group_add', 'bulk add users (csv)'
    when 'bulk_add_problems'
      bulk_badge 'library_add', 'bulk add problems'
    when 'bulk_add_problems_by_group'
      bulk_badge 'library_add', 'bulk add problems (group)'
    when 'import_testcases'
      bulk_badge 'upload_file', 'import testcases'
    when 'remove_user'
      bulk_badge 'person_remove', 'remove user'
    when 'remove_problem'
      bulk_badge 'library_books', 'remove problem'
    when 'move_up'
      bulk_badge 'arrow_upward', 'move up'
    when 'move_down'
      bulk_badge 'arrow_downward', 'move down'
    when 'bulk_enable_users'
      bulk_badge 'toggle_on', 'bulk enable users'
    when 'bulk_disable_users'
      bulk_badge 'toggle_off', 'bulk disable users'
    when 'bulk_remove_users'
      bulk_badge 'group_remove', 'bulk remove users'
    when 'bulk_clear_user_ips'
      bulk_badge 'lock_open', 'bulk clear user IPs'
    when 'bulk_enable_problems'
      bulk_badge 'toggle_on', 'bulk enable problems'
    when 'bulk_disable_problems'
      bulk_badge 'toggle_off', 'bulk disable problems'
    when 'bulk_remove_problems'
      bulk_badge 'remove_circle_outline', 'bulk remove problems'
    else
      badge action, 'bg-secondary-subtle text-secondary-emphasis'
    end
  end

  def grader_configuration_key(log)
    return log.auditable.key if log.auditable
    # Record destroyed — recover the key from the stored diff.
    changes = log.object_changes || {}
    changes.dig('key', 1) || changes.dig('key', 0)
  end

  private

  def label_for(log, fallback)
    record = log.auditable
    return fallback unless record
    detail = yield(record)
    detail.to_s.strip.present? ? "#{log.auditable_type}: #{detail}" : fallback
  end

  def badge(label, classes)
    content_tag :span, label, class: "badge #{classes}"
  end

  def icon_badge(icon, label, classes)
    content_tag :span, class: "badge #{classes} d-inline-flex align-items-center gap-1" do
      concat content_tag(:span, icon, class: 'mi md-18')
      concat label
    end
  end

  def bulk_badge(icon, label)
    icon_badge icon, label, 'bg-info-subtle text-info-emphasis'
  end
end
