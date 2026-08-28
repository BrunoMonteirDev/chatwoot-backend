class PermissionProfilePolicy < ApplicationPolicy
  %i[index show create update destroy].each do |action|
    define_method("#{action}?") { @account_user.administrator? }
  end
end
