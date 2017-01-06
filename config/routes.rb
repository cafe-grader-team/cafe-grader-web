CafeGrader::Application.routes.draw do
  get "sources/direct_edit"

  root :to => 'main#login'

  #logins
  get 'login/login',  to: 'login#login'

  resources :contests

  resources :sites

  resources :announcements do
    member do
      get 'toggle','toggle_front'
    end
  end

  resources :problems do
    member do
      get 'toggle'
      get 'toggle_test'
      get 'stat'
      get 'show_testcase'
    end
    collection do
      get 'turn_all_off'
      get 'turn_all_on'
      get 'import'
      get 'manage'
    end

    resources :testcases, only: [] do
      member do
        get 'download_input'
        get 'download_sol'
      end
    end
  end

  resources :grader_configuration, controller: 'configurations'

  resources :users do
    member do
      get 'toggle_activate', 'toggle_enable'
      get 'stat'
    end
  end

  resources :submissions do
    member do
      get 'download'
      get 'compiler_msg'
    end
    collection do
      get 'prob/:problem_id', to: 'submissions#index', as: 'problem'
      get 'direct_edit_problem/:problem_id', to: 'submissions#direct_edit_problem', as: 'direct_edit_problem'
      get 'get_latest_submission_status/:uid/:pid', to: 'submissions#get_latest_submission_status', as: 'get_latest_submission_status'
    end
  end

  get 'tasks/view/:file.:ext' => 'tasks#view'
  get 'tasks/download/:id/:file.:ext' => 'tasks#download'
  get 'heartbeat/:id/edit' => 'heartbeat#edit'

  #main
  get "main/list"
  get 'main/submission(/:id)', to: 'main#submission', as: 'main_submission'

  #report
  get 'report/current_score', to: 'report#current_score', as: 'report_current_score'
  get 'report/problem_hof(/:id)', to: 'report#problem_hof', as: 'report_problem_hof'
  get "report/login"
  get 'report/max_score', to: 'report#max_score', as: 'report_max_score'
  post 'report/show_max_score', to: 'report#show_max_score', as: 'report_show_max_score'

  #grader
  get 'graders/list', to: 'graders#list', as: 'grader_list'
  

  get 'heartbeat/:id/edit' => 'heartbeat#edit'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  match ':controller(/:action(/:id))(.:format)', via:  [:get, :post]
end
