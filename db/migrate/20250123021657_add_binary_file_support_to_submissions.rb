class AddBinaryFileSupportToSubmissions < ActiveRecord::Migration[7.0]
  def change
    add_column :submissions, :content_type, :string
    add_column :languages, :binary, :boolean, default: false
    reversible do |dir|
      dir.up do
        change_column :submissions, :binary, :longblob
      end
      dir.down do
        change_column :submissions, :binary, :blob
      end
    end
  end
end
