class AddVivaDailyLimitRemoveVivaMode < ActiveRecord::Migration[8.0]
  def change
    # Context-based viva policy (2026-07-21 design, Phase A): the
    # practice/exam toggle is replaced by a numeric per-problem daily start
    # limit. nil -> site default (GraderConfiguration); 0 -> contest-only.
    add_column :problems, :viva_daily_limit, :integer

    remove_column :problems, :viva_mode, :integer, limit: 1, default: 0, null: false
  end
end
