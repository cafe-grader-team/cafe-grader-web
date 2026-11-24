# Rows for the submissions table on problems#stat (see stat.html.haml).
json.data do
  json.array! @submissions do |sub|
    json.extract! sub, :id, :user_id, :login, :full_name, :pretty_name,
                       :submitted_at, :grader_comment, :ip_address
    # decimal(16,6) would serialize as a string ("100.0") and sort lexically.
    json.points sub.points&.to_f
  end
end
