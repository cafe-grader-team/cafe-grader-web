# Configures rack-mini-profiler. The gem is auto-loaded via Railtie because
# its Gemfile entry is in the :development group without `require: false`,
# so the middleware is already inserted by the time this initializer runs.
#
# Decision (2026-05-18): badge stays visible by default. It doesn't hide or
# block anything on this app's pages, and a constant perf indicator is more
# useful than a forgotten opt-in.
#
# If you ever want it silent-by-default (only profiles when you pass
# `?pp=enable`), uncomment the line:
#   Rack::MiniProfiler.config.enabled = false
# …and use `?pp=enable` to turn on for the current session.
#
# For an ad-hoc disable in the current session use `?pp=disable`.
return unless Rails.env.development?

Rack::MiniProfiler.config.position = "top-right"
