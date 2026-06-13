class CreateTags < ActiveRecord::Migration[4.2]
  def change
    create_table :tags, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :public

      t.timestamps null: false
    end
  end
end
