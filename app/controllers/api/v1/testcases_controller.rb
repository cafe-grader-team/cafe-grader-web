class Api::V1::TestcasesController < Api::V1::BaseController
  before_action :set_testcase
  before_action :authorize_testcase!

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

  def authorize_testcase!
    unless current_user.can_view_testcase?(@problem)
      render json: { error: "You are not allowed to view this testcase" }, status: :forbidden
    end
  end
end
