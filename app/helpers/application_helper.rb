# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper

  def user_options
    options = ''
    user = User.find(session[:user_id])
    if user.admin? 
      options = options + ' ' +
	(link_to_unless_current '[Problem admin]', 
           :controller => 'problems', :action => 'index')
      options = options + ' ' +
	(link_to_unless_current '[User admin]',
           :controller => 'user_admin', :action => 'index')
    end
    options += link_to_unless_current '[Main]',
                 :controller => 'main', :action => 'list'
    options += link_to_unless_current '[Settings]',
                 :controller => 'users', :action => 'index'
    options = options + ' ' +
      link_to('[Log out]', {:controller => 'main', :action => 'login'})
    options
  end

end
