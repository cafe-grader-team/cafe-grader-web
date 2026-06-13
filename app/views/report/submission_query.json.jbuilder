sub_count_by_date = Hash.new(0)
json.draw params['draw']&.to_i
#json.recordsTotal @recordsTotal
#json.recordsFiltered @recordsFiltered
json.data do
  json.array! @submissions do |sub|
    sub_count_by_date[sub.submitted_at.to_date] += 1
    json.extract! sub, :grader_comment, :ip_address, :id, :submitted_at, :points, :login, :pretty_name, :user_id, :user_full_name
    json.extract! sub, :full_name,:problem_id, :name
  end
end
json.sub_count_by_date sub_count_by_date
