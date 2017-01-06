# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20161031063337) do

  create_table "announcements", force: :cascade do |t|
    t.string   "author",       limit: 255
    t.text     "body",         limit: 65535
    t.boolean  "published"
    t.datetime "created_at",                                 null: false
    t.datetime "updated_at",                                 null: false
    t.boolean  "frontpage",                  default: false
    t.boolean  "contest_only",               default: false
    t.string   "title",        limit: 255
    t.string   "notes",        limit: 255
  end

  create_table "contests", force: :cascade do |t|
    t.string   "title",      limit: 255
    t.boolean  "enabled"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.string   "name",       limit: 255
  end

  create_table "contests_problems", id: false, force: :cascade do |t|
    t.integer "contest_id", limit: 4
    t.integer "problem_id", limit: 4
  end

  create_table "contests_users", id: false, force: :cascade do |t|
    t.integer "contest_id", limit: 4
    t.integer "user_id",    limit: 4
  end

  create_table "countries", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "descriptions", force: :cascade do |t|
    t.text     "body",       limit: 65535
    t.boolean  "markdowned"
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  create_table "grader_configurations", force: :cascade do |t|
    t.string   "key",         limit: 255
    t.string   "value_type",  limit: 255
    t.string   "value",       limit: 255
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.text     "description", limit: 65535
  end

  create_table "grader_processes", force: :cascade do |t|
    t.string   "host",       limit: 255
    t.integer  "pid",        limit: 4
    t.string   "mode",       limit: 255
    t.boolean  "active"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.integer  "task_id",    limit: 4
    t.string   "task_type",  limit: 255
    t.boolean  "terminated"
  end

  add_index "grader_processes", ["host", "pid"], name: "index_grader_processes_on_ip_and_pid", using: :btree

  create_table "heart_beats", force: :cascade do |t|
    t.integer  "user_id",    limit: 4
    t.string   "ip_address", limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.string   "status",     limit: 255
  end

  add_index "heart_beats", ["updated_at"], name: "index_heart_beats_on_updated_at", using: :btree

  create_table "languages", force: :cascade do |t|
    t.string "name",        limit: 10
    t.string "pretty_name", limit: 255
    t.string "ext",         limit: 10
    t.string "common_ext",  limit: 255
  end

  create_table "logins", force: :cascade do |t|
    t.integer  "user_id",    limit: 4
    t.string   "ip_address", limit: 255
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
  end

  create_table "messages", force: :cascade do |t|
    t.integer  "sender_id",           limit: 4
    t.integer  "receiver_id",         limit: 4
    t.integer  "replying_message_id", limit: 4
    t.text     "body",                limit: 65535
    t.boolean  "replied"
    t.datetime "created_at",                        null: false
    t.datetime "updated_at",                        null: false
  end

  create_table "problems", force: :cascade do |t|
    t.string  "name",                 limit: 30
    t.string  "full_name",            limit: 255
    t.integer "full_score",           limit: 4
    t.date    "date_added"
    t.boolean "available"
    t.string  "url",                  limit: 255
    t.integer "description_id",       limit: 4
    t.boolean "test_allowed"
    t.boolean "output_only"
    t.string  "description_filename", limit: 255
  end

  create_table "rights", force: :cascade do |t|
    t.string "name",       limit: 255
    t.string "controller", limit: 255
    t.string "action",     limit: 255
  end

  create_table "rights_roles", id: false, force: :cascade do |t|
    t.integer "right_id", limit: 4
    t.integer "role_id",  limit: 4
  end

  add_index "rights_roles", ["role_id"], name: "index_rights_roles_on_role_id", using: :btree

  create_table "roles", force: :cascade do |t|
    t.string "name", limit: 255
  end

  create_table "roles_users", id: false, force: :cascade do |t|
    t.integer "role_id", limit: 4
    t.integer "user_id", limit: 4
  end

  add_index "roles_users", ["user_id"], name: "index_roles_users_on_user_id", using: :btree

  create_table "sessions", force: :cascade do |t|
    t.string   "session_id", limit: 255
    t.text     "data",       limit: 65535
    t.datetime "updated_at"
  end

  add_index "sessions", ["session_id"], name: "index_sessions_on_session_id", using: :btree
  add_index "sessions", ["updated_at"], name: "index_sessions_on_updated_at", using: :btree

  create_table "sites", force: :cascade do |t|
    t.string   "name",       limit: 255
    t.boolean  "started"
    t.datetime "start_time"
    t.datetime "created_at",             null: false
    t.datetime "updated_at",             null: false
    t.integer  "country_id", limit: 4
    t.string   "password",   limit: 255
  end

  create_table "submission_view_logs", force: :cascade do |t|
    t.integer  "user_id",       limit: 4
    t.integer  "submission_id", limit: 4
    t.datetime "created_at",              null: false
    t.datetime "updated_at",              null: false
  end

  create_table "submissions", force: :cascade do |t|
    t.integer  "user_id",               limit: 4
    t.integer  "problem_id",            limit: 4
    t.integer  "language_id",           limit: 4
    t.text     "source",                limit: 65535
    t.binary   "binary",                limit: 65535
    t.datetime "submitted_at"
    t.datetime "compiled_at"
    t.text     "compiler_message",      limit: 65535
    t.datetime "graded_at"
    t.integer  "points",                limit: 4
    t.text     "grader_comment",        limit: 65535
    t.integer  "number",                limit: 4
    t.string   "source_filename",       limit: 255
    t.float    "max_runtime",           limit: 24
    t.integer  "peak_memory",           limit: 4
    t.integer  "effective_code_length", limit: 4
    t.string   "ip_address",            limit: 255
  end

  add_index "submissions", ["user_id", "problem_id", "number"], name: "index_submissions_on_user_id_and_problem_id_and_number", unique: true, using: :btree
  add_index "submissions", ["user_id", "problem_id"], name: "index_submissions_on_user_id_and_problem_id", using: :btree

  create_table "tasks", force: :cascade do |t|
    t.integer  "submission_id", limit: 4
    t.datetime "created_at"
    t.integer  "status",        limit: 4
    t.datetime "updated_at"
  end

  create_table "test_pairs", force: :cascade do |t|
    t.integer  "problem_id", limit: 4
    t.text     "input",      limit: 16777215
    t.text     "solution",   limit: 16777215
    t.datetime "created_at",                  null: false
    t.datetime "updated_at",                  null: false
  end

  create_table "test_requests", force: :cascade do |t|
    t.integer  "user_id",          limit: 4
    t.integer  "problem_id",       limit: 4
    t.integer  "submission_id",    limit: 4
    t.string   "input_file_name",  limit: 255
    t.string   "output_file_name", limit: 255
    t.string   "running_stat",     limit: 255
    t.integer  "status",           limit: 4
    t.datetime "updated_at",                     null: false
    t.datetime "submitted_at"
    t.datetime "compiled_at"
    t.text     "compiler_message", limit: 65535
    t.datetime "graded_at"
    t.string   "grader_comment",   limit: 255
    t.datetime "created_at",                     null: false
    t.float    "running_time",     limit: 24
    t.string   "exit_status",      limit: 255
    t.integer  "memory_usage",     limit: 4
  end

  add_index "test_requests", ["user_id", "problem_id"], name: "index_test_requests_on_user_id_and_problem_id", using: :btree

  create_table "testcases", force: :cascade do |t|
    t.integer  "problem_id", limit: 4
    t.integer  "num",        limit: 4
    t.integer  "group",      limit: 4
    t.integer  "score",      limit: 4
    t.text     "input",      limit: 65535
    t.text     "sol",        limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "testcases", ["problem_id"], name: "index_testcases_on_problem_id", using: :btree

  create_table "user_contest_stats", force: :cascade do |t|
    t.integer  "user_id",       limit: 4
    t.datetime "started_at"
    t.datetime "created_at",              null: false
    t.datetime "updated_at",              null: false
    t.boolean  "forced_logout"
  end

  create_table "users", force: :cascade do |t|
    t.string   "login",           limit: 50
    t.string   "full_name",       limit: 255
    t.string   "hashed_password", limit: 255
    t.string   "salt",            limit: 5
    t.string   "alias",           limit: 255
    t.string   "email",           limit: 255
    t.integer  "site_id",         limit: 4
    t.integer  "country_id",      limit: 4
    t.boolean  "activated",                   default: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "enabled",                     default: true
    t.string   "remark",          limit: 255
    t.string   "last_ip",         limit: 255
    t.string   "section",         limit: 255
  end

  add_index "users", ["login"], name: "index_users_on_login", unique: true, using: :btree

end
