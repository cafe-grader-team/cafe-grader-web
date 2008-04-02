# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper

  def user_header
    menu_items = ''
    user = User.find(session[:user_id])

    if (user!=nil) and (user.admin?) 
      # admin menu
      menu_items << "<b>Administrative task:</b> "
      append_to menu_items, '[Problem admin]', 'problems', 'index'
      append_to menu_items, '[User admin]', 'user_admin', 'index'
      append_to menu_items, '[User stat]', 'user_admin', 'user_stat'
      #append_to menu_items, '[Graders]', 'graders', 'list'
      append_to menu_items, '[Site config]', 'configurations', 'index'
      menu_items << "<br/>"
    end

    # main page
    append_to menu_items, '[Main]', 'main', 'list'
    append_to menu_items, '[Submissions]', 'main', 'submission'
    append_to menu_items, '[Test]', 'test', 'index'
    append_to menu_items, '[Settings]', 'users', 'index'
    append_to menu_items, '[Log out]', 'main', 'login'

    menu_items
  end

  def append_to(option,label, controller, action)
    option << ' ' if option!=''
    option << link_to_unless_current(label,
                                     :controller => controller,
                                     :action => action)
  end

  def format_short_time(time)
    now = Time.now
    st = ''
    if (time.yday != now.yday) or
	(time.year != now.year)
      st = time.strftime("%x ")
    end
    st + time.strftime("%X")
  end


  def user_title_bar(user)
    <<TITLEBAR
<div class="title">
<table>
<tr>
<td class="left-col">
#{user.full_name}<br/>
Current time is #{format_short_time(Time.new)}<br/>
</td>
<td class="right-col">APIO'08</td>
</tr>
</table>
</div>
TITLEBAR
  end

end
