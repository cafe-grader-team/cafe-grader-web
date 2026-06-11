require "swagger_helper"

RSpec.describe "Auth API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites

  path "/api/v1/auth/login" do
    post "Log in and receive a JWT token" do
      tags "Auth"
      consumes "application/json"
      produces "application/json"

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          login: { type: :string, description: "Username" },
          password: { type: :string, description: "Password" }
        },
        required: %w[login password]
      }

      response "200", "login successful" do
        schema type: :object, additionalProperties: false, properties: {
          token: { type: :string, description: "JWT token" },
          expires_at: { type: :string, format: "date-time",
                        description: "Token expiry (#{Api::V1::AuthController::TOKEN_TTL.inspect} after issue); re-login to obtain a fresh token" },
          user: {
            type: :object, additionalProperties: false,
            properties: {
              id: { type: :integer },
              login: { type: :string },
              full_name: { type: :string }
            }
          }
        }, required: %w[token expires_at user]

        let(:body) { { login: "admin", password: "admin" } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["token"]).to be_present
          expect(data["user"]["login"]).to eq("admin")
          expect(Time.zone.parse(data["expires_at"]))
            .to be_within(1.minute).of(Api::V1::AuthController::TOKEN_TTL.from_now)
        end
      end

      response "401", "invalid credentials" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        let(:body) { { login: "admin", password: "wrong" } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("Invalid login or password")
        end
      end

      response "403", "account disabled" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        before { users(:john).update!(enabled: false) }
        let(:body) { { login: "john", password: "hello" } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to eq("Account is disabled")
        end
      end

      response "429", "too many login attempts (rate limited per client IP)" do
        schema type: :object, additionalProperties: false, properties: { error: { type: :string } }

        # The test cache is a NullStore, so the limiter never accumulates;
        # force the counter past the limit to exercise the 429 path. The
        # rate_limit macro captured the controller's cache_store at class
        # load, so stub that exact object.
        before do
          allow(Api::V1::AuthController.cache_store)
            .to receive(:increment).and_return(999)
        end
        let(:body) { { login: "admin", password: "admin" } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to match(/Too many login attempts/)
        end
      end
    end
  end
end
