require 'test_helper'

# Issue #25: free-disk reporting. df is real here; the paths are what vary.
class GraderProcessDiskTest < ActiveSupport::TestCase
  test 'free_disk_mb measures an existing directory and returns nil for a missing one' do
    mb = GraderProcess.free_disk_mb(Rails.root)
    assert_kind_of Integer, mb
    assert_operator mb, :>, 0
    assert_nil GraderProcess.free_disk_mb('/no/such/dir/anywhere')
    assert_nil GraderProcess.free_disk_mb(nil)
  end

  test 'worker_free_disk_mb takes the smallest figure and ignores unmeasurable directories' do
    assert_equal GraderProcess.free_disk_mb(Rails.root), GraderProcess.worker_free_disk_mb([Rails.root, '/no/such/dir'])
    assert_nil GraderProcess.worker_free_disk_mb(['/no/such/dir'])
  end

  test 'disk_by_host keeps one row per host, the newest, sorted by free space' do
    GraderProcess.create!(worker_id: 1, box_id: 1, host: 'judge-a', disk_free_mb: 9000, last_heartbeat: 2.minutes.ago)
    GraderProcess.create!(worker_id: 1, box_id: 2, host: 'judge-a', disk_free_mb: 8000, last_heartbeat: 10.seconds.ago)
    GraderProcess.create!(worker_id: 2, box_id: 1, host: 'judge-b', disk_free_mb: 500, last_heartbeat: 5.seconds.ago)
    GraderProcess.create!(worker_id: 3, box_id: 1, host: 'judge-c', disk_free_mb: nil, last_heartbeat: 1.second.ago)
    rows = GraderProcess.disk_by_host
    assert_equal [['judge-b', 500], ['judge-a', 8000]], rows.map { |h, mb, _| [h, mb] }
    assert GraderProcess.low_disk?(500)
    assert_not GraderProcess.low_disk?(8000)
    assert_not GraderProcess.low_disk?(nil)
  end
end
