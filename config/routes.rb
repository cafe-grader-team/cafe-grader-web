CafeGrader::Application.routes.draw do
  root :to => 'main#login'

  get "report/login"

  resources :contests

  resources :announcements
  match 'announcements/toggle/:id' => 'announcements#toggle'

  resources :sites

  resources :grader_configuration, controller: 'configurations'

  match 'tasks/view/:file.:ext' => 'tasks#view'
  match 'tasks/download/:id/:file.:ext' => 'tasks#download'
  match 'heartbeat/:id/edit' => 'heartbeat#edit'

  #main
  get "main/list"

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  match ':controller(/:action(/:id))(.:format)'
end
