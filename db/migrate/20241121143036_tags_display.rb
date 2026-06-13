class TagsDisplay < ActiveRecord::Migration[7.0]
  def change
    add_column :tags, :primary, :bool, default: false
    add_column :groups, :hidden, :bool, default: false
    change_column_default :tags, :color, from: nil, to: '#6C757D'
  end
end
