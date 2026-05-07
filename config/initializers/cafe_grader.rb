Rails.configuration.worker = Rails.application.config_for(:worker)
Rails.configuration.llm = Rails.application.config_for(:llm)

# build llm service key into provider
# provider[x] is the service object class name that provides llm model x
# We can get the actual class by  Rails.configuration.llm[:provider]["gemini-2.5-pro"].constantize
#
# Some keys in llm.yml configure things other than per-model service registration
# (e.g., viva_turn_service points directly at a concrete class). Skip those.
LLM_NON_SERVICE_KEYS = %i[viva_turn_service viva_grade_service provider].freeze

provider = Hash.new
Rails.configuration.llm.each do |x|
  # skip when the config is malformed or the key isn't a service registration
  next if LLM_NON_SERVICE_KEYS.include?(x[0])
  next unless x.count >= 2
  next unless x[1].is_a? String

  class_name = x[0]
  x[1].split(',').each { |model| provider[model] = 'Llm::'+class_name.to_s }
end
Rails.configuration.llm[:provider] = provider
