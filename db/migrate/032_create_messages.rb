class CreateMessages < ActiveRecord::Migration[4.2]
  def self.up
    create_table :messages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.column "sender_id", :integer
      t.column "receiver_id", :integer
      t.column "replying_message_id", :integer
      t.column "body", :text
      t.column "replied", :boolean   # this is for efficiency
      
      t.timestamps
    end
  end

  def self.down
    drop_table :messages
  end
end
