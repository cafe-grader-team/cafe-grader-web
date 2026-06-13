class WorkerController < ApplicationController
  skip_forgery_protection
  before_action :worker_authenticity
  # this centralize communication between worker and the web interface

  # handle receiving compiled files from worker
  def compiled_submission
    sub = Submission.find(params[:id])
    # atomic replace: attach new files first, then purge old ones
    old_blobs = sub.compiled_files.map(&:blob)
    sub.compiled_files.attach upload_compiled_params[:compiled_files]
    old_blobs.each { |blob| blob.purge_later }
  end

  def get_compiled_submission
    sub = Submission.find(params[:sub_id])
    compiled_file = sub.compiled_files.find(params[:attach_id])
    send_data compiled_file.download, :filename => compiled_file.filename.to_s, :type => 'application/octet-stream'
  rescue ActiveRecord::RecordNotFound => e
    render status: :not_found, plain: "Not found: #{e.message}"
  rescue ActiveStorage::FileNotFoundError
    render status: :not_found, plain: "File missing from storage for submission #{params[:sub_id]}"
  end

  def get_manager
    dataset = Dataset.find(params[:ds_id])
    file = dataset.managers.find(params[:manager_id])
    send_data file.download, :filename => file.filename.to_s, :type => 'application/octet-stream'
  rescue ActiveRecord::RecordNotFound => e
    render status: :not_found, plain: "Not found: #{e.message}"
  rescue ActiveStorage::FileNotFoundError
    render status: :not_found, plain: "File missing from storage for manager #{params[:manager_id]} in dataset #{params[:ds_id]}"
  end

  def get_attachment
    file = ActiveStorage::Attachment.find(params[:id])
    send_data file.download, :filename => file.filename.to_s, :type => 'application/octet-stream'
  rescue ActiveRecord::RecordNotFound
    render status: :not_found, plain: "Attachment #{params[:id]} not found"
  rescue ActiveStorage::FileNotFoundError
    render status: :not_found, plain: "File missing from storage for attachment #{params[:id]} (#{file&.name})"
  end

  private
    # make sure that this is the worker that we allow
    # we don't use rails authenticity token here
    def worker_authenticity
      passcode = request.headers['x-api-key']
      if passcode.nil? || passcode != Rails.configuration.worker[:worker_passcode]
        render status: :unauthorized, plain: 'wrong passcode'
        return false
      end
    end

    def upload_compiled_params
      return params.permit({compiled_files: []})
    end
end

