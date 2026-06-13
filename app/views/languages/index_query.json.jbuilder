json.data do
  json.array! @languages do |language|
    json.extract! language, :id, :name, :pretty_name, :ext, :common_ext
  end
end
