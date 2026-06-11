class Api::V1::ProblemsController < Api::V1::BaseController
  before_action :set_problem, only: [:show, :description, :file, :data_files, :testcases]
  # Write actions look the problem up directly: set_problem uses the
  # student submit scope, which excludes unavailable problems even for
  # their editors.
  before_action :set_problem_for_edit, only: [:update, :destroy, :statement, :import_testcases]
  before_action :require_editor!, only: [:create]

  # GET /api/v1/problems
  def index
    problems = current_user.problems_for_action(:submit, respect_admin: false)
      .includes(:public_tags)
      .with_attached_statement
      .with_attached_attachment
      .default_order

    submissions = Submission.where(user: current_user, problem: problems)
    prob_stats = build_problem_stats(submissions)

    render json: problems.map { |p| problem_list_json(p, prob_stats[p.id]) }
  end

  # GET /api/v1/problems/:id
  def show
    submissions = Submission.where(user: current_user, problem: @problem)
    stat = build_problem_stats(submissions)[@problem.id] || {}
    last = stat[:last]

    render json: {
      id: @problem.id,
      name: @problem.name,
      full_name: @problem.full_name,
      full_score: @problem.full_score,
      difficulty: @problem.difficulty,
      tags: @problem.public_tags.pluck(:name),
      submission_count: stat[:count] || 0,
      best_score: stat[:best_score],
      last_score: last&.points&.to_f,
      last_result: last&.grader_comment,
      last_submission_time: last&.submitted_at,
      last_submission_id: last&.id,
      has_testcase: @problem.can_view_testcase,
      has_attachment: @problem.attachment.attached?,
      permitted_languages: permitted_languages_for(@problem),
      submission_ids: submissions.order(submitted_at: :desc).pluck(:id)
    }
  end

  # GET /api/v1/problems/:id/description
  def description
    render json: {
      markdown: @problem.markdown?,
      description: @problem.description
    }
  end

  # GET /api/v1/problems/:id/files/:type
  def file
    # The dataset is only needed for checker/manager (they hang off the
    # live dataset). PDF and attachment live on Problem directly, so
    # demanding a live_dataset here used to lock viva problems (which
    # have no dataset by design) out of the PDF endpoint entirely.
    # Resolved on demand inside the branches that need it.

    case params[:type]
    when "pdf"
      # PDF statement is hidden from students for problem modes where
      # the PDF is staff-only (viva). Mirrors the web equivalent in
      # ProblemsController#download_by_type.
      unless current_user.can_view_problem_pdf?(@problem)
        render json: {error: "PDF statement not available for this problem"}, status: :forbidden and return
      end
      if @problem.statement.attached?
        send_data @problem.statement.download,
          type: @problem.statement.content_type,
          filename: @problem.statement.filename.to_s,
          disposition: "inline"
      elsif @problem.generated_statement.attached?
        send_data @problem.generated_statement.download,
          type: "application/pdf",
          filename: "#{@problem.name}.pdf",
          disposition: "inline"
      else
        render_not_found("PDF statement")
      end
    when "attachment"
      if @problem.attachment.attached?
        send_data @problem.attachment.download,
          type: @problem.attachment.content_type,
          filename: @problem.attachment.filename.to_s
      else
        render_not_found("Attachment")
      end
    when "checker"
      return unless authorize_edit!
      dataset = @problem.live_dataset
      return render_not_found("Dataset") unless dataset
      if dataset.checker.attached?
        send_data dataset.checker.download,
          type: "application/octet-stream",
          filename: dataset.checker.filename.to_s
      else
        render_not_found("Checker")
      end
    when "manager"
      dataset = @problem.live_dataset
      return render_not_found("Dataset") unless dataset
      managers = dataset.managers
      if managers.attached?
        render json: managers.map { |m|
          { id: m.id, filename: m.filename.to_s }
        }
      else
        render json: []
      end
    else
      render json: { error: "Unknown file type: #{params[:type]}" }, status: :bad_request
    end
  end

  # GET /api/v1/problems/:id/data_files
  def data_files
    return unless authorize_edit!
    dataset = @problem.live_dataset
    unless dataset
      render_not_found("Dataset") and return
    end

    if dataset.data_files.attached?
      render json: dataset.data_files.map { |f|
        { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size }
      }
    else
      render json: []
    end
  end

  # POST /api/v1/problems
  def create
    @problem = Problem.new(problem_params)
    @problem.full_name = @problem.name if @problem.full_name.blank?
    # quick_create-style defaults for keys the client omitted
    @problem.available = false unless problem_params.key?(:available)
    @problem.test_allowed = true unless problem_params.key?(:test_allowed)
    @problem.output_only = false unless problem_params.key?(:output_only)
    @problem.date_added ||= Time.zone.today

    return unless apply_permitted_languages(@problem)

    # Mirror web quick_create: a problem without a dataset is invisible to
    # the manage views, so the default dataset + live pointer are created
    # atomically with the problem.
    ok = Problem.transaction do
      next false unless @problem.save
      ds = @problem.datasets.create!(name: @problem.get_next_dataset_name)
      @problem.update!(live_dataset: ds)
      true
    end

    if ok
      render json: problem_admin_json(@problem), status: :created
    else
      render_validation_errors(@problem)
    end
  rescue ArgumentError => e # invalid enum value, e.g. compilation_type
    render json: { error: "Validation failed", details: [e.message] }, status: :unprocessable_entity
  end

  # PATCH /api/v1/problems/:id
  def update
    return unless apply_permitted_languages(@problem)

    if @problem.update(problem_params)
      render json: problem_admin_json(@problem)
    else
      render_validation_errors(@problem)
    end
  rescue ArgumentError => e
    render json: { error: "Validation failed", details: [e.message] }, status: :unprocessable_entity
  end

  # PUT /api/v1/problems/:id/statement — upload/replace the statement PDF
  def statement
    file = params[:statement]
    unless file.respond_to?(:content_type)
      render json: { error: "Missing statement file" }, status: :unprocessable_entity and return
    end
    unless file.content_type == "application/pdf"
      render json: { error: "Uploaded file is not PDF" }, status: :unprocessable_entity and return
    end

    @problem.statement.attach(file)
    render json: problem_admin_json(@problem)
  end

  # DELETE /api/v1/problems/:id
  def destroy
    @problem.destroy
    head :no_content
  end

  # POST /api/v1/problems/:id/testcases/import — bulk import from a zip
  # (mirrors the web ProblemsController#import_testcases / ProblemImporter flow)
  def import_testcases
    file = params[:file]
    unless file.respond_to?(:tempfile)
      render json: { error: "Missing zip file (multipart field: file)" },
             status: :unprocessable_entity and return
    end

    dataset = nil
    if params[:dataset_id].present?
      dataset = @problem.datasets.where(id: params[:dataset_id]).first
      render_not_found("Dataset") and return unless dataset
    end

    importer = ProblemImporter.new
    extracted_path = importer.unzip_to_dir(
      file.tempfile.path,
      @problem.name,
      Rails.configuration.worker[:directory][:judge_raw_path])

    if importer.errors.count > 0
      render json: { error: "Import failed", details: importer.errors },
             status: :unprocessable_entity and return
    end

    # importing replaces files workers may have cached
    dataset&.invalidate_worker

    # one semantic audit row instead of a per-testcase cascade
    AuditLog.paused do
      importer.import_dataset_from_dir(
        extracted_path, @problem.name,
        full_name: @problem.full_name,
        input_pattern: params[:input_pattern].presence || "*.in",
        sol_pattern: params[:sol_pattern].presence || "*.sol",
        dataset: dataset,
        do_statement: false,
        do_checker: false,
        do_cpp_extras: false,
        do_solutions: false
      )
    end
    result_dataset = importer.dataset
    AuditLog.record!(auditable: @problem,
                     action: "import_testcases",
                     object_changes: {
                       "dataset" => [nil, result_dataset&.name],
                       "testcases" => [nil, result_dataset&.testcases&.count]
                     })

    render json: {
      problem_id: @problem.id,
      dataset_id: result_dataset&.id,
      dataset_name: result_dataset&.name,
      testcase_count: result_dataset&.testcases&.count || 0,
      log: importer.log
    }
  end

  # GET /api/v1/problems/:id/testcases
  def testcases
    unless current_user.can_view_testcase?(@problem)
      render json: { error: "You are not allowed to view testcases for this problem" }, status: :forbidden and return
    end

    dataset = @problem.live_dataset
    tcs = dataset.testcases.display_order

    render json: tcs.map { |tc|
      {
        id: tc.id,
        num: tc.num,
        group: tc.group,
        group_name: tc.group_name,
        weight: tc.weight
      }
    }
  end

  private

  def set_problem
    @problem = current_user.problems_for_action(:submit).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Problem")
  end

  # 404 for unknown ids, 403 for problems the user cannot edit.
  def set_problem_for_edit
    @problem = Problem.find(params[:id])
    authorize_edit!
  rescue ActiveRecord::RecordNotFound
    render_not_found("Problem")
  end

  def authorize_edit!
    return true if current_user.can_edit_problem?(@problem)
    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  def problem_params
    params.require(:problem).permit(:name, :full_name, :available, :date_added,
                                    :test_allowed, :output_only, :difficulty,
                                    :submission_filename, :compilation_type,
                                    :view_testcase, :view_submission, :markdown,
                                    :description, :url, tag_ids: [], group_ids: [])
  end

  # permitted_lang is stored as a space-separated string of language
  # names; the API speaks ids (mirrors the web update action's mapping).
  # nil → leave untouched, [] → clear (all languages allowed).
  def apply_permitted_languages(problem)
    return true unless params[:problem]&.key?(:permitted_language_ids)

    ids = Array(params[:problem][:permitted_language_ids]).reject(&:blank?)
    langs = Language.where(id: ids)
    if langs.count != ids.map(&:to_i).uniq.size
      render json: { error: "Validation failed", details: ["Unknown language id"] },
             status: :unprocessable_entity
      return false
    end
    problem.permitted_lang = langs.map(&:name).join(" ")
    true
  end

  # Admin/editor-facing shape (the student-facing shapes above hide
  # management fields like available/live_dataset_id).
  def problem_admin_json(problem)
    {
      id: problem.id,
      name: problem.name,
      full_name: problem.full_name,
      full_score: problem.full_score,
      available: problem.available,
      test_allowed: problem.test_allowed,
      output_only: problem.output_only,
      view_testcase: problem.view_testcase,
      view_submission: problem.view_submission,
      markdown: problem.markdown,
      difficulty: problem.difficulty,
      date_added: problem.date_added,
      url: problem.url,
      description: problem.description,
      submission_filename: problem.submission_filename,
      compilation_type: problem.compilation_type,
      live_dataset_id: problem.live_dataset_id,
      permitted_languages: permitted_languages_for(problem),
      tag_ids: problem.tag_ids,
      group_ids: problem.group_ids,
      has_statement: problem.statement.attached?,
      has_attachment: problem.attachment.attached?
    }
  end

  def build_problem_stats(submissions)
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
      has_attachment: problem.attachment.attached?,
      permitted_languages: permitted_languages_for(problem)
    }
  end

  def permitted_languages_for(problem)
    ids = problem.get_permitted_lang_as_ids(when_blank: nil)
    return nil if ids.nil?  # nil means all languages allowed
    Language.where(id: ids).map { |l| { id: l.id, name: l.name, ext: l.ext } }
  end
end
