class AddCountryToSitesAndUsers < ActiveRecord::Migration[4.2]
  def self.up
    add_column 'sites', 'country_id', :integer
    add_column 'sites', 'password', :string

    add_column 'users', 'country_id', :integer
  end

  def self.down
    remove_column 'users', 'country_id'

    remove_column 'sites', 'country_id'
    remove_column 'sites', 'password'
  end
end
