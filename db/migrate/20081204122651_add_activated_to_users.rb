class AddActivatedToUsers < ActiveRecord::Migration
  def self.up
    add_column :users, :activated, :boolean, :default => 0

    User.reset_column_information

    User.all.each do |user|

      # disable validation
      class <<user
        def valid?
          return true
        end
      end

      user.activated = true
      user.save
    end
  end


  def self.down
    remove_column :users, :activated
  end
end
