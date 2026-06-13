class CreateLanguages < ActiveRecord::Migration[4.2]
  def self.up
    create_table :languages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column :name, :string, :limit => 10
      t.column :pretty_name, :string
    end

    Language.create(:name => "c", :pretty_name => "C")
    Language.create(:name => "cpp", :pretty_name => "C++")
    Language.create(:name => "pas", :pretty_name => "Pascal")
  end

  def self.down
    drop_table :languages
  end
end
