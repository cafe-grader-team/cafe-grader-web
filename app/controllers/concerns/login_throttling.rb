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
# at exam starts (~20 attempts in 2-3 minutes). The window slides: each
# failure resets the expiry, so a sustained attack stays blocked until it
# pauses for a full WINDOW. No permanent per-account lockout on purpose —
# that would let anyone lock a victim out of an exam by hammering their
# login name.
module LoginThrottling
  FAILURE_LIMIT = 30
  WINDOW = 3.minutes

  private

  def login_throttled?
    Rails.cache.read(throttle_ip_key).to_i >= FAILURE_LIMIT ||
      Rails.cache.read(throttle_account_key).to_i >= FAILURE_LIMIT
  end

  def record_login_failure!
    Rails.cache.increment(throttle_ip_key, 1, expires_in: WINDOW)
    Rails.cache.increment(throttle_account_key, 1, expires_in: WINDOW)
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

  def throttle_ip_key
    "login-failures:ip:#{request.remote_ip}"
  end

  def throttle_account_key
    "login-failures:acct:#{params[:login].to_s.downcase}"
  end
end
