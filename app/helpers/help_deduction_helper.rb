# Student-facing wording of the help-deduction rule (HelpDeduction, spec
# docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md).
module HelpDeductionHelper
  # The problem list's line. counted: the reduction that counts (capped);
  # raw: hints + AI help before the cap; cap: the cap that applied, or nil;
  # notice: shown uncapped although a contest of the student's sets a cap.
  def help_reduction_text(counted, raw, cap, notice)
    return nil unless counted.to_f.positive?

    if cap && raw.to_f > cap
      "Full score reduced by #{help_points(counted)} (capped; #{help_points(raw)} before the cap)"
    elsif notice
      "Full score reduced by #{help_points(counted)} (contest grading may cap this)"
    else
      "Full score reduced by #{help_points(counted)}"
    end
  end

  # The confirm boxes' block, markdown (rendered inside the boxes' :markdown
  # filter). budget: HelpDeduction::Budget; cost: this reveal's or request's
  # charge; kind: :hint or :ai. Empty for an AI request the requester does not
  # pay for (an admin asking on a student's behalf).
  def help_budget_text(budget, cost:, kind:)
    return '' if kind == :ai && cost.to_f.zero?

    noun = kind == :hint ? 'hint' : 'request'
    lines = []
    lines << "Contest `#{budget.contest_name}` caps hint and AI deductions at #{budget.cap} points per problem." if budget.cap
    lines << "Lost on this problem so far: #{help_points(budget.lost)} " \
             "(hints #{help_points(budget.hint_lost)}, AI help #{help_points(budget.ai_lost)})."
    if budget.at_cap?
      lines << 'You have reached the cap, so this costs you nothing more.'
    elsif budget.counts(cost) < cost.to_f
      more = budget.counts(cost)
      lines << "This #{noun} costs #{help_points(cost)}, but only #{help_points(more)} more counts " \
               "(#{help_points(budget.counted)} → #{help_points(budget.counted + more)})."
    end
    if kind == :ai
      lines << "AI help on this problem stops once you have spent #{budget.spending_limit} points; " \
               "you have spent #{help_points(budget.ai_spent)}."
    end
    lines.join("\n\n")
  end

  def help_points(value)
    number_with_precision(value.to_f, precision: 2, strip_insignificant_zeros: true)
  end
end
