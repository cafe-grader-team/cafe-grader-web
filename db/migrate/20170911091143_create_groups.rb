class CreateGroups < ActiveRecord::Migration

  def change
    create_table :groups do |t|
      t.string :name
      t.string :description
    end

    create_join_table :groups, :users do |t|
      # t.index [:group_id, :user_id]
      t.index [:user_id, :group_id]
    end

    create_join_table :problems, :groups do |t|
      # t.index [:problem_id, :group_id]
      t.index [:group_id, :problem_id]
    end

    reversible do |change|
      change.up do
        GraderConfiguration.where(key: 'system.use_problem_group').first_or_create(value_type: 'boolean', value: 'false',
                                                                                   description: 'If true, available problem to the user will be only ones associated with the group of the user');
      end

      change.down do
        GraderConfiguration.where(key: 'system.use_problem_group').destroy_all
      end
    end
  end
end
