require "swagger_helper"

RSpec.describe "Submissions API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :submissions, :languages, :evaluations

  let(:user) { users(:admin) }
  let(:Authorization) { "Bearer #{jwt_token_for(user)}" }

  path "/api/v1/problems/{problem_id}/submissions" do
    get "List user's submissions for a problem" do
      tags "Submissions"
      produces "application/json"
      security [bearer: []]

      parameter name: :problem_id, in: :path, type: :integer, required: true

      response "200", "submissions list" do
        schema type: :array, items: {
          type: :object, additionalProperties: false, properties: {
            id: { type: :integer },
            number: { type: :integer },
            language: { type: :string },
            submitted_at: { type: :string, format: "date-time" },
            points: { type: :number, nullable: true },
            status: { type: :string, nullable: true },
            grader_comment: { type: :string, nullable: true }
          }
        }

        let(:problem_id) { problems(:prob_add).id }

        # non-nil points so the schema exercises the type (DECIMAL → must be a JSON number)
        before { submissions(:add1_by_admin).update_columns(points: 50.5) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          mine = data.find { |s| s["id"] == submissions(:add1_by_admin).id }
          expect(mine["points"]).to eq(50.5)
        end
      end
    end

    post "Submit code to a problem" do
      tags "Submissions"
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :problem_id, in: :path, type: :integer, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          source: { type: :string, description: "Source code" },
          filename: { type: :string, description: "Filename (for language detection)" },
          language_id: { type: :integer, description: "Language ID" }
        },
        required: %w[source]
      }

      response "201", "submission created" do
        schema type: :object, additionalProperties: false, properties: {
          id: { type: :integer },
          number: { type: :integer },
          status: { type: :string }
        }, required: %w[id number status]

        let(:problem_id) { problems(:prob_add).id }
        let(:body) { { source: '#include <stdio.h>\nint main() { printf("3"); }', filename: "solution.c", language_id: languages(:Language_c).id } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["id"]).to be_present
          expect(data["status"]).to eq("submitted")
        end
      end

      response "422", "missing source code" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:problem_id) { problems(:prob_add).id }
        let(:body) { {} }

        run_test!
      end
    end
  end

  path "/api/v1/submissions/{id}" do
    get "Get submission detail" do
      tags "Submissions"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "submission detail" do
        schema type: :object, additionalProperties: false, properties: {
          id: { type: :integer },
          problem_id: { type: :integer },
          problem_name: { type: :string },
          user_id: { type: :integer },
          language: { type: :string },
          source: { type: :string, nullable: true },
          source_filename: { type: :string, nullable: true },
          submitted_at: { type: :string, format: "date-time" },
          points: { type: :number, nullable: true },
          status: { type: :string, nullable: true },
          grader_comment: { type: :string, nullable: true },
          compiler_message: { type: :string, nullable: true },
          max_runtime: { type: :number, nullable: true },
          peak_memory: { type: :integer, nullable: true },
          number: { type: :integer },
          evaluations: {
            type: :array, items: {
              type: :object, additionalProperties: false, properties: {
                testcase_id: { type: :integer },
                result: { type: :string, nullable: true },
                score: { type: :number, nullable: true },
                time: { type: :integer, nullable: true },
                memory: { type: :integer, nullable: true }
              }
            }
          }
        }, required: %w[id problem_id language submitted_at]

        let(:id) { submissions(:add1_by_admin).id }

        before { submissions(:add1_by_admin).update_columns(points: 50.5) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["problem_name"]).to eq("add")
          expect(data["points"]).to eq(50.5)
        end
      end

      response "404", "submission not found" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:id) { 999999 }

        run_test!
      end
    end
  end
end
