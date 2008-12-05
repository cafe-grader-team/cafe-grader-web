# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper

  SYSTEM_MODE_CONF_KEY = 'system.mode'

  def user_header
    menu_items = ''
    user = User.find(session[:user_id])

    if (user!=nil) and (session[:admin]) 
      # admin menu
      menu_items << "<b>Administrative task:</b> "
      append_to menu_items, '[Announcements]', 'announcements', 'index'
      append_to menu_items, '[Msg console]', 'messages', 'console'
      append_to menu_items, '[Problem admin]', 'problems', 'index'
      append_to menu_items, '[User admin]', 'user_admin', 'index'
      append_to menu_items, '[User stat]', 'user_admin', 'user_stat'
      append_to menu_items, '[Graders]', 'graders', 'list'
      append_to menu_items, '[Site config]', 'configurations', 'index'
      menu_items << "<br/>"
    end

    # main page
    append_to menu_items, '[Main]', 'main', 'list'
    append_to menu_items, '[Messages]', 'messages', 'list'

    if (user!=nil) and (Configuration.show_tasks_to?(user))
      append_to menu_items, '[Tasks]', 'tasks', 'list'
      append_to menu_items, '[Submissions]', 'main', 'submission'
      append_to menu_items, '[Test]', 'test', 'index'
    end
    append_to menu_items, '[Help]', 'main', 'help'

    if Configuration['system.user_setting_enabled']
      append_to menu_items, '[Settings]', 'users', 'index'
    end
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
    now = Time.now.gmtime
    st = ''
    if (time.yday != now.yday) or
	(time.year != now.year)
      st = time.strftime("%x ")
    end
    st + time.strftime("%X")
  end

  def read_textfile(fname,max_size=2048)
    begin
      File.open(fname).read(max_size)
    rescue
      nil
    end
  end

  def user_title_bar(user)
    header = ''
    time_left = ''

    #
    # if the contest is over
    if Configuration[SYSTEM_MODE_CONF_KEY]=='contest' 
      if user.site!=nil and user.site.finished?
        header = <<CONTEST_OVER
<tr><td colspan="2" align="center">
<span class="contest-over-msg">THE CONTEST IS OVER</span>
</td></tr>
CONTEST_OVER
      end
      if user.site!=nil
        time_left = ". Time left: #{Time.at(user.site.time_left).gmtime.strftime("%X")}"
      end
    end
    
    #
    # if the contest is in the anaysis mode
    if Configuration[SYSTEM_MODE_CONF_KEY]=='analysis'
      header = <<ANALYSISMODE
<tr><td colspan="2" align="center">
<span class="contest-over-msg">ANALYSIS MODE</span>
</td></tr>
ANALYSISMODE
    end

    contest_name = Configuration['contest.name']

    #
    # build real title bar
    <<TITLEBAR
<div class="title">
<table>
#{header}
<tr>
<td class="left-col">
#{user.full_name}<br/>
Current time is #{format_short_time(Time.new.gmtime)} UTC
#{time_left}
<br/>
</td>
<td class="right-col">#{contest_name}</td>
</tr>
</table>
</div>
TITLEBAR
  end

end
