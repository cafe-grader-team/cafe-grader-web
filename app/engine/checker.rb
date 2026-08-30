require 'open3'

class Checker
  include IsolateRunner
  include JudgeBase
  include Rails.application.routes.url_helpers

  # Each branch produces the shell command that compares submission output
  # to the expected answer. Semantics documented in
  # doc/dataset-scoring-and-evaluation.md — keep that file in sync with
  # this dispatch table when adding/changing evaluators.
  def check_command(evaluation_type, input_file, output_file, ans_file)
    case evaluation_type
    when 'default'
      # -b: ignore amount-of-whitespace diffs; -B: ignore blank lines;
      # -Z: ignore trailing whitespace. Right default for most problems.
      return "diff -q -b -B -Z #{output_file} #{ans_file}"
    when 'exact'
      return "diff -q #{output_file} #{ans_file}"
    when 'relative'
      # Tokenizes on whitespace; numbers compared with EPSILON = 1e-6.
      prog = Rails.root.join 'lib', 'checker', (evaluation_type + ".rb")
      return "#{prog} #{input_file} #{output_file} #{ans_file}"
    when 'postgres'
      # Strips CREATE VIEW / DROP VIEW lines, then CMS-style scoring.
      prog = Rails.root.join 'lib', 'checker', 'postgres_checker.rb'
      return "#{prog} #{input_file} #{output_file} #{ans_file}"
    when 'custom_testlib', 'custom_testlib_raw'
      # User's checker, testlib/Codeforces argv order (input, USER, correct),
      # CMS result protocol: exit 0, score on stdout, comment on stderr. The
      # _raw variant outputs a raw decimal score meant to pair with
      # score_type :raw_sum. Named custom_cms / custom_cms_raw until rev 2047
      # — the order is NOT what CMS itself passes (see 'cms_comparator').
      # Every deployed problem on these types was written to this order
      # (verified 2026-08-29/30, doc/decisions.md) — do NOT change.
      return "#{@prob_checker_file} #{input_file} #{output_file} #{ans_file}"
    when 'cms_comparator'
      # User's checker, CMS-native argv order (input, CORRECT, USER) — this is
      # what CMS itself invokes (cms/grading/steps/trusted.py), swapped from
      # custom_testlib's order. Same result protocol as custom_testlib: exit 0,
      # score on stdout, comment on stderr (see process_result_cms).
      return "#{@prob_checker_file} #{input_file} #{ans_file} #{output_file}"
    when 'custom_cafe'
      # User's checker. Receives <lang> <tc_num> <in> <out> <ans> 10.
      # Output is two lines: line1 CORRECT/INCORRECT/COMMENT:, line2 score
      # (note: score is divided by 10 in process_result_cafe).
      return "#{@prob_checker_file} #{@sub.language.name} #{@testcase.num} #{input_file} #{output_file} #{ans_file} 10"
    when 'no_check'
      # Reachable here but NOT in the Dataset#evaluation_type enum — see doc.
      return ""
    end
  end

  def process_result_cms(out, err)
    score = out.chomp.strip
    err = err.chomp.strip
    err = nil if ['translate:success', 'translate:wrong'].include? err   # remove CMS default "translate:success" and "translate:wrong" from the comment
    err = nil if err.blank?
    return EngineResponse::CheckerResult.by_score(score: score, comment: err)
  end

  def process_result_cms_raw(out, err)
    score = out.chomp.strip.to_d
    err = err.chomp.strip
    err = nil if err.blank?
    return EngineResponse::CheckerResult.partial(score: score, comment: err)
  end

  def process_result_cafe(out, err)
    arr = out.split("\n")
    if arr.count < 2
      return EngineResponse::CheckerResult.grader_error(comment: '(cafe-checker) output from checker is malformed')
    end
    score = arr[1].to_d/10
    if arr[0].upcase == "CORRECT"
      return EngineResponse::CheckerResult.correct(score: score)
    elsif arr[0].upcase == "INCORRECT"
      return EngineResponse::CheckerResult.wrong(score: score)
    elsif arr[0].split(':')[0].upcase == 'COMMENT'
      comment = arr[0][8...]
      return EngineResponse::CheckerResult.partial(score: score, comment: comment)
    else
      return EngineResponse::CheckerResult.grader_error(comment: '(cafe-checker) output from checker is malformed')
    end
  end

  def process_result(evaluation_type, out, err, status)
    case evaluation_type
    when 'default', 'exact', 'relative'
      # these standard check return 0 when correct
      if status.exitstatus == 0
        return EngineResponse::CheckerResult.correct
      else
        return EngineResponse::CheckerResult.wrong
      end
    when 'postgres'
      return process_result_cms(out, err)
    when 'custom_testlib', 'custom_testlib_raw', 'custom_cafe', 'cms_comparator'
      if status.exitstatus == 0
        if evaluation_type == 'custom_testlib' || evaluation_type == 'cms_comparator'
          return process_result_cms(out, err)
        elsif evaluation_type == 'custom_testlib_raw'
          return process_result_cms_raw(out, err)
        else
          return process_result_cafe(out, err)
        end
      else
        comment = "ERROR IN CHECKER!!!\n-- stderr --\n#{err}-- status -- #{status}"
        return EngineResponse::CheckerResult.grader_error(comment: comment)
      end
    when 'no_check'
      return EngineResponse::CheckerResult.partial(score: 0)
    else
      return EngineResponse::CheckerResult.grader_error(comment: 'Unknown evaluation type')
    end
  end

  # check if required files, that are, output from submttion, answer from problem
  # and any other file is there
  def check_for_required_file
    raise "Output file [#{@output_file.cleanpath}] does not exists" unless @output_file.exist?
    raise "Answer file [#{@ans_file.cleanpath}] does not exists" unless @ans_file.exist?
    if ['custom_testlib', 'custom_testlib_raw', 'custom_cafe', 'cms_comparator'].include?(@ds.evaluation_type) &&
        (@prob_checker_file.nil? || @prob_checker_file.exist? == false)
      raise GraderError.new("Checker file does not exists", submission_id: @sub.id)
    end
  end

  def result_status_with_color(result)
    if result[:result] == :correct
      color = COLOR_GRADING_CORRECT
    elsif result[:result] == :wrong
      color = COLOR_GRADING_WRONG
    elsif result[:result] == :partial
      color = COLOR_GRADING_PARTIAL
    else
      color = :red
    end

    res = Rainbow(result[:result].to_s).color(color)
    res += " comment: #{result[:comment]}" unless result[:comment].blank?
    return res
  end

  # main run function
  # run the submission against the testcase
  def process(sub, testcase)
    @sub = sub
    @testcase = testcase
    @ds = @testcase.dataset

    # init isolate
    # setup_isolate(@box_id)

    # prepare files location variable
    prepare_submission_directory(@sub)
    prepare_dataset_directory(@ds)
    prepare_testcase_directory(@sub, @testcase)
    check_for_required_file

    cmd = check_command(@ds.evaluation_type, @input_file, @output_file, @ans_file)

    # call the compare command
    judge_log "#{rb_sub(@sub)} Testcase: #{rb_testcase(@testcase)} check cmd: " + Rainbow(cmd).color(JudgeBase::COLOR_CHECK_CMD)
    out, err, status = Open3.capture3(cmd)

    result = process_result(@ds.evaluation_type, out, err, status)
    judge_log "#{rb_sub(@sub)} Testcase: #{rb_testcase(@testcase)} check result: "+result_status_with_color(result)
    return result
  end

  # return appropriate evaluator class for the submission
  def self.get_checker(submission)
    # TODO: should return appropriate scorer class
    return self
  end
end
