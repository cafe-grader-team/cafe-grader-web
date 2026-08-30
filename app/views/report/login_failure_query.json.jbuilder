json.draw params['draw']&.to_i
json.recordsTotal @recordsTotal
json.recordsFiltered @recordsFiltered
json.data do
  json.array! @failures do |login|
    json.attempted_login h(login.attempted_login)
    json.login_text login.user ? "<a href='#{stat_user_admin_path(login.user_id)}'>(#{h login.user.login})</a> #{h login.user.full_name}" : ''
    json.created_at login.created_at.strftime('%Y-%m-%d %H:%M:%S')
    json.ip_address login.ip_address
  end
end
