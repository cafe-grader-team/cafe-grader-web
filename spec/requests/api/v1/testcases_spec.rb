require "swagger_helper"

RSpec.describe "Testcases API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems

  let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }

  path "/api/v1/testcases/{id}/input" do
    get "Download testcase input file" do
      tags "Testcases"
      produces "text/plain"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "input file content" do
        let(:id) do
          tc = testcases(:tc_add_1)
          tc.inp_file.attach(io: StringIO.new(tc.input), filename: "add.1.in", content_type: "text/plain")
          tc.id
        end

        run_test! do |response|
          expect(response.body).to eq("1 2\n")
          expect(response.headers["Content-Disposition"]).to include("add.1.in")
        end
      end

      response "404", "testcase not found (body hints to use the global id from /problems/{id}/testcases, not num)" do
        let(:id) { 999_999 }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["error"]).to eq("Testcase not found")
          expect(body["hint"]).to include("`id`").and include("`num`")
        end
      end

      response "403", "not allowed to view testcase" do
        let(:user) { users(:john) }
        let(:Authorization) { "Bearer #{jwt_token_for(user)}" }
        let(:id) { testcases(:tc_add_1).id }

        # right.view_testcase is false in fixtures
        run_test!
      end
    end
  end

  path "/api/v1/testcases/{id}/sol" do
    get "Download testcase solution file" do
      tags "Testcases"
      produces "text/plain"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "solution file content" do
        let(:id) do
          tc = testcases(:tc_add_1)
          tc.ans_file.attach(io: StringIO.new(tc.sol), filename: "add.1.sol", content_type: "text/plain")
          tc.id
        end

        run_test! do |response|
          expect(response.body).to eq("3\n")
          expect(response.headers["Content-Disposition"]).to include("add.1.sol")
        end
      end

      response "404", "testcase not found (body hints to use the global id from /problems/{id}/testcases, not num)" do
        let(:id) { 999_999 }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["error"]).to eq("Testcase not found")
          expect(body["hint"]).to include("`id`").and include("`num`")
        end
      end

      response "403", "not allowed to view testcase" do
        let(:user) { users(:john) }
        let(:Authorization) { "Bearer #{jwt_token_for(user)}" }
        let(:id) { testcases(:tc_add_1).id }

        run_test!
      end
    end
  end

  # Plain (non-swagger) tests for the tiers (issues #18 and #59). A second
  # `response "200"` block on the paths above would clobber the documented
  # schema in swagger.yaml, so these are intentionally not swagger blocks.
  describe "preview tier on /input and /sol" do
    let(:tc) { testcases(:tc_add_1) }

    before do
      GraderConfiguration.where(key: "right.view_testcase").update_all(value: "true")
      GraderConfiguration.instance_variable_set(:@config_cache, nil)
      problems(:prob_add).update!(view_testcase: true)
      tc.inp_file.attach(io: StringIO.new("A" * 5000), filename: "add.1.in", content_type: "text/plain")
    end

    after { GraderConfiguration.instance_variable_set(:@config_cache, nil) }

    it "gives a student the first 2048 bytes with the size and truncation headers" do
      get "/api/v1/testcases/#{tc.id}/input", headers: { "Authorization" => "Bearer #{jwt_token_for(users(:john))}" }
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to eq(2048)
      expect(response.headers["X-Testcase-Byte-Size"]).to eq("5000")
      expect(response.headers["X-Testcase-Truncated"]).to eq("true")
    end

    it "gives an admin the whole file" do
      get "/api/v1/testcases/#{tc.id}/input", headers: { "Authorization" => "Bearer #{jwt_token_for(users(:admin))}" }
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to eq(5000)
      expect(response.headers["X-Testcase-Truncated"]).to be_nil
    end

    it "refuses a student when the problem's own flag is off, even with the site right on" do
      problems(:prob_add).update!(view_testcase: false)
      get "/api/v1/testcases/#{tc.id}/input", headers: { "Authorization" => "Bearer #{jwt_token_for(users(:john))}" }
      expect(response).to have_http_status(:forbidden)
    end

    it "lists the tier and the file sizes in the problem's testcase metadata" do
      get "/api/v1/problems/#{problems(:prob_add).id}/testcases", headers: { "Authorization" => "Bearer #{jwt_token_for(users(:john))}" }
      expect(response).to have_http_status(:ok)
      row = JSON.parse(response.body).find { |r| r["id"] == tc.id }
      expect(row).to include("access" => "preview", "input_bytes" => 5000, "sol_bytes" => nil)
    end
  end
end
