namespace :problems do
  desc 'Export a problem to a zip. Usage: rails "problems:export[<name_or_id>,all]" (2nd arg "all" -> all datasets)'
  task :export, %i[ref scope] => :environment do |_t, args|
    unless args[:ref]
      warn 'Usage: rails "problems:export[<problem name or id>,all]"  (omit "all" for live dataset only)'
      next
    end
    problem = Problem.find_by(id: args[:ref]) || Problem.find_by(name: args[:ref])
    unless problem
      warn "Problem '#{args[:ref]}' not found."
      next
    end
    all = args[:scope].to_s.downcase == 'all'
    res = problem.export(all_datasets: all, zip: true)
    puts "Exported '#{problem.name}' (#{all ? 'all datasets' : 'live dataset only'}) -> #{res[:zip]}"
    puts "  status: #{res[:status]}#{res[:error] ? " (#{res[:error]})" : ''}"
  end
end
