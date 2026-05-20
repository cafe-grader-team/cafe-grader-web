class AddVivaTerminatedAtToSubmissions < ActiveRecord::Migration[8.0]
  def change
    # Set by Llm::VivaTurnAssist#handle_response when the model emits the
    # [[VIVA_ALERT]] sentinel (jailbreak attempt detected). Non-nil means
    # the interview was force-ended; grading still runs against the
    # partial transcript, and the student narrative explicitly mentions
    # the termination. Meaningful only for viva submissions.
    add_column :submissions, :viva_terminated_at, :datetime
    add_index  :submissions, :viva_terminated_at
  end
end
