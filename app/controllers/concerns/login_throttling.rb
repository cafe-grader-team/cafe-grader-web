# Brute-force protection shared by the two password doors — the web login
# (LoginController#login) and the API login (Api::V1::AuthController#login).
# The cache keys are door-agnostic, so attempts through either door draw
# down the same budget; throttling only one door would just redirect the
# attack to the other.
#
# Only *failures* count: a NAT'd classroom logging in at once must never
# trip the per-IP counter, so successes cost nothing. The per-account
# counter stops a distributed attack on one account; the per-IP counter
# stops spraying many accounts from one host. A throttled request is
# refused before any password check, so it can't be used as an oracle and
# never reaches external authenticators (CUCAS).
#
# FAILURE_LIMIT sits well above real frustrated-human burst rates observed
# at exam starts (~20 attempts in 2-3 minutes). The window is fixed, not
# sliding: Rails' cache stores keep the first failure's expiry when they
# increment, so a counter dies WINDOW after its first failure and a lock
# lasts at most the rest of that window. No permanent per-account lockout
# on purpose — that would let anyone lock a victim out of an exam by
# hammering their login name.
#
# Exam gateways: when a whole room reaches the server through one NAT
# address (the exam environment's VPN gateway), every student's typo lands
# on one per-IP counter, and a few minutes of wrong passwords lock the room
# out (DS Quiz 2, 2026-10-07: a CU-net password switch left off for four
# minutes, 113 login attempts refused). Addresses listed in
# right.login_throttle_exempt_ips skip the per-IP counter; the per-account
# counter still applies to them. Admins clear live locks with "Clear Login
# Locks" on the configuration page (LoginThrottling.clear_recent!).
module LoginThrottling
  FAILURE_LIMIT = 30
  WINDOW = 3.minutes

  def self.ip_key(ip)
    "login-failures:ip:#{ip}"
  end

  def self.account_key(login)
    "login-failures:acct:#{login.to_s.downcase}"
  end

  # Deletes every live failure counter and reports the ones that were
  # locking. Cache stores cannot list their keys portably, so the candidates
  # come from the logins table: each counted failure also writes a failed
  # Login row, and a live counter's first failure is at most WINDOW old.
  # Returns {addresses: {ip => count}, accounts: {login => count}} holding
  # only the counters that had reached FAILURE_LIMIT.
  def self.clear_recent!(now: Time.zone.now)
    recent = Login.where(success: false).where('created_at >= ?', now - WINDOW - 1.minute)
    locked = {addresses: {}, accounts: {}}
    recent.distinct.pluck(:ip_address).compact.each do |ip|
      count = Rails.cache.read(ip_key(ip)).to_i
      locked[:addresses][ip] = count if count >= FAILURE_LIMIT
      Rails.cache.delete(ip_key(ip))
    end
    recent.distinct.pluck(:attempted_login).compact.map(&:downcase).uniq.each do |login|
      count = Rails.cache.read(account_key(login)).to_i
      locked[:accounts][login] = count if count >= FAILURE_LIMIT
      Rails.cache.delete(account_key(login))
    end
    locked
  end

  private

  def login_throttled?
    (!ip_throttle_exempt? && Rails.cache.read(throttle_ip_key).to_i >= FAILURE_LIMIT) ||
      Rails.cache.read(throttle_account_key).to_i >= FAILURE_LIMIT
  end

  def record_login_failure!
    Rails.cache.increment(throttle_ip_key, 1, expires_in: WINDOW) unless ip_throttle_exempt?
    Rails.cache.increment(throttle_account_key, 1, expires_in: WINDOW)
    create_failed_login_row
  end

  # A refused login (right outside password, wrong door) is logged but does
  # not draw down the failure budget: the student typed a real password.
  def record_refused_login!
    create_failed_login_row
  end

  def create_failed_login_row
    Login.create(user_id: User.where(login: params[:login].to_s).pick(:id),
                 attempted_login: params[:login].to_s,
                 ip_address: request.remote_ip,
                 success: false)
  end

  def clear_login_failures!
    # Proof of ownership clears the account counter only. The IP counter
    # stays: clearing it would let one known-good account reset the budget
    # for spraying other accounts from the same host.
    Rails.cache.delete(throttle_account_key)
  end

  def ip_throttle_exempt?
    return @ip_throttle_exempt if defined?(@ip_throttle_exempt)
    @ip_throttle_exempt = GraderConfiguration.login_throttle_exempt_ip?(request.remote_ip)
  end

  def throttle_ip_key
    LoginThrottling.ip_key(request.remote_ip)
  end

  def throttle_account_key
    LoginThrottling.account_key(params[:login])
  end
end
