# View helpers for the Near-Miss run browser. Badge shape mirrors
# AuditLogsHelper (bg-<color>-subtle + text-<color>-emphasis).
module NearMissRunsHelper
  # Display order for status rollups: outcomes first, transient states last.
  STATUS_ORDER = %w[accepted over_budget no_change failed processing pending].freeze

  # Covers both SubmissionRepair#status and the per-round gate outcomes
  # stored in rounds_log ('unparseable', 'unfixable').
  STATUS_BADGES = {
    'accepted'    => ['check_circle',   'bg-success-subtle text-success-emphasis'],
    'over_budget' => ['straighten',     'bg-warning-subtle text-warning-emphasis'],
    'no_change'   => ['block',          'bg-light text-secondary border'],
    'failed'      => ['error',          'bg-danger-subtle text-danger-emphasis'],
    'processing'  => ['autorenew',      'bg-info-subtle text-info-emphasis'],
    'pending'     => ['schedule',       'bg-secondary-subtle text-secondary-emphasis'],
    'unparseable' => ['broken_image',   'bg-danger-subtle text-danger-emphasis'],
    'unfixable'   => ['do_not_disturb', 'bg-light text-secondary border'],
    'truncated'   => ['content_cut',    'bg-danger-subtle text-danger-emphasis'],
    # Not an attempt status: accepted attempts whose shadow has no real judge
    # outcome (grader_error / still in flight) — excluded from gap stats.
    'ungradeable' => ['report_off',     'bg-danger-subtle text-danger-emphasis']
  }.freeze

  # Badge for an attempt status / round gate outcome; count: prefixes the
  # label with a number for the outcome-rollup cells ("12 accepted").
  def near_miss_status_badge(status, count: nil)
    icon, classes = STATUS_BADGES.fetch(status.to_s, ['help', 'bg-secondary-subtle text-secondary-emphasis'])
    label = status.to_s.humanize.downcase
    label = "#{count} #{label}" if count
    content_tag :span, class: "badge d-inline-flex align-items-center gap-1 #{classes}" do
      content_tag(:span, icon, class: 'mi md-18') + label
    end
  end

  def near_miss_category_badge(label)
    return if label.blank?
    content_tag :span, label, class: 'badge bg-primary-subtle text-primary-emphasis'
  end

  # Mechanical gap (repaired − original) colour-coded: green = rescue, red =
  # the repair made things worse (the safety signal from the Genie batch),
  # muted = not accepted / no real judge outcome yet. Gated on shadow_graded?
  # — a grader_error shadow's points column reads 0, which would otherwise
  # paint a fake red gap for what is an infrastructure failure.
  def near_miss_gap(repair)
    orig = repair.original_submission&.points
    rep  = repair.repaired_submission&.points
    return content_tag(:span, '—', class: 'text-secondary') unless repair.shadow_graded? && orig && rep
    gap = rep.to_f - orig.to_f
    if gap.positive?
      content_tag :span, "+#{near_miss_points(gap)}", class: 'text-success fw-semibold'
    elsif gap.negative?
      content_tag :span, "−#{near_miss_points(gap.abs)}", class: 'text-danger fw-semibold'
    else
      content_tag :span, '0', class: 'text-secondary'
    end
  end

  # submissions.points is decimal(16,6) — show integers without ".0".
  def near_miss_points(value)
    return '—' if value.nil?
    f = value.to_f
    f == f.to_i ? f.to_i.to_s : format('%.2f', f)
  end

  # "40/100", raw_sum-aware (mirrors submissions/show); nil-safe for
  # not-yet-graded shadows.
  def near_miss_score(submission)
    return '—' if submission.nil? || submission.points.nil?
    points = near_miss_points(submission.points)
    submission.problem&.live_dataset&.st_raw_sum? ? points : "#{points}/100"
  end

  # Colour a stored Gate patch. Custom format (SubmissionRepair::Gate):
  # "@N" position-marker lines with -old / +new lines — no unified-diff
  # file headers, so the prefix test is unambiguous.
  def near_miss_patch(patch)
    spans = patch.to_s.split("\n").map do |line|
      classes =
        if line.start_with?('@')
          'd-block text-secondary'
        elsif line.start_with?('+')
          'd-block bg-success-subtle'
        elsif line.start_with?('-')
          'd-block bg-danger-subtle'
        else
          'd-block'
        end
      content_tag(:span, line, class: classes)
    end
    safe_join(spans)
  end

  # "2026-07-31 16:12 → 17:40", compressed when the run stayed inside one
  # day / one minute. Raw pluck values arrive as UTC — convert for display.
  def near_miss_activity_range(first_at, last_at)
    first_at = first_at.in_time_zone
    last_at  = last_at&.in_time_zone
    first_s  = first_at.strftime('%Y-%m-%d %H:%M')
    return first_s if last_at.nil? || last_at.to_i / 60 == first_at.to_i / 60
    last_s = first_at.to_date == last_at.to_date ? last_at.strftime('%H:%M') : last_at.strftime('%Y-%m-%d %H:%M')
    "#{first_s} → #{last_s}"
  end
end
