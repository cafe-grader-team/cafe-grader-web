class AddDeductionCapAndAssistSpendingLimitToContests < ActiveRecord::Migration[8.0]
  # Spec docs/superpowers/specs/2026-11-21-deduction-cap-spending-limit-design.md.
  # deduction_cap: the most hints + AI help can take off one problem's full
  # score in this contest (nil = no cap). assist_spending_limit: the most
  # points of AI help a student may spend on one problem before more requests
  # are refused (nil = the site setting system.llm_assist_spending_limit).
  def change
    add_column :contests, :deduction_cap, :integer
    add_column :contests, :assist_spending_limit, :integer
  end
end
