json.data do
  json.array! @problems do |prob|
    solved = prob.solved_count.to_i
    attempted = prob.attempted_count.to_i
    rate = attempted > 0 ? (solved * 100.0 / attempted).round(1) : 0
    json.id prob.id
    json.name prob.name
    json.full_name prob.full_name
    json.sub_count prob.sub_count.to_i
    json.solved solved
    json.attempted attempted
    json.rate rate
  end
end
