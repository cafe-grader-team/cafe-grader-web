class CreateMessages < ActiveRecord::Migration
  def self.up
    create_table :messages do |t|
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
