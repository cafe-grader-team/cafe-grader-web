class AddOutputToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :output, :text
  end
end
