class Current < ActiveSupport::CurrentAttributes
  attribute :user, :ip, :actor_note, :audit_disabled
end
