class AuditLogsController < ApplicationController
  before_action :admin_authorization

  PER_PAGE = 50

  def index
    @auditable_type = params[:auditable_type].presence
    @auditable_id   = params[:auditable_id].presence
    @filter_user    = User.find_by(id: params[:user_id]) if params[:user_id].present?

    scope = AuditLog.includes(:user, :auditable).recent
    scope = apply_scope(scope)

    @total_count = scope.count
    @page        = [params[:page].to_i, 1].max
    @per_page    = PER_PAGE
    @total_pages = [(@total_count.to_f / @per_page).ceil, 1].max
    @page        = @total_pages if @page > @total_pages

    @audits = scope.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    @audit = AuditLog.includes(:user).find(params[:id])
  end

  private

  def apply_scope(scope)
    if @auditable_type == "Dataset" && @auditable_id.present?
      dataset = Dataset.find_by(id: @auditable_id)
      return scope.none unless dataset
      scope.where(
        "(audit_logs.auditable_type = 'Dataset' AND audit_logs.auditable_id = ?) " \
        "OR (audit_logs.auditable_type = 'Testcase' AND audit_logs.auditable_id IN (?))",
        dataset.id, dataset.testcases.pluck(:id).presence || [0]
      )
    elsif @auditable_type == "Contest" && @auditable_id.present?
      contest = Contest.find_by(id: @auditable_id)
      return scope.none unless contest
      scope.where(
        "(audit_logs.auditable_type = 'Contest' AND audit_logs.auditable_id = ?) " \
        "OR (audit_logs.auditable_type = 'ContestProblem' AND audit_logs.auditable_id IN (?)) " \
        "OR (audit_logs.auditable_type = 'ContestUser'    AND audit_logs.auditable_id IN (?))",
        contest.id,
        contest.contests_problems.pluck(:id).presence || [0],
        contest.contests_users.pluck(:id).presence    || [0]
      )
    elsif @auditable_type.present? && @auditable_id.present?
      scope.where(auditable_type: @auditable_type, auditable_id: @auditable_id)
    else
      scope = scope.where(auditable_type: @auditable_type) if @auditable_type.present?
      scope = scope.where(user_id: @filter_user.id)        if @filter_user
      scope
    end
  end
end
