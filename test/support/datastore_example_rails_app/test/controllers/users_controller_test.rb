require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    super
    @user = create(:user, parent_key_id: 12345)
  end

  test 'should get index' do
    get users_url
    assert_response :success
  end

  test 'should get new' do
    get new_user_url
    assert_response :success
  end

  test 'should create user' do
    assert_difference('User.count_test_entities') do
      post users_url, params: { user: { name: 'User 2', email: 'user_2@test.com' } }
    end
    assert_redirected_to user_url(@user.id + 1)
  end

  test 'should show user' do
    get user_url(@user)
    assert_response :success
  end

  test 'should get edit' do
    get edit_user_url(@user)
    assert_response :success
  end

  test 'should update user' do
    patch user_url(@user), params: { user: { name: 'Updated User' } }
    assert_redirected_to user_url(@user)
  end

  test 'should destroy user' do
    assert_difference('User.count_test_entities', -1) do
      delete user_url(@user)
    end
    assert_redirected_to users_url
  end
end
