class Api::V1::ContestsController < Api::V1::BaseController
  before_action :set_contest

  def show
    render json: {
      id: @contest.id,
      name: @contest.name,
      description: @contest.description,
      start: @contest.start,
      stop: @contest.stop,
      finalized: @contest.finalized,
      status: @contest.contest_status
    }
  end

  def problems
    problems = @contest.problems.where(available: true)
      .includes(:public_tags)
      .order("contests_problems.number")

    submissions = Submission.where(user: current_user, problem: problems)
    prob_stats = build_problem_stats(submissions, problems)

    render json: problems.map { |p| problem_list_json(p, prob_stats[p.id]) }
  end

  private

  def set_contest
    @contest = current_user.contests_for_action(:submit).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Contest")
  end

  def build_problem_stats(submissions, problems)
    stats = Hash.new { |h, k| h[k] = {} }

    last_sub_ids = submissions.group(:problem_id).pluck("max(id)")
    Submission.where(id: last_sub_ids).each do |sub|
      stats[sub.problem_id][:count] = sub.number
      stats[sub.problem_id][:last] = sub
    end

    # points is a DECIMAL column (BigDecimal in Ruby), which Rails JSON-encodes
    # as a string to preserve precision — cast to float so the API emits numbers
    submissions.group(:problem_id).pluck("problem_id", "max(points)").each do |pid, max|
      stats[pid][:best_score] = max&.to_f
    end

    stats
  end

  def problem_list_json(problem, stat)
    stat ||= {}
    last = stat[:last]
    {
      id: problem.id,
      name: problem.name,
      full_name: problem.full_name,
      difficulty: problem.difficulty,
      tags: problem.public_tags.pluck(:name),
      submission_count: stat[:count] || 0,
      best_score: stat[:best_score],
      last_score: last&.points&.to_f,
      last_result: last&.grader_comment,
      last_submission_time: last&.submitted_at,
      last_submission_id: last&.id,
      has_testcase: problem.can_view_testcase,
      has_attachment: problem.attachment.attached?
    }
  end
end
