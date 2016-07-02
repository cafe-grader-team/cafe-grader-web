CafeGrader::Application.routes.draw do
  get "sources/direct_edit"

  root :to => 'main#login'


  resources :contests

  resources :sites

  resources :announcements do
    member do
      get 'toggle'
    end
  end


  resources :problems do
    member do
      get 'toggle'
    end
    collection do
      get 'turn_all_off'
      get 'turn_all_on'
      get 'import'
      get 'manage'
    end
  end

  resources :grader_configuration, controller: 'configurations'

  resources :users do
    member do
      get 'toggle_activate', 'toggle_enable'
    end
  end

  #resources :sources do
  #  collection do
  #  end
  #end
  get 'sources/direct_edit/:pid', to: 'sources#direct_edit', as: 'direct_edit'


  match 'tasks/view/:file.:ext' => 'tasks#view'
  match 'tasks/download/:id/:file.:ext' => 'tasks#download'
  match 'heartbeat/:id/edit' => 'heartbeat#edit'

  #main
  get "main/list"
  get 'main/submission(/:id)', to: 'main#submission', as: 'main_submission'

  #report
  get 'report/problem_hof(/:id)', to: 'report#problem_hof', as: 'report_problem_hof'
  get "report/login"

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  match ':controller(/:action(/:id))(.:format)'
end
