# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_06_10_120000) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "announcements", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "author"
    t.text "body", size: :medium
    t.boolean "published"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "frontpage", default: false
    t.boolean "contest_only", default: false
    t.string "title"
    t.string "notes"
    t.boolean "on_nav_bar", default: false
    t.bigint "group_id"
    t.index ["group_id"], name: "index_announcements_on_group_id"
  end

  create_table "audit_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.string "actor_note"
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.string "action", null: false
    t.json "object_changes"
    t.string "ip_address", limit: 45
    t.datetime "created_at", null: false
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "comment_reveals", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "comment_id", null: false
    t.bigint "user_id", null: false
    t.boolean "enabled", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["comment_id"], name: "index_comment_reveals_on_comment_id"
    t.index ["user_id"], name: "index_comment_reveals_on_user_id"
  end

  create_table "comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "commentable_type", null: false
    t.bigint "commentable_id", null: false
    t.bigint "user_id", null: false
    t.integer "kind", default: 0
    t.boolean "enabled", default: true
    t.float "cost"
    t.string "title"
    t.text "body", size: :medium
    t.text "remark"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "llm_response", size: :medium
    t.string "llm_model"
    t.integer "status", default: 0
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "contests", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.boolean "enabled"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "description"
    t.datetime "start"
    t.datetime "stop"
    t.boolean "finalized", default: false
    t.text "remark", size: :medium
    t.integer "pre_contest_seconds", default: 0
    t.integer "post_contest_seconds", default: 0
    t.text "log", size: :medium
    t.boolean "allow_hint", default: true
  end

  create_table "contests_problems", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "contest_id"
    t.bigint "problem_id"
    t.integer "number"
    t.float "weight", default: 1.0
    t.boolean "enabled", default: true
    t.boolean "allow_llm", default: false
    t.index ["contest_id"], name: "index_contests_problems_on_contest_id"
    t.index ["problem_id"], name: "index_contests_problems_on_problem_id"
  end

  create_table "contests_users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "contest_id"
    t.bigint "user_id"
    t.decimal "current_score", precision: 10
    t.integer "start_offset_second", default: 0
    t.integer "extra_time_second", default: 0
    t.string "remark"
    t.string "seat"
    t.boolean "enabled", default: true
    t.datetime "last_heartbeat"
    t.integer "role", default: 0
    t.index ["contest_id"], name: "index_contests_users_on_contest_id"
    t.index ["user_id"], name: "index_contests_users_on_user_id"
  end

  create_table "countries", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "datasets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "problem_id"
    t.string "name"
    t.decimal "time_limit", precision: 10, scale: 2, default: "1.0"
    t.integer "memory_limit"
    t.integer "score_type", limit: 1, default: 0
    t.integer "evaluation_type", limit: 1, default: 0
    t.string "score_param"
    t.string "main_filename"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "initializer_filename"
    t.index ["problem_id"], name: "index_datasets_on_problem_id"
  end

  create_table "descriptions", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", size: :medium
    t.boolean "markdowned"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "evaluations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "submission_id"
    t.bigint "testcase_id"
    t.integer "result"
    t.integer "time"
    t.integer "memory"
    t.decimal "score", precision: 16, scale: 6
    t.string "result_text"
    t.string "isolate_message"
    t.text "output"
    t.index ["submission_id"], name: "index_evaluations_on_submission_id"
    t.index ["testcase_id"], name: "index_evaluations_on_testcase_id"
  end

  create_table "grader_configurations", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "key"
    t.string "value_type"
    t.string "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "description", size: :medium
  end

  create_table "grader_processes", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "host"
    t.integer "pid"
    t.string "mode"
    t.boolean "active"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "task_id"
    t.string "job_type"
    t.boolean "terminated"
    t.integer "worker_id"
    t.integer "box_id"
    t.datetime "last_heartbeat"
    t.string "key"
    t.boolean "enabled", default: false
    t.integer "status", default: 0
    t.index ["host", "pid"], name: "index_grader_processes_on_host_and_pid"
  end

  create_table "groups", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.boolean "enabled", default: true
    t.boolean "hidden", default: false
  end

  create_table "groups_problems", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "problem_id", null: false
    t.integer "group_id", null: false
    t.boolean "enabled", default: true
    t.index ["group_id", "problem_id"], name: "index_groups_problems_on_group_id_and_problem_id"
  end

  create_table "groups_users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "group_id", null: false
    t.integer "user_id", null: false
    t.integer "role", default: 0
    t.boolean "enabled", default: true
    t.index ["user_id", "group_id"], name: "index_groups_users_on_user_id_and_group_id"
  end

  create_table "heart_beats", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.string "ip_address"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status"
    t.index ["updated_at"], name: "index_heart_beats_on_updated_at"
  end

  create_table "jobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "status", limit: 1, default: 0
    t.integer "grader_process_id"
    t.integer "job_type"
    t.integer "arg"
    t.string "param"
    t.string "result"
    t.bigint "parent_job_id"
    t.datetime "finished"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "priority", default: 0
    t.index ["parent_job_id"], name: "index_jobs_on_parent_job_id"
  end

  create_table "languages", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", limit: 10
    t.string "pretty_name"
    t.string "ext", limit: 10
    t.string "common_ext"
    t.boolean "binary", default: false
    t.index ["name"], name: "index_languages_on_name", unique: true
  end

  create_table "logins", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.string "ip_address"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "cookie"
    t.index ["user_id"], name: "index_logins_on_user_id"
  end

  create_table "messages", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "sender_id"
    t.integer "receiver_id"
    t.integer "replying_message_id"
    t.text "body", size: :medium
    t.boolean "replied"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "problem_stats", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "problem_id", null: false
    t.integer "sub_count", default: 0, null: false
    t.integer "solved_count", default: 0, null: false
    t.integer "attempted_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["problem_id"], name: "index_problem_stats_on_problem_id", unique: true
  end

  create_table "problems", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", limit: 30
    t.string "full_name"
    t.integer "full_score"
    t.date "date_added"
    t.boolean "available"
    t.string "url"
    t.integer "description_id"
    t.boolean "test_allowed"
    t.boolean "output_only"
    t.string "description_filename"
    t.boolean "view_testcase"
    t.integer "difficulty"
    t.text "description", size: :medium
    t.boolean "markdown"
    t.bigint "live_dataset_id"
    t.string "submission_filename"
    t.integer "task_type", limit: 1, default: 0
    t.integer "compilation_type", limit: 1, default: 0
    t.string "permitted_lang"
    t.text "log", size: :medium
    t.boolean "allow_hint", default: true
    t.boolean "view_submission", default: true
    t.index ["live_dataset_id"], name: "index_problems_on_live_dataset_id"
  end

  create_table "problems_tags", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "problem_id"
    t.integer "tag_id"
    t.index ["problem_id", "tag_id"], name: "index_problems_tags_on_problem_id_and_tag_id", unique: true
    t.index ["problem_id"], name: "index_problems_tags_on_problem_id"
    t.index ["tag_id"], name: "index_problems_tags_on_tag_id"
  end

  create_table "rights", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.string "controller"
    t.string "action"
  end

  create_table "rights_roles", id: false, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "right_id"
    t.integer "role_id"
    t.index ["role_id"], name: "index_rights_roles_on_role_id"
  end

  create_table "roles", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
  end

  create_table "roles_users", id: false, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "role_id"
    t.integer "user_id"
    t.index ["user_id"], name: "index_roles_users_on_user_id"
  end

  create_table "sessions", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "session_id"
    t.text "data", size: :medium
    t.datetime "updated_at", precision: nil
    t.index ["session_id"], name: "index_sessions_on_session_id"
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "sites", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.boolean "started"
    t.datetime "start_time", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "country_id"
    t.string "password"
  end

  create_table "submission_view_logs", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.integer "submission_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "submissions", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.integer "problem_id"
    t.integer "language_id"
    t.text "source", size: :long
    t.binary "binary", size: :long
    t.datetime "submitted_at", precision: nil
    t.datetime "compiled_at", precision: nil
    t.text "compiler_message", size: :medium
    t.datetime "graded_at", precision: nil
    t.decimal "points", precision: 16, scale: 6
    t.text "grader_comment", size: :medium
    t.integer "number"
    t.string "source_filename"
    t.float "max_runtime"
    t.integer "peak_memory"
    t.integer "effective_code_length"
    t.string "ip_address"
    t.integer "tag", default: 0
    t.integer "status", limit: 1, default: 0
    t.string "cookie"
    t.string "content_type"
    t.datetime "viva_archived_at"
    t.datetime "viva_terminated_at"
    t.index ["graded_at"], name: "index_submissions_on_graded_at"
    t.index ["problem_id"], name: "index_submissions_on_problem_id"
    t.index ["submitted_at"], name: "index_submissions_on_submitted_at"
    t.index ["tag"], name: "index_submissions_on_tag"
    t.index ["user_id", "problem_id", "number"], name: "index_submissions_on_user_id_and_problem_id_and_number", unique: true
    t.index ["viva_archived_at"], name: "index_submissions_on_viva_archived_at"
    t.index ["viva_terminated_at"], name: "index_submissions_on_viva_terminated_at"
  end

  create_table "tags", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.text "description", size: :medium
    t.boolean "public"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "color", default: "#6C757D"
    t.text "params", size: :medium
    t.integer "kind", default: 0
  end

  create_table "tasks", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "submission_id"
    t.datetime "created_at", precision: nil
    t.integer "status"
    t.datetime "updated_at", precision: nil
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["submission_id"], name: "index_tasks_on_submission_id"
  end

  create_table "test_pairs", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "problem_id"
    t.text "input", size: :long
    t.text "solution", size: :long
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "test_requests", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.integer "problem_id"
    t.integer "submission_id"
    t.string "input_file_name"
    t.string "output_file_name"
    t.string "running_stat"
    t.integer "status"
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "submitted_at", precision: nil
    t.datetime "compiled_at", precision: nil
    t.text "compiler_message", size: :medium
    t.datetime "graded_at", precision: nil
    t.string "grader_comment"
    t.datetime "created_at", precision: nil, null: false
    t.float "running_time"
    t.string "exit_status"
    t.integer "memory_usage"
    t.index ["user_id", "problem_id"], name: "index_test_requests_on_user_id_and_problem_id"
  end

  create_table "testcases", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "problem_id"
    t.integer "num"
    t.integer "group"
    t.integer "weight"
    t.text "input", size: :long
    t.text "sol", size: :long
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.bigint "dataset_id"
    t.string "group_name"
    t.string "code_name"
    t.index ["dataset_id"], name: "index_testcases_on_dataset_id"
    t.index ["problem_id"], name: "index_testcases_on_problem_id"
  end

  create_table "user_contest_stats", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "user_id"
    t.datetime "started_at"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "forced_logout"
  end

  create_table "users", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "login", limit: 50
    t.string "full_name"
    t.string "hashed_password"
    t.string "salt", limit: 5
    t.string "alias"
    t.string "email"
    t.integer "site_id"
    t.integer "country_id"
    t.boolean "activated", default: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "enabled", default: true
    t.string "remark"
    t.string "last_ip"
    t.string "section"
    t.integer "default_language_id"
    t.datetime "last_heartbeat"
    t.index ["login"], name: "index_users_on_login", unique: true
  end

  create_table "viva_grades", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "submission_id", null: false
    t.string "rubric_version"
    t.text "score_json", size: :medium
    t.decimal "total_points", precision: 8, scale: 4
    t.text "narrative", size: :medium
    t.string "llm_model"
    t.text "llm_response_raw", size: :medium
    t.float "cost"
    t.datetime "graded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submission_id"], name: "index_viva_grades_on_submission_id", unique: true
  end

  create_table "viva_turns", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "submission_id", null: false
    t.integer "sequence", null: false
    t.integer "role", default: 2, null: false
    t.integer "status", default: 0, null: false
    t.text "content", size: :medium
    t.text "llm_response_raw", size: :medium
    t.string "llm_model"
    t.float "cost"
    t.integer "token_count_in"
    t.integer "token_count_out"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submission_id", "sequence"], name: "index_viva_turns_on_submission_id_and_sequence", unique: true
  end

  create_table "worker_datasets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "worker_id"
    t.bigint "dataset_id"
    t.integer "testcases_status", limit: 1, default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "managers_status", limit: 1, default: 0
    t.index ["dataset_id"], name: "index_worker_datasets_on_dataset_id"
    t.index ["worker_id"], name: "index_worker_datasets_on_worker_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "problem_stats", "problems"
  add_foreign_key "problems_tags", "problems"
  add_foreign_key "problems_tags", "tags"
  add_foreign_key "viva_grades", "submissions"
  add_foreign_key "viva_turns", "submissions"
end
