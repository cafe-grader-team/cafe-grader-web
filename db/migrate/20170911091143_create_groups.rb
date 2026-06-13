class CreateGroups < ActiveRecord::Migration[4.2]

  def change
    create_table :groups, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      t.string :name
      t.string :description
    end

    create_join_table :groups, :users, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
      # t.index [:group_id, :user_id]
      t.index [:user_id, :group_id]
    end

    create_join_table :problems, :groups, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci" do |t|
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
