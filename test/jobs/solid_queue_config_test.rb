require "test_helper"

# Every queue a job can land in must have a worker. From 2026-09-17 until
# 4.7.3 nothing served `solid_queue_recurring` — where Solid Queue puts every
# `command:` task of config/recurring.yml — so the nightly cleanup, the viva
# failsafe and reaper, and the job reclaim silently never ran on any host
# (about 9,550 unrun requests per host when found on 2026-10-08).
class SolidQueueConfigTest < ActiveSupport::TestCase
  def config(file)
    YAML.safe_load(ERB.new(Rails.root.join("config", file).read).result, aliases: true)["production"]
  end

  def worker_queues
    config("queue.yml")["workers"].map { |w| Array(w["queues"]).map { |q| q.to_s.strip } }
  end

  def served?(queue)
    worker_queues.any? { |qs| qs.include?("*") || qs.include?(queue) }
  end

  test "the viva worker serves only viva and the other worker serves every queue" do
    assert_includes worker_queues, ["viva"], "interview turns keep a worker no other job can occupy"
    assert_includes worker_queues, ["*"], "the default worker must serve every queue, scheduled tasks included"
  end

  test "every scheduled task and every job class lands in a queue some worker serves" do
    tasks = config("recurring.yml")
    queues = tasks.map do |key, task|
      task["queue"] || (task["command"] ? "solid_queue_recurring" : task["class"].constantize.queue_name)
    end
    Rails.application.eager_load!
    queues += ApplicationJob.descendants.map(&:queue_name)

    queues.uniq.each { |q| assert served?(q), "no worker serves queue #{q.inspect}" }
  end

  test "scheduled tasks live in recurring.yml, which is the only place Solid Queue reads them from" do
    assert_nil config("queue.yml")["recurring"], "Solid Queue never reads a recurring: key in queue.yml"
    assert_equal "RefreshProblemStatsJob", config("recurring.yml").dig("refresh_problem_stats", "class")
  end
end
