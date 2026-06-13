require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Cafe Grader API",
        version: "v1",
        description: "API for the Cafe Grader online judge platform"
      },
      paths: {},
      servers: [
        { url: "{server}", variables: { server: { default: "https://your-server.example.com", description: "Server URL" } } }
      ],
      components: {
        securitySchemes: {
          bearer: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "JWT"
          }
        },
        schemas: {
          Error: {
            type: :object, additionalProperties: false,
            properties: {
              error: { type: :string },
              hint: { type: :string }
            },
            required: %w[error]
          },
          ValidationError: {
            type: :object, additionalProperties: false,
            properties: {
              error: { type: :string },
              details: { type: :array, items: { type: :string } }
            },
            required: %w[error]
          },
          Attachment: {
            type: :object, additionalProperties: false, nullable: true,
            properties: {
              id: { type: :integer, description: "Attachment id (use with the file delete endpoint)" },
              filename: { type: :string },
              byte_size: { type: :integer }
            },
            required: %w[id filename byte_size]
          },
          DatasetAdmin: {
            type: :object, additionalProperties: false,
            properties: {
              id: { type: :integer },
              problem_id: { type: :integer },
              name: { type: :string },
              live: { type: :boolean, description: "Whether this is the problem's live (grading) dataset" },
              time_limit: { type: :number, nullable: true, description: "Seconds" },
              memory_limit: { type: :integer, nullable: true, description: "MB" },
              score_type: { type: :string, enum: Dataset.score_types.keys },
              evaluation_type: { type: :string, enum: Dataset.evaluation_types.keys },
              score_param: { type: :string, nullable: true },
              main_filename: { type: :string, nullable: true },
              initializer_filename: { type: :string, nullable: true },
              testcase_count: { type: :integer },
              files: {
                type: :object, additionalProperties: false,
                properties: {
                  checker: { "$ref" => "#/components/schemas/Attachment" },
                  managers: { type: :array, items: { "$ref" => "#/components/schemas/Attachment" } },
                  data_files: { type: :array, items: { "$ref" => "#/components/schemas/Attachment" } },
                  initializers: { type: :array, items: { "$ref" => "#/components/schemas/Attachment" } }
                }
              }
            },
            required: %w[id problem_id name live score_type evaluation_type testcase_count files]
          },
          DatasetPayload: {
            type: :object,
            properties: {
              dataset: {
                type: :object,
                properties: {
                  name: { type: :string, description: "Defaults to the next free \"Dataset N\" on create" },
                  time_limit: { type: :number, description: "Seconds" },
                  memory_limit: { type: :integer, description: "MB" },
                  score_type: { type: :string, enum: Dataset.score_types.keys },
                  evaluation_type: { type: :string, enum: Dataset.evaluation_types.keys },
                  score_param: { type: :string },
                  main_filename: { type: :string },
                  initializer_filename: { type: :string }
                }
              }
            }
          },
          UserAdmin: {
            type: :object, additionalProperties: false,
            properties: {
              id: { type: :integer },
              login: { type: :string },
              full_name: { type: :string },
              alias: { type: :string, nullable: true },
              email: { type: :string, nullable: true },
              remark: { type: :string, nullable: true },
              enabled: { type: :boolean, nullable: true },
              activated: { type: :boolean, nullable: true },
              roles: { type: :array, items: { type: :string },
                       description: "Read-only: roles are granted via the web UI only" },
              group_ids: { type: :array, items: { type: :integer } }
            },
            required: %w[id login full_name roles group_ids]
          },
          UserPayload: {
            type: :object,
            properties: {
              user: {
                type: :object,
                properties: {
                  login: { type: :string, description: "3-30 chars, letters/digits/underscore" },
                  password: { type: :string, description: "4-50 chars. Blank on update keeps the current password." },
                  password_confirmation: { type: :string },
                  full_name: { type: :string },
                  email: { type: :string },
                  alias: { type: :string },
                  remark: { type: :string },
                  enabled: { type: :boolean, description: "Disabled users cannot log in or hold API tokens" },
                  group_ids: { type: :array, items: { type: :integer } }
                }
              }
            },
            required: %w[user]
          },
          TestcaseAdmin: {
            type: :object, additionalProperties: false,
            properties: {
              id: { type: :integer },
              dataset_id: { type: :integer },
              problem_id: { type: :integer },
              num: { type: :integer },
              group: { type: :integer, nullable: true },
              group_name: { type: :string, nullable: true },
              weight: { type: :integer, nullable: true },
              code_name: { type: :string, nullable: true }
            },
            required: %w[id dataset_id num]
          },
          TestcasePayload: {
            type: :object,
            properties: {
              testcase: {
                type: :object,
                properties: {
                  num: { type: :integer, description: "Defaults to the next free number on create. Display order is (group, num)." },
                  group: { type: :integer },
                  group_name: { type: :string },
                  weight: { type: :integer },
                  code_name: { type: :string }
                }
              },
              input: { type: :string, description: "Replacement input content (CRLF is normalized to LF)" },
              sol: { type: :string, description: "Replacement expected-output content" }
            }
          },
          ProblemPayload: {
            type: :object,
            properties: {
              problem: {
                type: :object,
                properties: {
                  name: { type: :string, description: "Short name (letters, numbers, ()[]-_ only); must be unique" },
                  full_name: { type: :string, description: "Display name (defaults to name on create)" },
                  available: { type: :boolean, description: "Visible/submittable for students (default false on create)" },
                  date_added: { type: :string, format: "date" },
                  test_allowed: { type: :boolean },
                  output_only: { type: :boolean },
                  difficulty: { type: :integer },
                  submission_filename: { type: :string },
                  compilation_type: { type: :string, enum: Problem.compilation_types.keys },
                  view_testcase: { type: :boolean },
                  view_submission: { type: :boolean },
                  markdown: { type: :boolean },
                  description: { type: :string },
                  url: { type: :string },
                  tag_ids: { type: :array, items: { type: :integer } },
                  group_ids: { type: :array, items: { type: :integer },
                               description: "Groups the problem belongs to. Editors keep edit access through their groups, so include one of yours." },
                  permitted_language_ids: { type: :array, items: { type: :integer },
                                            description: "Restrict submittable languages; empty array allows all" }
                }
              }
            },
            required: %w[problem]
          },
          ProblemAdmin: {
            type: :object, additionalProperties: false,
            description: "Management view of a problem (editor/admin endpoints)",
            properties: {
              id: { type: :integer },
              name: { type: :string },
              full_name: { type: :string },
              full_score: { type: :integer, nullable: true },
              available: { type: :boolean },
              test_allowed: { type: :boolean, nullable: true },
              output_only: { type: :boolean, nullable: true },
              view_testcase: { type: :boolean, nullable: true },
              view_submission: { type: :boolean, nullable: true },
              markdown: { type: :boolean, nullable: true },
              difficulty: { type: :integer, nullable: true },
              date_added: { type: :string, format: "date", nullable: true },
              url: { type: :string, nullable: true },
              description: { type: :string, nullable: true },
              submission_filename: { type: :string, nullable: true },
              compilation_type: { type: :string, enum: Problem.compilation_types.keys },
              live_dataset_id: { type: :integer, nullable: true },
              permitted_languages: {
                type: :array, nullable: true,
                items: {
                  type: :object, additionalProperties: false,
                  properties: { id: { type: :integer }, name: { type: :string }, ext: { type: :string } }
                },
                description: "Allowed languages, or null if all are allowed"
              },
              tag_ids: { type: :array, items: { type: :integer } },
              group_ids: { type: :array, items: { type: :integer } },
              has_statement: { type: :boolean },
              has_attachment: { type: :boolean }
            },
            required: %w[id name full_name available live_dataset_id]
          }
        }
      }
    }
  }

  config.openapi_format = :yaml
end
