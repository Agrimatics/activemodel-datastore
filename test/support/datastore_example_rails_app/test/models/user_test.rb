require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'user attributes must not be empty' do
    attr = attributes_for(:user).except(:email, :enabled, :name, :role)
    user = User.new(attr)
    assert user.invalid?
    assert user.errors[:name].any?
    assert user.errors[:email].any?
    assert user.errors[:role].any?
    assert_equal 3, user.errors.messages.size
    assert user.enabled
  end

  test 'user values should be formatted correctly' do
    user = User.new(attributes_for(:user))
    assert user.valid?, user.errors.messages
    user.role = 1.to_s
    assert user.valid?
    assert_equal 1, user.role
    assert user.role.is_a?(Integer)
  end

  test 'user entity properties include' do
    assert User.method_defined? :entity_properties
    user = User.new
    assert user.entity_properties.include? 'email'
    assert user.entity_properties.include? 'enabled'
    assert user.entity_properties.include? 'name'
    assert user.entity_properties.include? 'role'
  end
end
