class ChangeUserLoginStringLimit < ActiveRecord::Migration[4.2]
  def self.up
    execute "ALTER TABLE `users` CHANGE `login` `login` VARCHAR( 50 )"
  end

  def self.down
    # don't have to revert
  end
end
