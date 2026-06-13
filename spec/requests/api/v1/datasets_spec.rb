require "swagger_helper"

RSpec.describe "Datasets API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :languages

  let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }
  let(:problem) { problems(:prob_add) }

  def upload_file(name, content, content_type)
    file = Tempfile.new(name)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type)
  end

  path "/api/v1/problems/{problem_id}/datasets" do
    parameter name: :problem_id, in: :path, type: :integer, required: true

    get "List a problem's datasets" do
      tags "Datasets"
      description "Editor view: every dataset of the problem with settings, files and live flag."
      produces "application/json"
      security [bearer: []]

      response "200", "datasets listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/DatasetAdmin" }

        let(:problem_id) { problem.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.length).to eq(1)
          ds = data.first
          expect(ds["name"]).to eq("Dataset 1")
          expect(ds["live"]).to eq(true)
          expect(ds["testcase_count"]).to eq(2)
          expect(ds["time_limit"]).to eq(1.0)
        end
      end

      response "403", "not an editor of this problem" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:problem_id) { problem.id }

        run_test!
      end

      response "404", "unknown problem" do
        schema "$ref" => "#/components/schemas/Error"

        let(:problem_id) { 999_999 }

        run_test!
      end
    end

    post "Create a dataset" do
      tags "Datasets"
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/DatasetPayload" }

      response "201", "dataset created" do
        schema "$ref" => "#/components/schemas/DatasetAdmin"

        let(:problem_id) { problem.id }
        let(:payload) { { dataset: { time_limit: 2.5, memory_limit: 64, score_type: "group_min" } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["name"]).to eq("Dataset 2") # auto-named
          expect(data["live"]).to eq(false)       # creating never steals the live pointer
          expect(data["time_limit"]).to eq(2.5)
          expect(data["score_type"]).to eq("group_min")

          log = AuditLog.find_by(auditable_type: "Dataset", auditable_id: data["id"], action: "create")
          expect(log&.user_id).to eq(users(:admin).id)
        end
      end

      response "422", "invalid enum value", document: false do
        let(:problem_id) { problem.id }
        let(:payload) { { dataset: { evaluation_type: "bogus" } } }

        run_test!
      end

      response "403", "not an editor", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:problem_id) { problem.id }
        let(:payload) { { dataset: {} } }

        run_test!
      end
    end
  end

  path "/api/v1/datasets/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    patch "Update dataset settings" do
      tags "Datasets"
      description "JSON settings only — upload files via POST /datasets/{id}/files."
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/DatasetPayload" }

      response "200", "dataset updated" do
        schema "$ref" => "#/components/schemas/DatasetAdmin"

        let(:id) { datasets(:ds_add).id }
        let(:payload) { { dataset: { time_limit: 3.5, memory_limit: 1024 } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["time_limit"]).to eq(3.5)
          expect(data["memory_limit"]).to eq(1024)
        end
      end

      response "404", "unknown dataset" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { 999_999 }
        let(:payload) { { dataset: { time_limit: 1 } } }

        run_test!
      end

      response "403", "not an editor", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { datasets(:ds_add).id }
        let(:payload) { { dataset: { time_limit: 1 } } }

        run_test!
      end
    end

    delete "Delete a dataset" do
      tags "Datasets"
      description "Refused (409) for the live dataset and for the problem's only dataset."
      produces "application/json"
      security [bearer: []]

      response "204", "dataset deleted" do
        let(:extra) { problem.datasets.create!(name: "Doomed") }
        let(:id) { extra.id }

        run_test! do
          expect(Dataset.exists?(extra.id)).to be(false)
        end
      end

      response "409", "cannot delete the live dataset" do
        schema "$ref" => "#/components/schemas/Error"

        before { problem.datasets.create!(name: "Backup") } # so 'live', not 'last', triggers
        let(:id) { datasets(:ds_add).id }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to match(/live dataset/)
        end
      end

      response "409", "cannot delete the only dataset", document: false do
        let(:id) { datasets(:ds_sub).id }

        before { problems(:prob_sub).update!(live_dataset: nil) }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to match(/last remaining/)
        end
      end
    end
  end

  path "/api/v1/datasets/{id}/set_live" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Make this the live (grading) dataset" do
      tags "Datasets"
      produces "application/json"
      security [bearer: []]

      response "200", "live dataset switched" do
        schema "$ref" => "#/components/schemas/DatasetAdmin"

        let(:extra) { problem.datasets.create!(name: "Next gen") }
        let(:id) { extra.id }

        run_test! do |response|
          expect(JSON.parse(response.body)["live"]).to eq(true)
          expect(problem.reload.live_dataset).to eq(extra)

          # live_dataset_id is in Problem's audited attributes
          log = AuditLog.where(auditable_type: "Problem", auditable_id: problem.id, action: "update").last
          expect(log).to be_present
        end
      end
    end
  end

  path "/api/v1/datasets/{id}/files" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Upload dataset files" do
      tags "Datasets"
      description "Attach a checker and/or compile/run support files. Workers' cached copies are invalidated."
      consumes "multipart/form-data"
      produces "application/json"
      security [bearer: []]

      parameter name: :checker, in: :formData, type: :file, required: false,
                description: "Custom checker script (used with custom_* evaluation types)"
      parameter name: :managers, in: :formData, type: :array, items: { type: :string, format: :binary }, required: false,
                description: "Compile-time files visible to the submission (e.g. grader main)"
      parameter name: :data_files, in: :formData, type: :array, items: { type: :string, format: :binary }, required: false,
                description: "Extra files present when running"
      parameter name: :initializers, in: :formData, type: :array, items: { type: :string, format: :binary }, required: false,
                description: "Testcase initialization files"

      response "200", "files attached" do
        schema "$ref" => "#/components/schemas/DatasetAdmin"

        let(:id) { datasets(:ds_add).id }
        let(:checker) { upload_file(["checker", ".rb"], "puts 'CORRECT'", "text/plain") }
        let(:managers) { [upload_file(["main", ".cpp"], "int main(){}", "text/plain")] }
        let(:data_files) { nil }
        let(:initializers) { nil }

        before do
          WorkerDataset.create!(dataset_id: datasets(:ds_add).id, worker_id: 1,
                                testcases_status: :ready, managers_status: :ready)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["files"]["checker"]["filename"]).to match(/checker/)
          expect(data["files"]["managers"].length).to eq(1)
          # attaching managers derives main_filename
          expect(data["main_filename"]).to match(/main/)
          # workers' cache invalidated so they re-download
          expect(WorkerDataset.where(dataset_id: datasets(:ds_add).id)).to be_empty
        end
      end

      response "422", "no files given" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:id) { datasets(:ds_add).id }
        let(:checker) { nil }
        let(:managers) { nil }
        let(:data_files) { nil }
        let(:initializers) { nil }

        run_test!
      end
    end
  end

  path "/api/v1/datasets/{id}/files/{attachment_id}" do
    parameter name: :id, in: :path, type: :integer, required: true
    parameter name: :attachment_id, in: :path, type: :integer, required: true

    delete "Delete a dataset file" do
      tags "Datasets"
      description "attachment_id comes from the files section of the dataset JSON."
      produces "application/json"
      security [bearer: []]

      response "200", "file removed" do
        schema "$ref" => "#/components/schemas/DatasetAdmin"

        let(:id) { datasets(:ds_add).id }
        let(:attachment_id) do
          datasets(:ds_add).data_files.attach(upload_file(["data", ".txt"], "x", "text/plain"))
          datasets(:ds_add).data_files.attachments.last.id
        end

        run_test! do |response|
          expect(JSON.parse(response.body)["files"]["data_files"]).to be_empty
        end
      end

      response "404", "unknown attachment" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { datasets(:ds_add).id }
        let(:attachment_id) { 999_999 }

        run_test!
      end
    end
  end
end
