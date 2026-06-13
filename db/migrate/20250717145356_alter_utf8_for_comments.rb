class AlterUtf8ForComments < ActiveRecord::Migration[8.0]
  def up
    execute "ALTER TABLE comment_reveals CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    execute "ALTER TABLE comments CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
  end

  def down
    # do nothing
  end
end
