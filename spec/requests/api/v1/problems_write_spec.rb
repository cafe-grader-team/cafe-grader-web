require "swagger_helper"

RSpec.describe "Problems write API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :submissions, :languages, :tags

  let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }

  path "/api/v1/problems" do
    post "Create a problem" do
      tags "Problems (manage)"
      description "Admin or group editor. Creates the problem together with a default dataset " \
                  "and live-dataset pointer (a dataset-less problem is invisible to manage views)."
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/ProblemPayload" }

      response "201", "problem created" do
        schema "$ref" => "#/components/schemas/ProblemAdmin"

        let(:payload) { { problem: { name: "api_created", description: "from API" } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["full_name"]).to eq("api_created") # defaults to name
          expect(data["available"]).to eq(false)         # default

          problem = Problem.find(data["id"])
          expect(problem.datasets.count).to eq(1)
          expect(problem.live_dataset).to eq(problem.datasets.first)

          # audit actor wiring (Current.user set by the API base controller)
          log = AuditLog.find_by(auditable_type: "Problem", auditable_id: problem.id, action: "create")
          expect(log).to be_present
          expect(log.user_id).to eq(users(:admin).id)
          expect(log.ip_address).to be_present
        end
      end

      response "201", "group editor creates a problem into their group", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:mary))}" }
        let(:payload) { { problem: { name: "editor_created", group_ids: [groups(:group_a).id] } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["group_ids"]).to eq([groups(:group_a).id])
        end
      end

      response "403", "not an editor" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:payload) { { problem: { name: "nope" } } }

        run_test!
      end

      response "422", "validation failure (e.g. duplicate name)" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:payload) { { problem: { name: "add" } } } # taken by fixture prob_add

        run_test! do |response|
          expect(JSON.parse(response.body)["details"].join).to match(/taken/)
        end
      end

      response "422", "unknown permitted language id", document: false do
        let(:payload) { { problem: { name: "lang_check", permitted_language_ids: [999_999] } } }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    patch "Update problem settings" do
      tags "Problems (manage)"
      description "Requires edit permission on the problem (admin, or group editor of one of its groups in group mode)."
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/ProblemPayload" }

      response "200", "problem updated" do
        schema "$ref" => "#/components/schemas/ProblemAdmin"

        let(:id) { problems(:prob_add).id }
        let(:payload) do
          { problem: { full_name: "Renamed via API", available: true,
                       permitted_language_ids: [languages(:Language_c).id] } }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["full_name"]).to eq("Renamed via API")
          expect(data["available"]).to eq(true)
          expect(data["permitted_languages"].map { |l| l["id"] }).to eq([languages(:Language_c).id])

          log = AuditLog.where(auditable_type: "Problem", auditable_id: id, action: "update").last
          expect(log).to be_present
          expect(log.user_id).to eq(users(:admin).id)
        end
      end

      response "200", "group editor can update problems of their groups", document: false do
        before { set_grader_config("system.use_problem_group", "true") }

        let(:Authorization) { "Bearer #{jwt_token_for(users(:mary))}" }
        let(:id) { problems(:prob_add).id }
        let(:payload) { { problem: { difficulty: 3 } } }

        run_test!
      end

      response "403", "no edit permission on this problem" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { problems(:prob_add).id }
        let(:payload) { { problem: { full_name: "hax" } } }

        run_test!
      end

      response "404", "unknown problem" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { 999_999 }
        let(:payload) { { problem: { full_name: "x" } } }

        run_test!
      end

      response "422", "validation failure", document: false do
        let(:id) { problems(:prob_add).id }
        let(:payload) { { problem: { name: "" } } }

        run_test!
      end
    end

    delete "Delete a problem" do
      tags "Problems (manage)"
      description "Destroys the problem with its datasets, testcases and submissions (mirrors the web admin action)."
      produces "application/json"
      security [bearer: []]

      response "204", "problem deleted" do
        let(:doomed) do
          Problem.create!(name: "doomed_prob", full_name: "Doomed", available: false)
        end
        let(:id) { doomed.id }

        run_test! do
          expect(Problem.exists?(doomed.id)).to be(false)
        end
      end

      response "403", "no edit permission" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { problems(:prob_add).id }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}/statement" do
    parameter name: :id, in: :path, type: :integer, required: true

    put "Upload or replace the statement PDF" do
      tags "Problems (manage)"
      consumes "multipart/form-data"
      produces "application/json"
      security [bearer: []]

      parameter name: :statement, in: :formData, type: :file, required: true,
                description: "PDF file (content type must be application/pdf)"

      let(:id) { problems(:prob_add).id }

      response "200", "statement uploaded" do
        schema "$ref" => "#/components/schemas/ProblemAdmin"

        let(:statement) do
          file = Tempfile.new(["statement", ".pdf"])
          file.write("%PDF-1.4\n%%EOF\n")
          file.rewind
          Rack::Test::UploadedFile.new(file.path, "application/pdf")
        end

        run_test! do |response|
          expect(JSON.parse(response.body)["has_statement"]).to eq(true)
          expect(problems(:prob_add).reload.statement).to be_attached
        end
      end

      response "422", "not a PDF" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:statement) do
          file = Tempfile.new(["statement", ".txt"])
          file.write("plain text")
          file.rewind
          Rack::Test::UploadedFile.new(file.path, "text/plain")
        end

        run_test!
      end
    end
  end
end
