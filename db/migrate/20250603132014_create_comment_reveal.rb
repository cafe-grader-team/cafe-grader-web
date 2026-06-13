class CreateCommentReveal < ActiveRecord::Migration[7.0]
  def change
    create_table :comment_reveals, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.references :comment, null: false
      t.references :user, null: false
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_column :problems, :allow_hint, :boolean, default: true
    add_column :contests, :allow_hint, :boolean, default: true
  end
end
