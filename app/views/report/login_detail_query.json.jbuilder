json.draw params['draw']&.to_i
json.recordsTotal @recordsTotal
json.recordsFiltered @recordsFiltered
json.data do
  json.array! @logins do |login|
    json.login_text login.user ? "<a href='#{stat_user_admin_path(login.user_id)}'>(#{h login.user.login})</a> #{h login.user.full_name}" : '-- deletec user --'
    json.created_at login.created_at.strftime('%Y-%m-%d %H:%M')
    json.ip_address login.ip_address
    json.cookie login.cookie
  end
end
