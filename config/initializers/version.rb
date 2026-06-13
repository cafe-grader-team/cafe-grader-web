# This constant will be available throughout the application.
APP_VERSION = begin
  File.read(Rails.root.join("APP_VERSION")).chomp
rescue StandardError => e
  # Fallback if everything fails. Logs the error for debugging.
  Rails.logger.error("Could not determine APP_VERSION: #{e.message}")
  "N/A"
end

# same for the suffix
APP_VERSION_SUFFIX = begin
  File.read(Rails.root.join("APP_VERSION_SUFFIX")).chomp
rescue StandardError => e
  Rails.logger.error("Could not determine APP_VERSION_SUFFIX: #{e.message}")
  "N/A"
end
