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
end
