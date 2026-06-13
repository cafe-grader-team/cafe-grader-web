json.draw params['draw']&.to_i
json.recordsTotal @recordsTotal
json.recordsFiltered @recordsFiltered
json.data do
  json.array! @users do |user|
    json.login_text "<a href='#{stat_user_admin_path(user[:id])}'>(#{user[:login]})</a> #{user[:full_name]}"
    json.count user[:count]
    json.earliest user[:min].strftime('%Y-%m-%d %H:%M')
    json.latest user[:max].strftime('%Y-%m-%d %H:%M')
    json.ip_address user[:ip].join('<br/>')
    json.cookie user[:cookie].join('<br/>')
  end
end
