# Seam for a login that works outside the grader's own passwords (e.g. a
# university single sign-on). Master has none; a deployment branch overrides
# these three methods (and only this file).
module OutsideLogin
  extend ActiveSupport::Concern

  class_methods do
    # Name shown to users, or nil when this deployment has no outside login.
    def outside_login_name
      nil
    end

    def outside_login_available?
      outside_login_name.present?
    end

    # Whether the outside login is switched on for the site right now.
    def outside_login_on?
      false
    end

    # Whether +password+ is +user+'s password in the outside system.
    def outside_password?(user, password)
      false
    end
  end
end
