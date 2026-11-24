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

  # The seed default is "0.0.0.0/0, ::/0" for this reason: IPv4 0.0.0.0/0
  # never matches an IPv6 address, and about a quarter of cp-grader's logins
  # (2026) arrive over IPv6.
  test "whitelisted_ip? needs ::/0 beside 0.0.0.0/0 to let every address in" do
    set_grader_config("right.whitelist_ignore", "false")
    set_grader_config("right.whitelist_ip", "0.0.0.0/0")
    assert GraderConfiguration.whitelisted_ip?("203.0.113.5")
    assert_not GraderConfiguration.whitelisted_ip?("2001:db8::5")

    set_grader_config("right.whitelist_ip", "0.0.0.0/0, ::/0")
    assert GraderConfiguration.whitelisted_ip?("203.0.113.5")
    assert GraderConfiguration.whitelisted_ip?("2001:db8::5")
  end

  # --- Login throttle exempt list ---

  test "login_throttle_exempt_ips_warnings is empty for a blank or well-formed list" do
    [nil, "", "  ", "10.0.5.40", "10.0.5.40, 10.0.5.41 192.0.2.0/24", "2001:db8::/32"].each do |value|
      assert_equal [], GraderConfiguration.login_throttle_exempt_ips_warnings(value), value.inspect
    end
  end

  test "login_throttle_exempt_ips_warnings names each entry the login check ignores" do
    warnings = GraderConfiguration.login_throttle_exempt_ips_warnings("10.0.5.40;10.0.5.41, 10.0.5.42, 10.0.5.999")
    assert_equal 2, warnings.size
    assert_match(/'10.0.5.40;10.0.5.41' is not an address or range/, warnings[0])
    assert_match(/'10.0.5.999' is not an address or range/, warnings[1])
  end

  test "login_throttle_exempt_ips_warnings flags a range that covers every address" do
    warnings = GraderConfiguration.login_throttle_exempt_ips_warnings("0.0.0.0/0, ::/0, 10.0.5.40/0, 10.0.0.0/8")
    assert_equal ["'0.0.0.0/0'", "'::/0'", "'10.0.5.40/0'"], warnings.map { |w| w[/'[^']*'/] }
    assert(warnings.all? { |w| w.include?("covers every address") })
  end

  test "value_warnings checks only the exempt list setting" do
    conf = GraderConfiguration.find_by(key: GraderConfiguration::LOGIN_THROTTLE_EXEMPT_IPS_KEY)
    conf.value = "not-an-ip"
    assert_equal 1, conf.value_warnings.size

    other = GraderConfiguration.find_by(key: "right.whitelist_ip")
    other.value = "not-an-ip"
    assert_equal [], other.value_warnings
  end

  # --- set_exam_mode ---

  test "set_exam_mode updates multiple configs" do
    GraderConfiguration.set_exam_mode(true)
    reset_grader_config_cache
    assert_not GraderConfiguration["right.bypass_agreement"]
    assert_not GraderConfiguration["right.multiple_ip_login"]
  end

  # The Contest button asks ON or OFF (design 2026-11-18, revised
  # 2026-11-19), so an exam mode no longer turns the whitelist on by itself.
  test "set_exam_mode leaves the IP whitelist alone; set_whitelist switches it and keeps the allowed list" do
    set_grader_config("right.whitelist_ip", "10.0.5.0/24")
    GraderConfiguration.set_exam_mode(true)
    reset_grader_config_cache
    assert_not GraderConfiguration.whitelist_active?

    GraderConfiguration.set_whitelist(true)
    reset_grader_config_cache
    assert GraderConfiguration.whitelist_active?
    assert_equal ["10.0.5.0/24"], GraderConfiguration.whitelist_ranges

    GraderConfiguration.set_whitelist(false)
    reset_grader_config_cache
    assert_not GraderConfiguration.whitelist_active?
    assert_equal ["10.0.5.0/24"], GraderConfiguration.whitelist_ranges
  ensure
    reset_grader_config_cache
  end
end
