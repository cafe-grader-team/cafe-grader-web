class AddIpToSubmissions < ActiveRecord::Migration[4.2]
  def change
    add_column :submissions, :ip_address, :string
  end
end
