require "swagger_helper"

RSpec.describe "Users admin API", type: :request do
  fixtures :users, :roles, :grader_configurations, :sites, :groups, :groups_users

  let(:Authorization) { "Bearer #{jwt_token_for(users(:admin))}" }

  path "/api/v1/users" do
    get "List users" do
      tags "Users (admin)"
      produces "application/json"
      security [bearer: []]

      parameter name: :q, in: :query, type: :string, required: false,
                description: "Substring filter on login or full name"
      parameter name: :page, in: :query, type: :integer, required: false, description: "1-based (default 1)"
      parameter name: :per_page, in: :query, type: :integer, required: false, description: "Default 50, max 200"

      let(:q) { nil }
      let(:page) { nil }
      let(:per_page) { nil }

      response "200", "users listed" do
        schema type: :object, additionalProperties: false, properties: {
          users: { type: :array, items: { "$ref" => "#/components/schemas/UserAdmin" } },
          meta: {
            type: :object, additionalProperties: false,
            properties: {
              page: { type: :integer },
              per_page: { type: :integer },
              total: { type: :integer }
            },
            required: %w[page per_page total]
          }
        }, required: %w[users meta]

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["meta"]["total"]).to eq(User.count)
          expect(data["users"].map { |u| u["login"] }).to include("admin", "john")
          admin = data["users"].find { |u| u["login"] == "admin" }
          expect(admin["roles"]).to include("admin")
        end
      end

      response "200", "filtered and paginated", document: false do
        let(:q) { "mar" }
        let(:per_page) { 1 }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["users"].map { |u| u["login"] }).to eq(["mary"])
          expect(data["meta"]["total"]).to eq(1)
        end
      end

      response "403", "not an admin" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:mary))}" }

        run_test!
      end
    end

    post "Create a user" do
      tags "Users (admin)"
      description "The account is created activated (mirrors the web admin form)."
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/UserPayload" }

      response "201", "user created" do
        schema "$ref" => "#/components/schemas/UserAdmin"

        let(:payload) do
          { user: { login: "new_student", full_name: "New Student",
                    password: "s3cret", password_confirmation: "s3cret",
                    group_ids: [groups(:group_a).id] } }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["group_ids"]).to eq([groups(:group_a).id])

          user = User.find(data["id"])
          expect(user.activated).to be(true)
          expect(User.authenticate("new_student", "s3cret")).to eq(user)
        end
      end

      response "422", "validation failure (duplicate login, short password, ...)" do
        schema "$ref" => "#/components/schemas/ValidationError"

        let(:payload) { { user: { login: "john", full_name: "Dup", password: "x", password_confirmation: "x" } } }

        run_test!
      end

      response "403", "not an admin", document: false do
        let(:Authorization) { "Bearer #{jwt_token_for(users(:john))}" }
        let(:payload) { { user: { login: "sneaky", full_name: "Sneaky" } } }

        run_test!
      end
    end
  end

  path "/api/v1/users/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    get "Get a user" do
      tags "Users (admin)"
      produces "application/json"
      security [bearer: []]

      response "200", "user detail" do
        schema "$ref" => "#/components/schemas/UserAdmin"

        let(:id) { users(:mary).id }

        run_test! do |response|
          expect(JSON.parse(response.body)["login"]).to eq("mary")
        end
      end

      response "404", "unknown user" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { 999_999 }

        run_test!
      end
    end

    patch "Update a user" do
      tags "Users (admin)"
      consumes "application/json"
      produces "application/json"
      security [bearer: []]

      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/UserPayload" }

      response "200", "user updated" do
        schema "$ref" => "#/components/schemas/UserAdmin"

        let(:id) { users(:james).id }
        let(:payload) { { user: { full_name: "James Renamed", enabled: false } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["full_name"]).to eq("James Renamed")
          expect(data["enabled"]).to eq(false)
          # blank password not sent — credentials unchanged
          expect(User.authenticate("james", "morning")).to be_present
        end
      end

      response "200", "password change", document: false do
        let(:id) { users(:james).id }
        let(:payload) { { user: { password: "newpass", password_confirmation: "newpass" } } }

        run_test! do
          expect(User.authenticate("james", "newpass")).to eq(users(:james))
          expect(User.authenticate("james", "morning")).to be_nil
        end
      end

      response "422", "validation failure", document: false do
        let(:id) { users(:james).id }
        let(:payload) { { user: { password: "a", password_confirmation: "a" } } }

        run_test!
      end

      response "403", "not an admin" do
        schema "$ref" => "#/components/schemas/Error"

        let(:Authorization) { "Bearer #{jwt_token_for(users(:james))}" }
        let(:id) { users(:james).id }
        let(:payload) { { user: { full_name: "Self Serve" } } }

        run_test!
      end
    end

    delete "Delete a user" do
      tags "Users (admin)"
      description "Refused for your own account."
      produces "application/json"
      security [bearer: []]

      response "204", "user deleted" do
        let(:victim) do
          User.create!(login: "victim", full_name: "Victim",
                       password: "doomed", password_confirmation: "doomed",
                       activated: true)
        end
        let(:id) { victim.id }

        run_test! do
          expect(User.exists?(victim.id)).to be(false)
        end
      end

      response "422", "cannot delete yourself" do
        schema "$ref" => "#/components/schemas/Error"

        let(:id) { users(:admin).id }

        run_test!
      end
    end
  end
end
