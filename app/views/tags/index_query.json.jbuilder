# for data table
json.data do
  json.array! @tags do |tag|
    json.extract! tag, :id, :name, :description, :public, :kind
    json.kind_text I18n.t(tag.kind, scope: "activerecord.attributes.tag.kinds")
  end
end
