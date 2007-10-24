class CreateLanguages < ActiveRecord::Migration
  def self.up
    create_table :languages do |t|
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
