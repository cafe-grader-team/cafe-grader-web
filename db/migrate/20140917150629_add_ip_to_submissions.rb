class AddIpToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :ip_address, :string
  end
end
