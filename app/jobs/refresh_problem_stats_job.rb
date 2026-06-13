class RefreshProblemStatsJob < ApplicationJob
  queue_as :default

  def perform
    ProblemStat.recompute_all
  end
end
