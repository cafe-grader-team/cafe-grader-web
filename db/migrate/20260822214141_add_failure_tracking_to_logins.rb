class AddFailureTrackingToLogins < ActiveRecord::Migration[8.0]
  def change
    # Failed attempts get a row too (success: false); attempted_login keeps
    # the submitted login string even when it matches no user.
    add_column :logins, :success, :boolean, null: false, default: true
    add_column :logins, :attempted_login, :string
  end
end
