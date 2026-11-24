# The student-facing testcase page and its downloads. Access is the tier
# User#testcase_access gives for the problem (issues #18 and #59): the page
# shows the first GraderConfiguration.testcase_preview_bytes of every file to
# everyone it admits, and only the :full tier (admins, reporters, editors)
# may download whole files. Managers (compile-time files) are whole for any
# tier: a submission is compiled against them, so they are not secret.
class TestcasesController < ApplicationController
  before_action :set_testcase, only: [:download_input, :download_sol]
  before_action :set_problem, only: [:show_problem, :download_manager, :download_data_file]
  before_action :testcase_authorization
  before_action :require_full_access, only: [:download_input, :download_sol, :download_data_file]

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

  # a run-time data file of the live dataset (issue #18); :full tier only
  def download_data_file
    df = @dataset.data_files.find(params[:att_id])

    send_data df.download, type: 'text/plain', filename: "#{df.filename}"
  end

  def show_problem
    @testcases = @dataset ? @dataset.testcases.display_order.with_attached_inp_file.with_attached_ans_file.to_a : []
    @managers = @dataset ? @dataset.managers : []
    @data_files = @dataset ? @dataset.data_files : []
    @preview_bytes = GraderConfiguration.testcase_preview_bytes
    @full = (@access == :full)
  end

  private
    def set_testcase
      @testcase = Testcase.find(params[:id])
      @problem = @testcase.dataset.problem
    end

    def set_problem
      @problem = Problem.find(params[:problem_id])
      @dataset = @problem.live_dataset
    end

    def testcase_authorization
      @access = @current_user&.testcase_access(@problem)
      unauthorized_redirect unless @access
    end

    def require_full_access
      unauthorized_redirect(msg: 'Only the first part of each test file is shown for this problem; downloads are not available.') unless @access == :full
    end
end
