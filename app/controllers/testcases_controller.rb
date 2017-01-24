class TestcasesController < ApplicationController
  before_action :set_testcase, only: [:download_input,:download_sol]
  before_action :testcase_authorization

  def download_input
    send_data @testcase.input, type: 'text/plain', filename: "#{@testcase.problem.name}.#{@testcase.num}.in"
  end

  def download_sol
    send_data @testcase.sol, type: 'text/plain', filename: "#{@testcase.problem.name}.#{@testcase.num}.sol"
  end

  def show_problem
    @problem = Problem.includes(:testcases).find(params[:problem_id])
    unless @current_user.admin? or @problem.view_testcase
      flash[:error] = 'You cannot view the testcase of this problem'
      redirect_to :controller => 'main', :action => 'list'
    end
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_testcase
      @testcase = Testcase.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def testcase_params
      params[:testcase]
    end
end
