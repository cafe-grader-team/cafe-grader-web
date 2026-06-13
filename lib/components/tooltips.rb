module Tooltips
  # To avoid deprecation warning, you need to make the wrapper_options explicit
  # even when they won't be used.
  def tooltip(wrapper_options = nil)
    unless options[:tooltip].nil?

      tooltip_html = "<span class='mi md-18 text-body-tertiary' " +
        "data-bs-toggle='tooltip' " +
        "data-bs-placement='top' " +
        "data-bs-title='#{tooltip_text}' " +
        ">help_center</span>"
      options[:label] = "#{raw_label_text} #{tooltip_html.html_safe}".html_safe
      # options[:label_html] ||= {}
      # options[:label_html]['data-bs-toggle'] ||= 'tooltip'
      # options[:label_html]['data-bs-placement'] ||= tooltip_position
      # options[:label_html]['data-bs-title'] ||= tooltip_text
      # input_html_options['data-bs-toggle'] ||= 'tooltip'
      # input_html_options['data-bs-placement'] ||= tooltip_position
      # input_html_options['data-bs-title'] ||= tooltip_text
      return nil # we don't want any text render
    end
  end

  def tooltip_text
    tooltip = options[:tooltip]
    if tooltip.is_a?(String)
      tooltip
    elsif tooltip.is_a?(Array)
      tooltip[1]
    else
      nil
    end
  end

  def tooltip_position
    tooltip = options[:tooltip]
    tooltip.is_a?(Array) ? tooltip[0] : "right"
  end
end

SimpleForm.include_component(Tooltips)
