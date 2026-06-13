require "swagger_helper"

RSpec.describe "Testcases write API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites,
           :problems, :datasets, :testcases,
           :groups, :groups_users, :groups_problems,
           :contests, :contests_users, :contests_problems,
           :languages

  let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }
  let(:dataset) { datasets(:ds_add) }

  path "/api/v1/datasets/{dataset_id}/testcases" do
    parameter name: :dataset_id, in: :path, type: :integer, required: true

    let(:dataset_id) { dataset.id }

    post "Add a testcase" do
      tags "Testcases (manage)"
      description "input/sol accept file uploads or plain-text fields (CRLF is normalized to LF, " \
                  "matching the zip importer). num defaults to the next free number. " \
                  "Workers' cached copy of the dataset is invalidated."
      consumes "multipart/form-data"
      produces "application/json"
      security [bearer: []]

      parameter name: :input, in: :formData, type: :file, required: true,
                description: "Input data (file or text field)"
      parameter name: :sol, in: :formData, type: :file, required: true,
                description: "Expected output (file or text field)"
      parameter name: "testcase[num]", in: :formData, type: :integer, required: false
      parameter name: "testcase[group]", in: :formData, type: :integer, required: false
      parameter name: "testcase[group_name]", in: :formData, type: :string, required: false
      parameter name: "testcase[weight]", in: :formData, type: :integer, required: false
      parameter name: "testcase[code_name]", in: :formData, type: :string, required: false

      response "201", "testcase created" do
        schema "$ref" => "#/components/schemas/TestcaseAdmin"

        let(:input) { "5 5\r\n" } # CRLF on purpose
        let(:sol) { "10\n" }
        let(:"testcase[group]") { 2 }
        let(:"testcase[weight]") { 25 }
        let(:"testcase[code_name]") { "api_case" }

        before do
          WorkerDataset.create!(dataset_id: datasets(:ds_add).id, worker_id: 1,
                                testcases_status: :ready, managers_status: :ready)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["num"]).to eq(3) # fixtures have num 1 and 2
          expect(data["group"]).to eq(2)
          expect(data["weight"]).to eq(25)

          tc = Testcase.find(data["id"])
          expect(tc.inp_file.download).to eq("5 5\n") # CRLF normalized
          expect(tc.ans_file.download).to eq("10\n")

          # workers must re-download the dataset
          expect(WorkerDataset.where(dataset_id: datasets(:ds_add).id)).to be_empty

          log = AuditLog.find_by(auditable_type: "Testcase", auditable_id: tc.id, action: "create")
          expect(log&.user_id).to eq(users(:admin).id)
        end
      end

      response "422", "missing content" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:input) { "5 5\n" }
        let(:sol) { nil }

        run_test!
      end

      response "403", "not an editor", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:input) { "x" }
        let(:sol) { "y" }

        run_test!
      end

      response "404", "unknown dataset" do
        schema "$ref" => "#/components/schemas/Error"

        let(:dataset_id) { 999_999 }
        let(:input) { "x" }
        let(:sol) { "y" }

        run_test!
      end
    end
  end

  path "/api/v1/testcases/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    patch "Update a testcase" do
      tags "Testcases (manage)"
      description "Metadata, and/or content replacement via the input/sol fields. " \
                  "Content changes invalidate workers' cached dataset; metadata-only changes don't need to " \
                  "(scoring reads the database)."
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/TestcasePayload" }

      response "200", "testcase updated" do
        schema "$ref" => "#/components/schemas/TestcaseAdmin"

        let(:id) { testcases(:tc_add_1).id }
        let(:payload) { { testcase: { weight: 70, group_name: "subtask1" } } }

        before do
          WorkerDataset.create!(dataset_id: datasets(:ds_add).id, worker_id: 1)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["weight"]).to eq(70)
          expect(data["group_name"]).to eq("subtask1")
          # metadata-only change: no need to re-download testcase files
          expect(WorkerDataset.where(dataset_id: datasets(:ds_add).id)).to be_present
        end
      end

      response "200", "content replacement invalidates worker cache", document: false do
        let(:id) { testcases(:tc_add_1).id }
        let(:payload) { { input: "100 200\r\n", sol: "300\n" } }

        before do
          WorkerDataset.create!(dataset_id: datasets(:ds_add).id, worker_id: 1)
        end

        run_test! do
          tc = testcases(:tc_add_1).reload
          expect(tc.inp_file.download).to eq("100 200\n")
          expect(tc.ans_file.download).to eq("300\n")
          expect(WorkerDataset.where(dataset_id: datasets(:ds_add).id)).to be_empty
        end
      end

      response "403", "not an editor" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { testcases(:tc_add_1).id }
        let(:payload) { { testcase: { weight: 1 } } }

        run_test!
      end

      response "404", "unknown testcase" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { 999_999 }
        let(:payload) { { testcase: { weight: 1 } } }

        run_test!
      end
    end

    delete "Delete a testcase" do
      tags "Testcases (manage)"
      produces "application/json"
      security [bearer: []]

      response "204", "testcase deleted" do
        let(:id) { testcases(:tc_add_2).id }

        before do
          WorkerDataset.create!(dataset_id: datasets(:ds_add).id, worker_id: 1)
        end

        run_test! do
          expect(Testcase.exists?(testcases(:tc_add_2).id)).to be(false)
          expect(WorkerDataset.where(dataset_id: datasets(:ds_add).id)).to be_empty
        end
      end

      response "403", "not an editor", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { testcases(:tc_add_1).id }

        run_test!
      end
    end
  end

  path "/api/v1/problems/{id}/testcases/import" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Bulk-import testcases from a zip" do
      tags "Testcases (manage)"
      description "Zip of paired files matched by input_pattern/sol_pattern (defaults *.in / *.sol). " \
                  "Without dataset_id a new dataset is created (and becomes live if the problem had none); " \
                  "with dataset_id, cases with matching code names are replaced in that dataset. " \
                  "Emits one consolidated `import_testcases` audit row."
      consumes "multipart/form-data"
      produces "application/json"
      security [bearer: []]

      parameter name: :file, in: :formData, type: :file, required: true, description: "Zip archive"
      parameter name: :dataset_id, in: :formData, type: :integer, required: false,
                description: "Existing dataset to import into (omit to create a new dataset)"
      parameter name: :input_pattern, in: :formData, type: :string, required: false, description: "Default *.in"
      parameter name: :sol_pattern, in: :formData, type: :string, required: false, description: "Default *.sol"

      # keep importer extraction out of the real judge directory
      let(:raw_dir) { Dir.mktmpdir("api-import-raw") }
      before do
        worker_conf = Rails.configuration.worker.deep_dup
        worker_conf[:directory][:judge_raw_path] = raw_dir
        allow(Rails.configuration).to receive(:worker).and_return(worker_conf)
      end

      def build_zip(entries)
        dir = Dir.mktmpdir("api-import-zip")
        paths = entries.map do |name, content|
          File.join(dir, name).tap { |p| File.write(p, content) }
        end
        zip_path = File.join(dir, "import.zip")
        system("zip", "-j", "-q", zip_path, *paths, exception: true)
        Rack::Test::UploadedFile.new(zip_path, "application/zip")
      end

      response "200", "testcases imported into a new dataset" do
        schema type: :object, additionalProperties: false, properties: {
          problem_id: { type: :integer },
          dataset_id: { type: :integer, nullable: true },
          dataset_name: { type: :string, nullable: true },
          testcase_count: { type: :integer },
          log: { type: :array, items: { type: :string } }
        }, required: %w[problem_id testcase_count log]

        let(:id) { problems(:prob_add).id }
        let(:file) { build_zip("1.in" => "1 1\n", "1.sol" => "2\n", "2.in" => "3 4\n", "2.sol" => "7\n") }
        let(:dataset_id) { nil }
        let(:input_pattern) { nil }
        let(:sol_pattern) { nil }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["testcase_count"]).to eq(2)
          expect(data["dataset_id"]).not_to eq(datasets(:ds_add).id) # new dataset

          # consolidated audit: one semantic row on the problem, no per-testcase cascade
          expect(AuditLog.where(auditable_type: "Problem",
                                auditable_id: problems(:prob_add).id,
                                action: "import_testcases").count).to eq(1)
          new_tc_ids = Dataset.find(data["dataset_id"]).testcases.ids
          expect(AuditLog.where(auditable_type: "Testcase", auditable_id: new_tc_ids)).to be_empty
        end
      end

      response "422", "not a valid zip" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:id) { problems(:prob_add).id }
        let(:file) do
          f = Tempfile.new(["broken", ".zip"])
          f.write("this is not a zip")
          f.rewind
          Rack::Test::UploadedFile.new(f.path, "application/zip")
        end
        let(:dataset_id) { nil }
        let(:input_pattern) { nil }
        let(:sol_pattern) { nil }

        run_test!
      end

      response "422", "missing file", document: false do
        let(:id) { problems(:prob_add).id }
        let(:file) { nil }
        let(:dataset_id) { nil }
        let(:input_pattern) { nil }
        let(:sol_pattern) { nil }

        run_test!
      end

      response "403", "not an editor", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:id) { problems(:prob_add).id }
        let(:file) { build_zip("1.in" => "1\n", "1.sol" => "1\n") }
        let(:dataset_id) { nil }
        let(:input_pattern) { nil }
        let(:sol_pattern) { nil }

        run_test!
      end
    end
  end
end
