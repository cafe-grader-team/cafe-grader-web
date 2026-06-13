require "swagger_helper"

RSpec.describe "Problems API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :submissions, :languages, :tags

  let(:user) { users(:admin) }
  let(:Authorization) { "Bearer #{jwt_token_for(user)}" }

  path "/api/v1/problems" do
    get "List all accessible problems" do
      tags "Problems"
      produces "application/json"
      security [bearer: []]

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

        # non-nil points so the schema actually exercises the score types
        # (points is DECIMAL/BigDecimal — regression: encoded as string "50.5")
        before { submissions(:add1_by_admin).update_columns(points: 50.5) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          names = data.map { |p| p["name"] }
          expect(names).to include("add")
          expect(names).not_to include("subtract") # not available

          add = data.find { |p| p["name"] == "add" }
          expect(add["best_score"]).to eq(50.5)
          expect(add["last_score"]).to eq(50.5)
          expect(add["last_submission_id"]).to eq(submissions(:add1_by_admin).id)
        end
      end
    end
  end

  path "/api/v1/problems/{id}" do
    get "Get problem detail" do
      tags "Problems"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "problem detail" do
        schema type: :object, additionalProperties: false, properties: {
          id: { type: :integer },
          name: { type: :string },
          full_name: { type: :string },
          full_score: { type: :integer, nullable: true },
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
          },
          submission_ids: { type: :array, items: { type: :integer } }
        }, required: %w[id name full_name submission_count submission_ids]

        let(:id) { problems(:prob_add).id }

        before { submissions(:add1_by_admin).update_columns(points: 50.5) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["name"]).to eq("add")
          expect(data["submission_ids"]).to be_an(Array)
          expect(data["best_score"]).to eq(50.5)
          expect(data["last_score"]).to eq(50.5)
          expect(data["last_submission_id"]).to eq(submissions(:add1_by_admin).id)
        end
      end

      response "404", "problem not found" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:id) { 999999 }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}/description" do
    get "Get problem description (markdown)" do
      tags "Problems"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "description returned" do
        schema type: :object, additionalProperties: false, properties: {
          markdown: { type: :boolean },
          description: { type: :string, nullable: true }
        }

        let(:id) { problems(:prob_add).id }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}/files/{type}" do
    get "Get problem file by type" do
      tags "Problems"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true
      parameter name: :type, in: :path, type: :string, required: true,
        enum: %w[pdf attachment checker manager],
        description: "File type to retrieve"

      response "404", "file not found" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:id) { problems(:prob_add).id }
        let(:type) { "pdf" }

        run_test!
      end

      response "400", "unknown file type" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:id) { problems(:prob_add).id }
        let(:type) { "unknown" }

        run_test!
      end

      response "403", "viva problem PDF blocked for students" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        # The PDF on a viva problem is the interviewer's brief, not
        # student-facing. Mirror of ProblemsController#download_by_type
        # web-side gate. Admins/editors/reporters still get the file.
        let(:user) { users(:john) }
        let(:id) { problems(:prob_viva).id }
        let(:type) { "pdf" }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}/testcases" do
    get "List testcase metadata for a problem" do
      tags "Problems"
      produces "application/json"
      security [bearer: []]

      parameter name: :id, in: :path, type: :integer, required: true

      response "200", "testcase metadata list" do
        schema type: :array, items: {
          type: :object, additionalProperties: false, properties: {
            id: { type: :integer, description: "Global testcase id — pass this as {id} to /api/v1/testcases/{id}/input and /api/v1/testcases/{id}/sol" },
            num: { type: :integer, description: "Display number within the problem (1, 2, 3, …) — not usable as {id} for the download endpoints" },
            group: { type: :integer, nullable: true, description: "Testcase group number" },
            group_name: { type: :string, nullable: true, description: "Testcase group name" },
            weight: { type: :integer, nullable: true, description: "Score weight of this testcase" }
          },
          required: %w[id num]
        }

        let(:id) { problems(:prob_add).id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body.length).to eq(2)
          expect(body.map { |t| t["num"] }).to eq([1, 2])
          expect(body.map { |t| t["id"] }).to all(be_a(Integer))
        end
      end

      response "403", "testcase viewing not allowed" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        # right.view_testcase is false in fixtures
        let(:user) { users(:john) }
        let(:id) { problems(:prob_add).id }

        run_test!
      end
    end
  end
end
