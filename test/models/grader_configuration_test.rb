require "test_helper"

class GraderConfigurationTest < ActiveSupport::TestCase
  # --- Config access ---

  test "get returns config value" do
    val = GraderConfiguration.get("ui.front.title")
    assert_equal "Grader", val
  end

  test "bracket accessor works like get" do
    assert_equal GraderConfiguration.get("ui.front.title"), GraderConfiguration["ui.front.title"]
  end

  test "get returns nil for non-existent key" do
    assert_nil GraderConfiguration.get("nonexistent.key")
  end

  test "get returns boolean for boolean type" do
    val = GraderConfiguration.get("system.single_user_mode")
    assert_equal false, val
  end

  # --- Mode queries ---

  test "standard_mode? returns true when mode is standard" do
    assert GraderConfiguration.standard_mode?
  end

  test "contest_mode? returns false in standard mode" do
    assert_not GraderConfiguration.contest_mode?
  end

  test "contest_mode? returns true when set" do
    set_grader_config("system.mode", "contest")
    assert GraderConfiguration.contest_mode?
  end

  test "indv_contest_mode? returns true when set" do
    set_grader_config("system.mode", "indv-contest")
    assert GraderConfiguration.indv_contest_mode?
  end

  test "analysis_mode? returns true when set" do
    set_grader_config("system.mode", "analysis")
    assert GraderConfiguration.analysis_mode?
  end

  test "time_limit_mode? returns true for contest and indv-contest" do
    set_grader_config("system.mode", "contest")
    assert GraderConfiguration.time_limit_mode?

    set_grader_config("system.mode", "indv-contest")
    assert GraderConfiguration.time_limit_mode?
  end

  # --- Boolean configs ---

  test "single_user_mode? defaults to false" do
    assert_not GraderConfiguration.single_user_mode?
  end

  test "multicontests? defaults to false" do
    assert_not GraderConfiguration.multicontests?
  end

  test "use_problem_group? defaults to false" do
    assert_not GraderConfiguration.use_problem_group?
  end

  # --- IP whitelist ---

  test "whitelisted_ip? accepts any IP while whitelist_ignore is on" do
    assert GraderConfiguration.whitelisted_ip?("203.0.113.5")
  end

  test "whitelisted_ip? matches CIDR ranges and exact IPs" do
    set_grader_config("right.whitelist_ignore", "false")
    set_grader_config("right.whitelist_ip", "10.0.0.0/8, 192.168.1.5")
    assert GraderConfiguration.whitelisted_ip?("10.31.4.7")
    assert GraderConfiguration.whitelisted_ip?("192.168.1.5")
    assert_not GraderConfiguration.whitelisted_ip?("192.168.1.6")
    assert_not GraderConfiguration.whitelisted_ip?("203.0.113.5")
  end

  test "whitelisted_ip? rejects everything when the active whitelist is blank" do
    set_grader_config("right.whitelist_ignore", "false")
    set_grader_config("right.whitelist_ip", "")
    assert_not GraderConfiguration.whitelisted_ip?("127.0.0.1")
  end

  # --- set_exam_mode ---

  test "set_exam_mode updates multiple configs" do
    GraderConfiguration.set_exam_mode(true)
    reset_grader_config_cache
    assert_not GraderConfiguration["right.bypass_agreement"]
    assert_not GraderConfiguration["right.multiple_ip_login"]
  end
end
