require "swagger_helper"

RSpec.describe "Languages API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites, :languages

  path "/api/v1/languages" do
    get "List all available languages" do
      tags "Languages"
      produces "application/json"
      security [bearer: []]

      response "200", "languages list" do
        schema type: :array, items: {
          type: :object, additionalProperties: false, properties: {
            id: { type: :integer },
            name: { type: :string },
            pretty_name: { type: :string },
            ext: { type: :string }
          }, required: %w[id name pretty_name ext]
        }

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          expect(data.map { |l| l["name"] }).to include("cpp", "python")
        end
      end
    end
  end
end
