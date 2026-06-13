# The test suites live in two parallel worlds: minitest in test/ (models,
# integration, system) and RSpec in spec/ (the rswag API specs, which double
# as the Swagger docs). `bin/rails test` runs only the former and `rspec`
# only the latter, so a green run of either says nothing about the other.
# `check` is the one command that runs both, plus the swagger freshness
# guard. System tests are excluded (slow, need Chrome) — run them with
# `bin/rails test:system`.
#
# Named `check` because Rails already owns `test:all` (all minitest
# including system tests).
desc "Run all test suites: minitest (test/), RSpec API specs (spec/), swagger freshness"
task :check do
  steps = [
    ["minitest (test/)",        %w[bin/rails test]],
    ["RSpec API specs (spec/)", %w[bundle exec rspec]],
    ["swagger freshness",       %w[bin/rails swagger:verify]]
  ]

  failed = []
  steps.each do |name, cmd|
    puts "\n== #{name}: #{cmd.join(' ')} =="
    failed << name unless system(*cmd)
  end

  abort "\ncheck FAILED: #{failed.join(', ')}" if failed.any?
  puts "\ncheck: all green"
end

namespace :swagger do
  desc "Fail if swagger/v1/swagger.yaml is stale (API specs changed without rswag:specs:swaggerize)"
  task :verify do
    path = Rails.root.join("swagger/v1/swagger.yaml")
    before = File.read(path)

    puts "(regenerating via rswag:specs:swaggerize to compare...)"
    unless system("bin/rails", "rswag:specs:swaggerize", out: File::NULL)
      abort "swagger:verify FAILED: rswag:specs:swaggerize itself failed — are the API specs failing?"
    end

    if File.read(path) == before
      puts "swagger:verify: #{path.relative_path_from(Rails.root)} is up to date"
    else
      # the regenerated (correct) file is left in place on purpose: to fix
      # the failure, just review and commit it
      abort "swagger:verify FAILED: swagger/v1/swagger.yaml was stale. " \
            "It has now been regenerated — review and commit it."
    end
  end
end
