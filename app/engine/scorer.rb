# This is for calculating the score of a submission after testcases are evaluated
class Scorer
  include IsolateRunner
  include JudgeBase
  include Rails.application.routes.url_helpers

  FALLBACK_POINTS_MAX = 9999.9999.to_d

  def sorted_evaluation
    @sub.evaluations.joins(:testcase).includes(:testcase)
          .order(:group, :code_name, 'testcases.id ASC')
  end

  # Three score-aggregation strategies live below: sum_of_all_testcases,
  # group_min, raw_sum. They're dispatched on Dataset#score_type at line
  # 135. Semantics documented in doc/dataset-scoring-and-evaluation.md —
  # keep that file in sync when modifying these.

  # score_type :sum — weighted sum / total weight × 100. Full score is
  # always 100 regardless of testcase weights. Default for most problems.
  def sum_of_all_testcases
    sum_user_score, sum_total_weight = 0.to_d, 0.to_d
    @sub.evaluations.each do |ev|
      score = ev.score || 0
      weight = ev.testcase.weight || 0
      sum_user_score += score * weight
      sum_total_weight += weight
    end
    raise GraderError.new("All testcase weights are zero for Sub ##{@sub.id}", submission_id: @sub.id) if sum_total_weight.zero?
    score = sum_user_score / sum_total_weight * 100.to_d
    return score
  end

  # score_type :group_min — IOI/ICPC subtask style. For each group take
  # the minimum testcase score, multiply by the group's max weight, then
  # normalize to 100. One failure in a group drags the whole group to
  # its min.
  def group_min
    # evs = evaluations sorted by group
    evs = sorted_evaluation.select(:group, :group_name, :score, :weight, :testcase_id).map { |r| r.attributes.symbolize_keys }
    return 0.to_d if evs.empty?
    max_group = evs.max_by { |x| x[:group] || 0 }
    evs << {group: max_group[:group]+1} # this is sentinel, the after final group

    last_group = max_group[:group]+2
    sum_user_score, sum_total_weight = 0.to_d, 0.to_d
    min_score = 0
    max_weight = 0
    evs.each.with_index do |ev, idx|
      group = ev[:group]
      score = ev[:score] || 0
      weight = ev[:weight] || 0

      # process group
      if last_group != group
        # found new group, save old group result
        # the nil group has min_score, max_weight as 0
        sum_user_score += min_score * max_weight
        sum_total_weight += max_weight

        # reset group tally
        min_score = score
        max_weight = weight
      else
        min_score = [min_score, score].min
        max_weight = [max_weight, weight].min
      end
      last_group = group
    end

    raise GraderError.new("All testcase weights are zero for Sub ##{@sub.id}", submission_id: @sub.id) if sum_total_weight.zero?
    score = sum_user_score / sum_total_weight * 100.to_d
    return score
  end

  # score_type :raw_sum — literal Σ of per-testcase scores. No weighting,
  # no scaling. Designed to pair with evaluation_type :custom_cms_raw,
  # where the custom checker emits the score it wants summed directly.
  def raw_sum
    sum_user_score = 0.to_d
    @sub.evaluations.each do |ev|
      score = ev.score || 0
      sum_user_score += score
    end
    score = sum_user_score
    return score
  end

  # build a combined short string that represent evaluation results of the entire dataset
  def build_grading_text
    result = ''

    # gen group info
    evs = sorted_evaluation.select(:group, :group_name, :result, :testcase_id).map { |r| r.attributes.symbolize_keys }
    return '' if evs.empty?
    max_group = evs.max_by { |x| x[:group] || 0 }
    evs << {group: max_group[:group]+1, result: ''} # this is sentinel

    last_group = max_group[:group]+2 # some group number that is not in the data and not sentinel
    group_result = ''
    current_group_count = 0
    # build the string
    evs.each do |ev|
      group = ev[:group]
      result_code = Evaluation.result_enum_to_code(ev[:result])

      # process end of group
      if last_group != group
        # found new group, save old group result
        if last_group != nil
          if current_group_count <= 1
            result += group_result
          else
            # multiple testcase in group
            result += '[' +  group_result + ']'
          end
        end

        # reset group tally
        group_result = ''
        current_group_count = 0
      end

      group_result += result_code
      current_group_count += 1
      last_group = group
    end
    return result
  end

  # main run function
  # calculate the score, assuming all required evaluation is completed
  def process(sub, dataset)
    @sub = sub
    @working_dataset = dataset

    # validate if sub has evaluations of all testcases of the dataset
    sub_tc_ids = @sub.evaluations.where.not(result: :waiting).pluck(:testcase_id).sort
    ds_tc_ids = @working_dataset.testcases.ids.sort
    if sub_tc_ids != ds_tc_ids
      msg = "Evaluations are missing, please rejudge."
      @sub.set_grading_error(msg)
      return EngineResponse::Result.failure(error: msg)
    end

    # calculate score
    point = nil
    case @working_dataset.score_type
    when 'sum'
      point = sum_of_all_testcases
    when 'group_min'
      point = group_min
    when 'raw_sum'
      point = raw_sum
    else
    end

    grading_text = build_grading_text

    # calculate time
    max_time = @sub.evaluations.pluck(:time).map { |x| x || 0 }.max
    max_mem = @sub.evaluations.pluck(:memory).map { |x| x || 0 }.max

    # update result
    @sub.set_grading_complete(normalize_point_for_storage(point), grading_text, max_time, max_mem)

    judge_log "#{rb_sub(@sub)} completed with points = " + Rainbow("#{point} (#{grading_text})").color(COLOR_SCORE_RESULT)
    return EngineResponse::Result.success
  end

  # return appropriate evaluator class for the submission
  def self.get_scorer(submission)
    # todo: should return appropriate scorer class
    return self
  end

  private

  def normalize_point_for_storage(point)
    return nil if point.nil?

    numeric_point = point.to_d
    max_point = max_points_supported_by_column
    min_point = -max_point
    return max_point if numeric_point > max_point
    return min_point if numeric_point < min_point

    numeric_point
  end

  def max_points_supported_by_column
    @max_points_supported_by_column ||= begin
      col = Submission.columns_hash['points']
      precision = col&.precision
      scale = col&.scale || 0

      if precision.present? && precision > scale
        digits_before_decimal = precision - scale
        (10.to_d**digits_before_decimal) - (1.to_d / (10.to_d**scale))
      else
        FALLBACK_POINTS_MAX
      end
    end
  end
end
