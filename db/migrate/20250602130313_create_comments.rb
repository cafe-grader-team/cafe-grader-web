class CreateComments < ActiveRecord::Migration[7.0]
  def change
    create_table :comments, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.references :commentable, null: false, polymorphic: true
      t.references :user, null: false
      t.integer :kind, default: 0
      t.boolean :enabled, default: true
      t.float :cost
      t.string :title
      t.text :body, limit: 16.megabytes - 1
      t.text :remark

      t.timestamps
    end
  end
end
