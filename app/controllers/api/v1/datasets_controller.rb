class Api::V1::DatasetsController < Api::V1::BaseController
  before_action :require_editor!
  before_action :set_problem_from_problem_id, only: [:index, :create]
  before_action :set_dataset, only: [:update, :destroy, :set_live, :file_create, :file_delete]

  # GET /api/v1/problems/:problem_id/datasets
  def index
    render json: @problem.datasets.includes(:testcases).map { |ds| dataset_json(ds) }
  end

  # POST /api/v1/problems/:problem_id/datasets
  def create
    @dataset = @problem.datasets.new(dataset_params)
    @dataset.name = @problem.get_next_dataset_name if @dataset.name.blank?

    if @dataset.save
      render json: dataset_json(@dataset), status: :created
    else
      render_validation_errors(@dataset)
    end
  rescue ArgumentError => e # invalid enum value (score_type / evaluation_type)
    render json: { error: "Validation failed", details: [e.message] }, status: :unprocessable_entity
  end

  # PATCH /api/v1/datasets/:id — settings only; files go through file_create
  def update
    if @dataset.update(dataset_params)
      render json: dataset_json(@dataset.reload)
    else
      render_validation_errors(@dataset)
    end
  rescue ArgumentError => e
    render json: { error: "Validation failed", details: [e.message] }, status: :unprocessable_entity
  end

  # POST /api/v1/datasets/:id/files — attach files (multipart)
  def file_create
    # blank-string values appear when a form field is submitted empty;
    # treat them as absent (ActiveStorage#attach ignores them anyway)
    uploads = params.slice(:checker, :managers, :data_files, :initializers)
                    .to_unsafe_h.compact_blank
    if uploads.empty?
      render json: { error: "No files given (use checker / managers / data_files / initializers)" },
             status: :unprocessable_entity and return
    end

    @dataset.checker.attach(uploads["checker"]) if uploads["checker"]
    @dataset.managers.attach(uploads["managers"]) if uploads["managers"]
    @dataset.data_files.attach(uploads["data_files"]) if uploads["data_files"]
    @dataset.initializers.attach(uploads["initializers"]) if uploads["initializers"]

    # workers cache dataset files (incl. the checker); drop the cache rows so
    # they re-download — mirrors the web DatasetsController#update
    @dataset.invalidate_worker

    # attaching to a persisted record skips the dataset's own callbacks, so
    # re-derive main_filename the way the web file actions do
    @dataset.reload
    @dataset.save if @dataset.update_main_filename
    render json: dataset_json(@dataset)
  end

  # DELETE /api/v1/datasets/:id
  def destroy
    problem = @dataset.problem
    if problem.datasets.count == 1
      render json: { error: "Cannot delete the last remaining dataset" }, status: :conflict
    elsif @dataset == problem.live_dataset
      render json: { error: "Cannot delete the live dataset" }, status: :conflict
    else
      @dataset.destroy
      head :no_content
    end
  end

  # POST /api/v1/datasets/:id/set_live
  def set_live
    @dataset.problem.update(live_dataset: @dataset)
    render json: dataset_json(@dataset.reload)
  end

  # DELETE /api/v1/datasets/:id/files/:attachment_id
  def file_delete
    att = ActiveStorage::Attachment.where(record: @dataset, id: params[:attachment_id]).first
    render_not_found("File") and return unless att

    att.purge
    @dataset.reload
    @dataset.save if @dataset.update_main_filename
    @dataset.invalidate_worker
    render json: dataset_json(@dataset)
  end

  private

  def set_problem_from_problem_id
    @problem = Problem.find(params[:problem_id])
    authorize_problem_edit!
  rescue ActiveRecord::RecordNotFound
    render_not_found("Problem")
  end

  def set_dataset
    @dataset = Dataset.find(params[:id])
    @problem = @dataset.problem
    authorize_problem_edit!
  rescue ActiveRecord::RecordNotFound
    render_not_found("Dataset")
  end

  def authorize_problem_edit!
    return true if current_user.can_edit_problem?(@problem)
    render json: { error: "Forbidden" }, status: :forbidden
    false
  end

  def dataset_params
    params.fetch(:dataset, {}).permit(:name, :time_limit, :memory_limit,
                                      :score_type, :evaluation_type, :score_param,
                                      :main_filename, :initializer_filename)
  end

  def dataset_json(dataset)
    {
      id: dataset.id,
      problem_id: dataset.problem_id,
      name: dataset.name,
      live: dataset.problem.live_dataset_id == dataset.id,
      # decimal column — cast so JSON carries a number, not a string
      time_limit: dataset.time_limit&.to_f,
      memory_limit: dataset.memory_limit,
      score_type: dataset.score_type,
      evaluation_type: dataset.evaluation_type,
      score_param: dataset.score_param,
      main_filename: dataset.main_filename,
      initializer_filename: dataset.initializer_filename,
      testcase_count: dataset.testcases.size,
      files: {
        checker: attachment_json(dataset.checker),
        managers: dataset.managers.map { |a| attachment_json(a) },
        data_files: dataset.data_files.map { |a| attachment_json(a) },
        initializers: dataset.initializers.map { |a| attachment_json(a) }
      }
    }
  end

  # accepts the has_one proxy (checker) or an Attachment row (from the
  # has_many collections); ids are Attachment ids, usable with file_delete
  def attachment_json(attached)
    if attached.is_a?(ActiveStorage::Attached::One)
      return nil unless attached.attached?
      attached = attached.attachment
    end
    { id: attached.id, filename: attached.filename.to_s, byte_size: attached.byte_size }
  end
end
