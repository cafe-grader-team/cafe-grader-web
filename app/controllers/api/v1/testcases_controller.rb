class Api::V1::TestcasesController < Api::V1::BaseController
  before_action :set_testcase, only: [:input, :sol, :update, :destroy]
  before_action :authorize_testcase!, only: [:input, :sol]
  before_action :require_editor!, only: [:create, :update, :destroy]
  before_action :set_dataset_for_create, only: [:create]
  before_action :authorize_edit!, only: [:update, :destroy]

  # GET /api/v1/testcases/:id/input
  def input
    send_data @testcase.inp_file.download,
      type: "text/plain",
      filename: "#{@problem.name}.#{@testcase.num}.in"
  end

  # GET /api/v1/testcases/:id/sol
  def sol
    send_data @testcase.ans_file.download,
      type: "text/plain",
      filename: "#{@problem.name}.#{@testcase.num}.sol"
  end

  # POST /api/v1/datasets/:dataset_id/testcases
  # content arrives as top-level input/sol params — file uploads or plain text
  def create
    input_content = extract_content(:input)
    sol_content = extract_content(:sol)
    unless input_content && sol_content
      render json: { error: "Validation failed",
                     details: ["input and sol are required (as file uploads or text fields)"] },
             status: :unprocessable_entity and return
    end

    @testcase = @dataset.testcases.new(testcase_params)
    @testcase.num ||= (@dataset.testcases.maximum(:num) || 0) + 1
    attach_content(@testcase, input_content, sol_content)

    if @testcase.save
      # workers cache testcase files per dataset; force a re-download
      @dataset.invalidate_worker
      render json: testcase_json(@testcase), status: :created
    else
      render_validation_errors(@testcase)
    end
  end

  # PATCH /api/v1/testcases/:id — metadata and/or content replacement
  def update
    input_content = extract_content(:input)
    sol_content = extract_content(:sol)

    if @testcase.update(testcase_params)
      if input_content || sol_content
        attach_content(@testcase, input_content, sol_content)
        @testcase.dataset.invalidate_worker
      end
      render json: testcase_json(@testcase)
    else
      render_validation_errors(@testcase)
    end
  end

  # DELETE /api/v1/testcases/:id
  def destroy
    @testcase.destroy
    @testcase.dataset.invalidate_worker
    head :no_content
  end

  private

  def set_testcase
    @testcase = Testcase.find(params[:id])
    @problem = @testcase.dataset.problem
  rescue ActiveRecord::RecordNotFound
    # the most common mistake is passing the per-problem `num` as {id}
    render_not_found("Testcase",
                     hint: "Use the global `id` from GET /api/v1/problems/{problem_id}/testcases, " \
                           "not the per-problem `num`. The solution file is at /api/v1/testcases/{id}/sol.")
  end

  def set_dataset_for_create
    @dataset = Dataset.find(params[:dataset_id])
    @problem = @dataset.problem
    authorize_edit!
  rescue ActiveRecord::RecordNotFound
    render_not_found("Dataset")
  end

  def authorize_testcase!
    unless current_user.can_view_testcase?(@problem)
      render json: { error: "You are not allowed to view this testcase" }, status: :forbidden
    end
  end

  def authorize_edit!
    return true if current_user.can_edit_problem?(@problem)
    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  def testcase_params
    params.fetch(:testcase, {}).permit(:num, :group, :group_name, :weight, :code_name)
  end

  # uploaded file or plain string; CRLF-normalized like ProblemImporter
  def extract_content(key)
    raw = params[key]
    return nil if raw.blank?
    content = raw.respond_to?(:read) ? raw.read : raw.to_s
    content.gsub(/\r$/, "")
  end

  # mirrors ProblemImporter#import_dataset_from_dir's attachment shape
  def attach_content(testcase, input_content, sol_content)
    if input_content
      testcase.inp_file.attach(io: StringIO.new(input_content), filename: "input.txt",
                               content_type: "text/plain", identify: false)
    end
    if sol_content
      testcase.ans_file.attach(io: StringIO.new(sol_content), filename: "answer.txt",
                               content_type: "text/plain", identify: false)
    end
  end

  def testcase_json(testcase)
    {
      id: testcase.id,
      dataset_id: testcase.dataset_id,
      problem_id: testcase.dataset.problem_id,
      num: testcase.num,
      group: testcase.group,
      group_name: testcase.group_name,
      weight: testcase.weight,
      code_name: testcase.code_name
    }
  end
end
