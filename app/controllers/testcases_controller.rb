class TestcasesController < ApplicationController
  before_action :set_testcase, only: [:download_input, :download_sol]
  before_action :set_problem, only: [:show_problem, :download_manager]
  before_action :testcase_authorization

  def download_input
    send_data @testcase.inp_file.download, type: 'text/plain', filename: "#{@testcase.dataset.problem.name}.#{@testcase.num}.in"
  end

  def download_sol
    send_data @testcase.ans_file.download, type: 'text/plain', filename: "#{@testcase.dataset.problem.name}.#{@testcase.num}.sol"
  end

  # can only download the live dataset managers
  def download_manager
    mg = @dataset.managers.find(params[:mg_id])

    send_data mg.download, type: 'text/plain', filename: "#{mg.filename}"
  end

  def show_problem
    @problem = Problem.includes(:testcases).find(params[:problem_id])
    @managers = @problem.live_dataset.managers
    unless @current_user.admin? or @problem.view_testcase
      flash[:error] = 'You cannot view the testcase of this problem'
      redirect_to controller: 'main', action: 'list'
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_testcase
      @testcase = Testcase.find(params[:id])
      @problem = @testcase.dataset.problem
    end

    def set_problem
      @problem = Problem.find(params[:problem_id])
      @dataset = @problem.live_dataset
    end

    # Only allow a trusted parameter "white list" through.
    def testcase_params
      params[:testcase]
    end

    def testcase_authorization
      # admin always has privileged
      unauthorized_redirect unless @current_user&.can_view_testcase?(@problem)
    end
end
