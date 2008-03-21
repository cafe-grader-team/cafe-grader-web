# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper

  def user_header
    menu_items = ''
    user = User.find(session[:user_id])

    # main page
    append_to menu_items, '[Main]', 'main', 'list'
    append_to menu_items, '[Submissions]', 'main', 'submission'
    append_to menu_items, '[Test]', 'test', 'index'

    # admin menu
    if (user!=nil) and (user.admin?) 
      append_to menu_items, '[Problem admin]', 'problems', 'index'
      append_to menu_items, '[User admin]', 'user_admin', 'index'
      append_to menu_items, '[User stat]', 'user_admin', 'user_stat'
    end

    # general options
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

end
