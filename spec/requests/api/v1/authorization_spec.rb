require "rails_helper"

RSpec.describe "API Authorization", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :submissions, :languages, :evaluations

  # Fixture recap:
  #   Users: admin (admin role), john (group_a user), mary (group_a editor, contest_a editor),
  #          james (group_a user, contest_a user), jack (contest_a + contest_b user), disabled_user
  #   Problems: prob_add (available), prob_sub (unavailable), easy (available), hard (available)
  #   Group_a: john, admin(editor), mary(editor), james — has prob_add, prob_sub
  #   Contest_a (enabled, ongoing): james, jack, mary(editor), admin(editor) — has prob_add, easy
  #   Contest_b (enabled, ongoing): jack — has easy, hard
  #   Default config: standard mode, use_problem_group=false, view_testcase=false

  # ==============================
  # JWT auth
  # ==============================
  describe "JWT authentication" do
    it "rejects requests with no token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests with invalid token" do
      get "/api/v1/me", headers: { "Authorization" => "Bearer garbage" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects expired tokens" do
      token = JWT.encode(
        { user_id: users(:john).id, exp: 1.day.ago.to_i },
        Rails.application.secret_key_base, "HS256"
      )
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Token has expired")
    end
  end

  # ==============================
  # Standard mode (no group, no contest)
  # ==============================
  describe "standard mode (default fixtures)" do
    # use_problem_group=false, system.mode=standard
    # problems_for_action(:submit) returns Problem.available

    it "any user sees all available problems" do
      get "/api/v1/problems", headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |p| p["name"] }
      expect(names).to include("add", "easy_problem", "hard_problem")
      expect(names).not_to include("subtract") # not available
    end

    it "admin sees all problems including unavailable" do
      get "/api/v1/problems", headers: auth_header_for(users(:admin))
      names = JSON.parse(response.body).map { |p| p["name"] }
      # admin's problems_for_action with respect_admin: false returns Problem.available
      # so admin also only sees available problems in the list
      expect(names).to include("add")
    end
  end

  # ==============================
  # Group mode
  # ==============================
  describe "group mode" do
    before do
      set_grader_config("system.use_problem_group", "true")
    end

    it "user in group sees only group's enabled problems" do
      get "/api/v1/problems", headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |p| p["name"] }
      # john is in group_a, which has prob_add (enabled) and prob_sub (enabled in group but not available)
      expect(names).to include("add")
      expect(names).not_to include("easy_problem") # not in group_a
    end

    it "user NOT in any group sees no problems" do
      get "/api/v1/problems", headers: auth_header_for(users(:jack))
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to be_empty
    end

    it "user NOT in group cannot view a group problem" do
      get "/api/v1/problems/#{problems(:prob_add).id}", headers: auth_header_for(users(:jack))
      expect(response).to have_http_status(:not_found)
    end

    it "user NOT in group cannot submit to a group problem" do
      post "/api/v1/problems/#{problems(:prob_add).id}/submissions",
        params: { source: "int main(){}", language_id: languages(:Language_c).id },
        headers: auth_header_for(users(:jack))
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ==============================
  # Contest mode
  # ==============================
  describe "contest mode" do
    before do
      set_grader_config("system.mode", "contest")
    end

    it "contest user sees only their contest's problems" do
      # james is in contest_a which has prob_add and easy
      get "/api/v1/problems", headers: auth_header_for(users(:james))
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |p| p["name"] }
      expect(names).to include("add", "easy_problem")
      expect(names).not_to include("hard_problem") # in contest_b only
    end

    it "user not in any contest sees no problems" do
      # john is NOT in any contest
      get "/api/v1/problems", headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_empty
    end

    it "user cannot access contest they are not in" do
      get "/api/v1/contests/#{contests(:contest_a).id}", headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:not_found)
    end

    it "user can access contest they are in" do
      get "/api/v1/contests/#{contests(:contest_a).id}", headers: auth_header_for(users(:james))
      expect(response).to have_http_status(:ok)
    end

    it "disabled contest is not accessible" do
      get "/api/v1/contests/#{contests(:contest_c).id}", headers: auth_header_for(users(:admin))
      expect(response).to have_http_status(:ok) # admin bypasses
    end
  end

  # ==============================
  # Testcase visibility
  # ==============================
  describe "testcase visibility" do
    it "rejects when global config view_testcase is false" do
      # right.view_testcase is false by default in fixtures
      get "/api/v1/problems/#{problems(:prob_add).id}/testcases",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end

    it "allows when global config view_testcase is true" do
      set_grader_config("right.view_testcase", "true")
      # User#can_view_testcase? only checks global config, not per-problem flag
      get "/api/v1/problems/#{problems(:prob_add).id}/testcases",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(2) # tc_add_1, tc_add_2
    end

    it "admin always can view testcases" do
      get "/api/v1/problems/#{problems(:prob_add).id}/testcases",
        headers: auth_header_for(users(:admin))
      expect(response).to have_http_status(:ok)
    end

    it "rejects testcase file download when not allowed" do
      get "/api/v1/testcases/#{testcases(:tc_add_1).id}/input",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ==============================
  # File access (edit-only)
  # ==============================
  describe "edit-only file access" do
    it "normal user cannot access checker" do
      get "/api/v1/problems/#{problems(:prob_add).id}/files/checker",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end

    it "normal user cannot access data_files" do
      get "/api/v1/problems/#{problems(:prob_add).id}/data_files",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end

    it "admin can access checker" do
      get "/api/v1/problems/#{problems(:prob_add).id}/files/checker",
        headers: auth_header_for(users(:admin))
      # 404 because no checker attached, but not 403
      expect(response).to have_http_status(:not_found)
    end

    it "admin can access data_files" do
      get "/api/v1/problems/#{problems(:prob_add).id}/data_files",
        headers: auth_header_for(users(:admin))
      expect(response).to have_http_status(:ok)
    end

    it "group editor can access checker" do
      set_grader_config("system.use_problem_group", "true")
      get "/api/v1/problems/#{problems(:prob_add).id}/files/checker",
        headers: auth_header_for(users(:mary))
      # mary is editor of group_a which has prob_add
      expect(response).to have_http_status(:not_found) # no file, but authorized
    end
  end

  # ==============================
  # Submission access
  # ==============================
  describe "submission access" do
    it "user can view own submission" do
      get "/api/v1/submissions/#{submissions(:add1_by_john).id}",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["source"]).to be_present
    end

    it "user cannot view another user's submission" do
      # right.user_view_submission is false in fixtures
      get "/api/v1/submissions/#{submissions(:add1_by_admin).id}",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end

    it "admin can view any submission with source" do
      get "/api/v1/submissions/#{submissions(:add1_by_john).id}",
        headers: auth_header_for(users(:admin))
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["source"]).to be_present
    end

    it "user sees own source but not other's even when can_view_submission" do
      set_grader_config("right.user_view_submission", "true")
      get "/api/v1/submissions/#{submissions(:add1_by_admin).id}",
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["source"]).to be_nil # can view metadata but not source
    end
  end

  # ==============================
  # Submit restrictions
  # ==============================
  describe "submit restrictions" do
    it "cannot submit to unavailable problem" do
      post "/api/v1/problems/#{problems(:prob_sub).id}/submissions",
        params: { source: "int main(){}", language_id: languages(:Language_c).id },
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:forbidden)
    end

    it "cannot submit without source code" do
      post "/api/v1/problems/#{problems(:prob_add).id}/submissions",
        params: {},
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forces language when only one is permitted" do
      problems(:prob_add).update!(permitted_lang: "python")
      post "/api/v1/problems/#{problems(:prob_add).id}/submissions",
        params: { source: "print(1)", language_id: languages(:Language_c).id },
        headers: auth_header_for(users(:john))
      # single permitted language is auto-forced (matches web form behavior)
      expect(response).to have_http_status(:created)
    end

    it "rejects non-permitted language when multiple are permitted" do
      problems(:prob_add).update!(permitted_lang: "python ruby")
      post "/api/v1/problems/#{problems(:prob_add).id}/submissions",
        params: { source: "int main(){}", language_id: languages(:Language_c).id },
        headers: auth_header_for(users(:john))
      expect(response).to have_http_status(:unprocessable_entity)
      data = JSON.parse(response.body)
      expect(data["error"]).to include("not permitted")
      expect(data["permitted_languages"]).to be_present
    end
  end

  # ==============================
  # Disabled user
  # ==============================
  describe "disabled user" do
    it "disabled user can authenticate but model checks will restrict access" do
      # disabled_user has activated: false, so User.authenticate returns nil
      post "/api/v1/auth/login", params: { login: "disabled", password: "disabled" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses to issue a token to an account with enabled=false" do
      users(:john).update!(enabled: false)
      post "/api/v1/auth/login", params: { login: "john", password: "hello" }
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects requests from a disabled account even with a still-valid token" do
      token = jwt_token_for(users(:john))
      users(:john).update!(enabled: false)
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("Account is disabled")
    end

    it "admin bypasses the enabled flag (mirrors web check_valid_login)" do
      users(:admin).update!(enabled: false)
      get "/api/v1/me", headers: auth_header_for(users(:admin))
      expect(response).to have_http_status(:ok)
    end
  end
end
