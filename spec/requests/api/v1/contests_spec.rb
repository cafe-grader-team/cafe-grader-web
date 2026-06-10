require "swagger_helper"

RSpec.describe "Contests API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :contests, :contests_users, :contests_problems,
           :problems, :datasets, :groups, :groups_users, :groups_problems,
           :tags, :submissions, :languages

  path "/api/v1/contests/{id}" do
    get "Get contest info" do
      tags "Contests"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "contest found" do
        schema type: :object, additionalProperties: false, properties: {
          id: { type: :integer },
          name: { type: :string },
          description: { type: :string, nullable: true },
          start: { type: :string, format: "date-time", nullable: true },
          stop: { type: :string, format: "date-time", nullable: true },
          finalized: { type: :boolean },
          status: { type: :string }
        }, required: %w[id name]

        let(:id) { contests(:contest_a).id }
        let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["name"]).to eq("contest_a")
        end
      end

      response "404", "contest not found or not accessible" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:id) { 999999 }
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }

        run_test!
      end
    end
  end

  path "/api/v1/contests/{id}/problems" do
    get "List problems in a contest" do
      tags "Contests"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "problems list" do
        schema type: :array, items: {
          type: :object, additionalProperties: false, properties: {
            id: { type: :integer },
            name: { type: :string },
            full_name: { type: :string },
            difficulty: { type: :integer, nullable: true },
            tags: { type: :array, items: { type: :string } },
            submission_count: { type: :integer },
            best_score: { type: :number, nullable: true },
            last_score: { type: :number, nullable: true },
            last_result: { type: :string, nullable: true },
            last_submission_time: { type: :string, format: "date-time", nullable: true },
            last_submission_id: { type: :integer, nullable: true, description: "Id of the user's latest submission for this problem — fetch details via /api/v1/submissions/{id}" },
            has_testcase: { type: :boolean },
            has_attachment: { type: :boolean },
            permitted_languages: {
              type: :array, nullable: true,
              items: {
                type: :object, additionalProperties: false,
                properties: { id: { type: :integer }, name: { type: :string }, ext: { type: :string } }
              },
              description: "Allowed languages, or null if all are allowed"
            }
          }
        }

        let(:id) { contests(:contest_a).id }
        let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }

        # non-nil points so the score fields are exercised as JSON numbers
        before { submissions(:add1_by_admin).update_columns(points: 50.5) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          expect(data.map { |p| p["name"] }).to include("add")

          add = data.find { |p| p["name"] == "add" }
          expect(add["best_score"]).to eq(50.5)
          expect(add["last_score"]).to eq(50.5)
          expect(add["last_submission_id"]).to eq(submissions(:add1_by_admin).id)
        end
      end
    end
  end
end
