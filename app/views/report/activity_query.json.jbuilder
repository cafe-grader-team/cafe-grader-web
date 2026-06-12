json.draw params['draw']&.to_i
json.data do
  json.array! @rows do |r|
    json.user_id r[:user_id]
    json.login r[:login]
    json.full_name r[:full_name]
    json.sub_count r[:sub_count]
    json.prob_count r[:prob_count]
    json.solved_count r[:solved_count]
    json.first_sub r[:first_sub]&.iso8601
    json.last_sub r[:last_sub]&.iso8601
    json.ip_count r[:ip_count]
  end
end
