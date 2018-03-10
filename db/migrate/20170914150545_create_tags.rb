class CreateTags < ActiveRecord::Migration
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :public

      t.timestamps null: false
    end
  end
end
