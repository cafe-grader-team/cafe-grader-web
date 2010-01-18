# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20100118174404) do

  create_table "announcements", :force => true do |t|
    t.string   "author"
    t.text     "body"
    t.boolean  "published"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "frontpage",    :default => false
    t.boolean  "contest_only", :default => false
    t.string   "title"
  end

  create_table "configurations", :force => true do |t|
    t.string   "key"
    t.string   "value_type"
    t.string   "value"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "countries", :force => true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "descriptions", :force => true do |t|
    t.text     "body"
    t.boolean  "markdowned"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "grader_processes", :force => true do |t|
    t.string   "host",       :limit => 20
    t.integer  "pid"
    t.string   "mode"
    t.boolean  "active"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "task_id"
    t.string   "task_type"
    t.boolean  "terminated"
  end

  add_index "grader_processes", ["host", "pid"], :name => "index_grader_processes_on_ip_and_pid"

  create_table "languages", :force => true do |t|
    t.string "name",        :limit => 10
    t.string "pretty_name"
    t.string "ext",         :limit => 10
    t.string "common_ext"
  end

  create_table "messages", :force => true do |t|
    t.integer  "sender_id"
    t.integer  "receiver_id"
    t.integer  "replying_message_id"
    t.text     "body"
    t.boolean  "replied"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "problems", :force => true do |t|
    t.string  "name",           :limit => 30
    t.string  "full_name"
    t.integer "full_score"
    t.date    "date_added"
    t.boolean "available"
    t.string  "url"
    t.integer "description_id"
    t.boolean "test_allowed"
    t.boolean "output_only"
  end

  create_table "rights", :force => true do |t|
    t.string "name"
    t.string "controller"
    t.string "action"
  end

  create_table "rights_roles", :id => false, :force => true do |t|
    t.integer "right_id"
    t.integer "role_id"
  end

  add_index "rights_roles", ["role_id"], :name => "index_rights_roles_on_role_id"

  create_table "roles", :force => true do |t|
    t.string "name"
  end

  create_table "roles_users", :id => false, :force => true do |t|
    t.integer "role_id"
    t.integer "user_id"
  end

  add_index "roles_users", ["user_id"], :name => "index_roles_users_on_user_id"

  create_table "sessions", :force => true do |t|
    t.string   "session_id"
    t.text     "data"
    t.datetime "updated_at"
  end

  add_index "sessions", ["session_id"], :name => "index_sessions_on_session_id"
  add_index "sessions", ["updated_at"], :name => "index_sessions_on_updated_at"

  create_table "sites", :force => true do |t|
    t.string   "name"
    t.boolean  "started"
    t.datetime "start_time"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "country_id"
    t.string   "password"
  end

  create_table "submissions", :force => true do |t|
    t.integer  "user_id"
    t.integer  "problem_id"
    t.integer  "language_id"
    t.text     "source"
    t.binary   "binary"
    t.datetime "submitted_at"
    t.datetime "compiled_at"
    t.text     "compiler_message"
    t.datetime "graded_at"
    t.integer  "points"
    t.text     "grader_comment"
    t.integer  "number"
    t.string   "source_filename"
  end

  add_index "submissions", ["user_id", "problem_id", "number"], :name => "index_submissions_on_user_id_and_problem_id_and_number", :unique => true
  add_index "submissions", ["user_id", "problem_id"], :name => "index_submissions_on_user_id_and_problem_id"

  create_table "tasks", :force => true do |t|
    t.integer  "submission_id"
    t.datetime "created_at"
    t.integer  "status"
    t.datetime "updated_at"
  end

  create_table "test_pair_assignments", :force => true do |t|
    t.integer  "user_id"
    t.integer  "problem_id"
    t.integer  "test_pair_id"
    t.integer  "test_pair_number"
    t.integer  "request_number"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "submitted"
  end

  create_table "test_pairs", :force => true do |t|
    t.integer  "problem_id"
    t.text     "input"
    t.text     "solution"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "number"
  end

  create_table "test_requests", :force => true do |t|
    t.integer  "user_id"
    t.integer  "problem_id"
    t.integer  "submission_id"
    t.string   "input_file_name"
    t.string   "output_file_name"
    t.string   "running_stat"
    t.integer  "status"
    t.datetime "updated_at"
    t.datetime "submitted_at"
    t.datetime "compiled_at"
    t.text     "compiler_message"
    t.datetime "graded_at"
    t.string   "grader_comment"
    t.datetime "created_at"
    t.float    "running_time"
    t.string   "exit_status"
    t.integer  "memory_usage"
  end

  add_index "test_requests", ["user_id", "problem_id"], :name => "index_test_requests_on_user_id_and_problem_id"

  create_table "users", :force => true do |t|
    t.string   "login",           :limit => 50
    t.string   "full_name"
    t.string   "hashed_password"
    t.string   "salt",            :limit => 5
    t.string   "alias"
    t.string   "email"
    t.integer  "site_id"
    t.integer  "country_id"
    t.boolean  "activated",                     :default => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["login"], :name => "index_users_on_login", :unique => true

end
