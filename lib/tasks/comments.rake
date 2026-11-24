namespace :comments do
  desc 'Backfill prompt/completion token counts on llm_assist comments from the stored provider response'
  task backfill_llm_usage: :environment do
    scope = Comment.where(kind: 'llm_assist', prompt_tokens: nil).where.not(llm_response: [nil, ''])
    total = scope.count
    done = 0
    scope.find_each { |c| done += 1 if c.backfill_llm_usage! }
    puts "backfilled token counts on #{done} of #{total} llm_assist comments"
  end
end
