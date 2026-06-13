class DatasetsController < ApplicationController
  include ProblemAuthorization

  # list of methods that are for viewing which requires viewable permission
  # (all others methods except these one are considered UPDATE_METHOD which require editable permission)
  VIEW_METHOD = %i[ view testcases files
                    testcase_input testcase_sol]

  before_action :set_dataset, only: %i[ edit update destroy
                                        file_delete file_view file_download
                                        testcase_input testcase_sol testcase_delete
                                        view set_as_live rejudge set_weight
                                        settings files testcases
                                      ]
  before_action :check_valid_login
  before_action :group_editor_authorization
  before_action :can_view_problem, only: VIEW_METHOD
  before_action :can_edit_problem, except: VIEW_METHOD
  before_action :set_active_tab, only: %i[edit view testcase_delete set_weight set_as_live update
                                          settings files testcases]

  # GET /datasets/new
  def new
    @dataset = Dataset.new
  end

  def view
    @dataset = Dataset.find(params[:null][:dsid])
    render :update
  end

  # GET /datasets/1/edit
  def edit
    render turbo_stream: turbo_stream.update(:dataset, partial: 'form', locals: {ds: @dataset})
  end

  # POST /datasets or /datasets.json
  def create
    @dataset = Dataset.new(dataset_params)

    respond_to do |format|
      if @dataset.save
        format.html { redirect_to dataset_url(@dataset), notice: "Dataset was successfully created." }
        format.json { render :show, status: :created, location: @dataset }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @dataset.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /datasets/1 or /datasets/1.json
  def update
    respond_to do |format|
      # file attachment
      @dataset.managers.attach params[:dataset][:managers] if params[:dataset] && params[:dataset][:managers]
      @dataset.data_files.attach params[:dataset][:data_files] if params[:dataset] && params[:dataset][:data_files]
      @dataset.initializers.attach params[:dataset][:initializers] if params[:dataset] && params[:dataset][:initializers]

      # since checker is downloaded and cached by WorkerDataset, we have to invalidate it
      # when it is updated
      if params[:dataset] && (params[:dataset][:checker] || params[:dataset][:managers] || params[:dataset][:initializers] || params[:dataset][:data_files])
        WorkerDataset.where(dataset_id: @dataset).delete_all
      end

      if @dataset.update(dataset_params)
        @toast = {title: 'Dataset', body: 'Dataset is updated.'}
        format.json { render :show, status: :ok, location: @dataset }
        format.turbo_stream
      else
        # format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @dataset.errors, status: :unprocessable_entity }
        format.turbo_stream
      end
    end
  end

  def file_delete
    att = ActiveStorage::Attachment.where(record: @dataset, id: params[:att_id]).first
    att.purge

    @dataset.reload
    @dataset.save if @dataset.update_main_filename

    @toast = {title: 'File deleted',
              body: "#{att.name.capitalize} file [#{att.filename}] is deleted."}
    @active_dataset_tab = "#files"
  end

  # POST /dataset/1/file/view/1
  # turbo
  def file_view
    att = ActiveStorage::Attachment.where(record: @dataset, id: params[:att_id]).first
    text = ERB::Util.html_escape(att.download)
    render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: att.filename, body_msg: "<pre>#{text}</pre>".html_safe}
  end

  def file_download
    att = ActiveStorage::Attachment.where(record: @dataset, id: params[:att_id]).first
    type = att.content_type
    filename = att.filename.to_s
    send_data att.download, disposition: 'inline', type: type, filename: filename
  end

  #--- turbo response ---
  def settings
    render turbo_stream: turbo_stream.update('dataset_settings', partial: 'settings', locals: {ds: @dataset})
  end

  def testcases
    render turbo_stream: turbo_stream.update('dataset_testcases', partial: 'testcases', locals: {ds: @dataset})
  end

  def files
    render turbo_stream: turbo_stream.update('dataset_files', partial: 'managers', locals: {ds: @dataset})
  end

  # as turbo
  def testcase_input
    begin
      tc = Testcase.find(params[:tc_id])
      text = ERB::Util.html_escape(tc.inp_file.download)
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Input', body_msg: "<pre>#{text}</pre>".html_safe }
    rescue  ActiveStorage::FileNotFoundError
      text = "<div class='alert alert-danger'>File NOT Found on the server!!!</div>".html_safe
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Input ERROR', body_msg: text }
    end
  end

  # as turbo
  def testcase_sol
    begin
      tc = Testcase.find(params[:tc_id])
      text = ERB::Util.html_escape(tc.ans_file.download)
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Answer', body_msg: "<pre>#{text}</pre>".html_safe }
    rescue  ActiveStorage::FileNotFoundError
      text = "<div class='alert alert-danger'>File NOT Found on the server!!!</div>".html_safe
      render partial: 'msg_modal_show', locals: {do_popup: true, header_msg: 'Answer ERROR', body_msg: text }
    end
  end

  # as turbo
  def testcase_delete
    tc = Testcase.find(params[:tc_id])
    tc.destroy
    # workers cache testcase files per dataset; without this they keep
    # grading against the deleted case
    tc.dataset.invalidate_worker

    @toast = {title: 'Testcase changed',
              body: "Testcase ##{tc.num} is deleted."}
    render :update
  end

  def set_weight
    begin
      config = JSON.parse(params[:weight_param])
      if config.is_a? Array
        @dataset.set_by_array(:weight, config, can_use_cms_mode: true)
      elsif config.is_a? Hash
        @dataset.set_by_hash(config.symbolize_keys)
      else
        raise JSON::ParserError
      end
      @toast = {body: "Testcases' parameters are updated.", title: 'Testcase updated'}
    rescue JSON::ParserError => e
      @toast = {body: "Weight parameter is malformed.", title: 'Testcase updated', type: 'alert'}
    end
    render :update
  end


  def set_as_live
    @dataset.problem.update(live_dataset: @dataset)
    @toast = {title: 'Dataset changed',
              body: "Dataset [#{@dataset.name}] is now live."}
    render :update
  end

  def rejudge
    @dataset.problem.submissions.each do |sub|
      # mass rejudge, priority is very low
      sub.add_judge_job(@dataset, -50)
    end
  end

  # DELETE /datasets/1 or /datasets/1.json
  def destroy
    p = @dataset.problem
    if p.datasets.count == 1
      # can't delete last dataset
      @toast = {title: 'Delete error', type: 'alert',
                body: "Cannot delete the last remaining dataset."}
    elsif @dataset == p.live_dataset
      # can't delete the live dataset
      @toast = {title: 'Delete error', type: 'alert',
                body: "Cannot delete the live dataset."}
    else
      @dataset.destroy
      @toast = {title: 'Dataset changed', type: 'warning',
                body: "Dataset  [#{@dataset.name}] is deleted."}
      # render new dataset
      @dataset = p.datasets.first
    end


    respond_to do |format|
      format.html { redirect_to datasets_url, notice: "Dataset was successfully destroyed." }
      format.json { head :no_content }
      format.turbo_stream { render :update }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_dataset
      @dataset = Dataset.find(params[:id])
      @problem = @dataset.problem
    end

    # Only allow a list of trusted parameters through.
    def dataset_params
      params.fetch(:dataset, {})
      params.require(:dataset).permit(:name, :time_limit, :memory_limit, :score_type, :evaluation_type, :main_filename,
                                      :checker, :initializer_filename)
    end

    # our 'bs-tab' stimulus controller set the hidden input as the HTML id of the showing tab
    # we set @dataset_active_tab to the id so that we render it, we can activate the correct tab
    def set_active_tab
      @active_dataset_tab = params[:active_dataset_tab]
      @active_dataset_tab = '#settings' if @active_dataset_tab.blank?
    end
end
