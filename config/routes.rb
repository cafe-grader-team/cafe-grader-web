Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  # ---- API ----
  namespace :api do
    namespace :v1 do
      post "auth/login", to: "auth#login"

      get "me", to: "users#me"
      resources :languages, only: [:index]

      resources :contests, only: [:show] do
        get "problems", on: :member
      end

      resources :problems, only: [:index, :show] do
        member do
          get "description"
          get "files/:type", action: "file", as: "file"
          get "data_files"
          get "testcases"
        end
        resources :submissions, only: [:index, :create]
      end

      resources :testcases, only: [] do
        member do
          get "input"
          get "sol"
        end
      end

      resources :submissions, only: [:show]
    end
  end

  resources :languages, except: [:show] do
    post :index_query, on: :collection
  end

  resources :tags, except: [:show] do
    post :toggle_public, on: :member
    post :index_query, on: :collection
  end

  get "sources/direct_edit"

  root to: 'main#login'

  # logins
  match 'login/login',  to: 'login#login', via: [:get, :post]

  resources :contests do
    member do
      # report

      # contest
      get 'toggle'
      get 'view'
      post 'view_query'
      post 'add_users_from_csv'
      get 'clone'
      get 'set_active'

      # contests_users
      post 'show_users_query'
      post 'add_user'
      post 'add_user_by_group'
      post 'do_all_users'
      post 'do_user'
      post 'extra_time_user'

      # contests_problems
      post 'show_problems_query'
      post 'add_problem'
      post 'add_problem_by_group'
      post 'do_all_problems'
      post 'do_problem'
    end
    collection do
      post 'index_query'
      post 'set_system_mode'
      post 'user_check_in'
      post 'contest_action'
    end
  end

  resources :sites

  resources :audit_logs, only: [:index, :show]

  resources :messages do
    member do
      get 'hide'
      post 'reply'
    end
    collection do
      get 'console'
      get 'list_all'
    end
  end

  resources :announcements do
    member do
      post 'toggle_published'
      post 'toggle_front'
      delete 'delete_file'
    end
  end

  resources :problems, except: [:new, :show] do
    member do
      post 'toggle_available'
      post 'toggle_view_testcase'
      get 'stat'
      get 'get_statement(/:filename)', as: 'get_statement', action: 'get_statement'
      get 'get_attachment(/:filename)', as: 'get_attachment', action: 'get_attachment'
      get 'download_archive'
      post 'add_dataset'
      post 'import_testcases'
      delete 'attachment', action: 'delete_attachment'
      delete 'statement', action: 'delete_statement'
      get 'helpers(/:submission_id)', as: 'helpers', action: 'helpers'
      # attachment
      get 'download/:attachment_type', to: 'download_by_type', as: 'download_by_type'
      delete 'delete/:attachment_type', to: 'delete_by_type', as: 'delete_by_type'
      # viva exam
      post 'viva/start', to: 'viva_sessions#start', as: 'viva_start'
    end
    collection do
      get 'turn_all_off'
      get 'turn_all_on'
      get 'import'
      get 'manage'
      post 'manage_query'
      post 'quick_create'
      post 'manage', action: 'do_manage'
      post 'do_import'
    end
    resources :comments, as: :hint, path: :hint, only: [:update] do
      get 'edit(/:id)', on: :collection, action: :edit, as: :edit
      post 'manage_problem', on: :collection, as: :manage
      post 'acquire', on: :member
      get '', on: :member, as: '', action: :show_hint
    end
  end

  resources :datasets, only: [:edit, :update, :destroy] do
    member do
      # turbo render
      get 'settings'
      get 'testcases'
      get 'files'

      post 'file/delete/:att_id', action: 'file_delete', as: 'file_delete'
      post 'file/view/:att_id', action: 'file_view', as: 'file_view'
      post 'file/download/:att_id', action: 'file_download', as: 'file_download'
      post 'testcase/input/:tc_id', action: 'testcase_input', as: 'testcase_input'
      post 'testcase/sol/:tc_id', action: 'testcase_sol', as: 'testcase_sol'
      post 'testcase/delete/:tc_id', action: 'testcase_delete', as: 'testcase_delete'
      post 'set_as_live'
      post 'view'
      post 'rejudge'
      post 'set_weight'
    end
  end

  resources :groups do
    member do
      # groups
      post 'toggle'

      # groups_users
      post 'show_users_query'
      post 'add_user', to: 'groups#add_user', as: 'add_user'
      post 'add_user_by_group'
      post 'do_all_users'
      post 'do_user'

      # groups_problems
      post 'show_problems_query'
      post 'add_problem', to: 'groups#add_problem', as: 'add_problem'
      post 'add_problem_by_group'
      post 'do_all_problems'
      post 'do_problem'
    end
  end

  resources :testcases, only: [] do
    member do
      get 'download_input'
      get 'download_sol'
    end
    collection do
      get 'show_problem/:problem_id(/:test_num)' => 'testcases#show_problem', as: 'show_problem'
      get 'download_manager/:problem_id/:mg_id', as: 'download_manager', action: 'download_manager'
    end
  end

  resources :grader_configuration, controller: 'configurations' do
    collection do
      get 'reload'
      get 'set_exam_right(/:value)', action: 'set_exam_right', as: 'set_exam_right'
      post 'clear_user_ip'
    end
    member do
      patch 'toggle'
    end
  end

  resources :users, only: [:new] do
    # these are for each user editing their own properties
    collection do
      get 'profile'
      post 'chg_passwd'
      post 'chg_default_language'
      patch 'update_self'
    end
  end

  # user admin
  # ** since :user_admin is SINGULAR, the helper functions will be xxx_user_admin_index_path <-- NOTICE THE *_index*
  resources :user_admin do
    collection do
      post 'index_query'
      post 'user_action'
      match 'bulk_manage', via: [:get, :post]
      get 'bulk_mail'
      get 'import'
      post 'do_import'
      get 'new_list'
      get 'admin'
      post 'admin_query'
      post 'ta_query'
      get 'active'
      get 'mass_mailing'
      match 'modify_role', via: [:get, :post]
      match 'create_from_list', via: [:get, :post]
      match 'random_all_passwords', via: [:get, :post]
    end
    member do
      get 'clear_last_ip'
      get 'toggle_activate'
      get 'toggle_enable'
      get 'stat'
      get 'stat/contest/:contest_id', to: 'user_admin#stat_contest', as: 'stat_contest'
    end
  end

  resources :submissions do
    member do
      get 'download'
      post 'compiler_msg'
      post 'rejudge'
      get 'set_tag'
      post 'evaluations'
      # viva exam
      get 'viva', to: 'viva_sessions#show', as: 'viva'
      post 'viva/turns', to: 'viva_sessions#answer', as: 'viva_answer'
      get 'viva/refresh', to: 'viva_sessions#refresh', as: 'viva_refresh'
      post 'archive_viva'
    end
    collection do
      get 'prob/:problem_id', to: 'submissions#index', as: 'problem'
      get 'direct_edit_problem/:problem_id(/:user_id)', to: 'submissions#direct_edit_problem', as: 'direct_edit_problem'
      get 'get_latest_submission_status/:uid/:pid', to: 'submissions#get_latest_submission_status', as: 'get_latest_submission_status'
    end
    resources :comments, only: [] do
      post 'llm_assist/:model', on: :collection, as: 'llm_assist', action: 'llm_assist'
      get '', to: 'index_partial', as: '', on: :collection
      post '', action: 'create_for_submission', on: :collection
      member do
        get '', action: 'show_for_submission', as: ''
        delete '', action: 'destroy_for_submission'
        patch '', action: 'update_for_submission'
      end
    end
  end

  # singular resource
  # ---- BEWARE ---- singular resource maps to plural controller by default, we can override by provide controller name directly
  # report
  resource :report, only: [], controller: 'report' do
    # max score report
    get 'max_score'
    post 'max_score_table'
    post 'max_score_query'
    post 'show_max_score'

    # submission report
    get 'submission'
    post 'submission_query'

    # login report
    get 'login'
    get 'login_stat'
    post 'login_stat'
    post 'login_summary_query'
    post 'login_detail_query'
    get 'multiple_login'

    # ai report
    get 'ai'
    post 'ai_query'

    # hall of fame
    get 'problem_hof'
    post 'problem_hof_query'
    post 'problem_hof_recompute'
    get 'problem_hof/:id', action: 'problem_hof_view', as: 'problem_hof_view'

    # get 'progress'


    get 'stuck'
    get 'cheat_report'
    post 'cheat_report'
    get 'cheat_scrutinize'
    post 'cheat_scrutinize'
  end
  # get 'report/current_score', to: 'report#current_score', as: 'report_current_score'
  # get 'report/problem_hof(/:id)', to: 'report#problem_hof', as: 'report_problem_hof'
  # get "report/login"
  # get 'report/max_score', to: 'report#max_score', as: 'report_max_score'
  # post 'report/show_max_score', to: 'report#show_max_score', as: 'report_show_max_score'

  resource :main, only: [], controller: 'main' do
    get 'login'
    get 'logout'
    get 'list'
    get 'submission(/:id)', action: 'submission', as: 'main_submission'
    get 'help'
    post 'submit'
    post 'prob_grop'
  end
  # main
  # get "main/list"
  # get 'main/submission(/:id)', to: 'main#submission', as: 'main_submission'
  # post 'main/submit', to: 'main#submit'
  # get 'main/announcements', to: 'main#announcements'

  namespace :worker do
    post 'compiled_submission/:id', action: :compiled_submission, as: :compiled_submission
    post 'get_compiled_submission/:sub_id/:attach_id', action: :get_compiled_submission, as: :get_compiled_submission
    post 'get_manager/:ds_id/:manager_id', action: :get_manager, as: :get_manager
    post 'get_attachment/:id', action: :get_attachment, as: :get_attachment
  end

  get 'heartbeat/:id/edit' => 'heartbeat#edit'

  # grader
  # get 'graders/list', to: 'graders#list', as: 'grader_list'
  resources :grader_processes, controller: :graders, only: [:index, :update] do
    member do
      post 'edit_job_type'
      post 'set_enabled/:enabled', as: :set_enabled, action: :set_enabled
    end
    collection do
      get 'queues'
      post 'queues_query'
      post 'retry_error_job'
      post 'retry_all_error_jobs'
      post 'clear_all_error_jobs'
    end
  end


  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)', via:  [:get, :post]
end
