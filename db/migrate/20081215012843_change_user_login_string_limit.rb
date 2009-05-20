class ChangeUserLoginStringLimit < ActiveRecord::Migration
  def self.up
    execute "ALTER TABLE `users` CHANGE `login` `login` VARCHAR( 50 )"
  end

  def self.down
    # don't have to revert
  end
end
