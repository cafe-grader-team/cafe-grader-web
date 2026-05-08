class AddVivaArchivedAtToSubmissions < ActiveRecord::Migration[8.0]
  def change
    # Soft "archive" flag for viva submissions: nil means active/canonical
    # (the one that gates the "Start Viva" button on /main/list); a non-nil
    # timestamp means an admin set this attempt aside so the student can
    # take a fresh viva. The original transcript and grade record are
    # preserved for audit. The column is meaningful only for viva
    # submissions; non-viva submissions ignore it.
    add_column :submissions, :viva_archived_at, :datetime
    add_index  :submissions, :viva_archived_at
  end
end
