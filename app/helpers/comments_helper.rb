module CommentsHelper
  # Cells of the AI-assist roll-up (Comment::UsageRow, comments/_llm_usage_by_model).

  # "—" when no row of the model reported a cost (a provider without a cost
  # source, or rows from before the column existed); the count of priced rows
  # when only some did, so the sum is never read as the model's total.
  def llm_usage_dollars(row)
    return '—' if row.priced.to_i.zero?
    text = number_to_currency(row.dollars, precision: 2)
    return text if row.priced == row.requests
    safe_join([text, ' ', content_tag(:span, "(#{row.priced} of #{row.requests} priced)", class: 'text-secondary')])
  end

  # "18.1M / 23.1M" — tokens in / out, compact.
  def llm_usage_tokens(row)
    return '—' if row.prompt_tokens.nil? && row.completion_tokens.nil?
    "#{compact_count(row.prompt_tokens)} / #{compact_count(row.completion_tokens)}"
  end

  # 950 → "950", 5_500 → "5.5k", 18_100_000 → "18.1M".
  def compact_count(n)
    return '—' if n.nil?
    number_to_human(n, precision: 3, significant: true, format: '%n%u',
                    units: {unit: '', thousand: 'k', million: 'M', billion: 'G'})
  end
end
