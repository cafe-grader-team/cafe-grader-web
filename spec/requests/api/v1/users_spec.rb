require "swagger_helper"

RSpec.describe "Users API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites

  path "/api/v1/me" do
    get "Get current user profile" do
      tags "User"
      produces "application/json"
      security [bearer: []]

      response "200", "user profile" do
        schema type: :object, additionalProperties: false, properties: {
          id: { type: :integer },
          login: { type: :string },
          full_name: { type: :string },
          alias: { type: :string, nullable: true },
          email: { type: :string, nullable: true },
          section: { type: :string, nullable: true },
          remark: { type: :string, nullable: true },
          admin: { type: :boolean }
        }, required: %w[id login full_name admin]

        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["login"]).to eq("john")
          expect(data["admin"]).to be false
        end
      end

      response "401", "missing or invalid token" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:Authorization) { "Bearer invalid_token" }

        run_test!
      end
    end
  end
end
