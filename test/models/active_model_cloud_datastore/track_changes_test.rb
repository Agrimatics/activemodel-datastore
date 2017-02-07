require 'test_helper'

class TrackChangesTest < ActiveSupport::TestCase
  test 'track changes with single attribute' do
    create(:mock_model, name: 25.5)
    mock_model = MockModel.all.first
    refute mock_model.exclude_from_save?
    mock_model.track_changes
    refute mock_model.exclude_from_save?

    mock_model.name = '25.5'
    assert mock_model.changed?
    mock_model.name = 25.5
    assert mock_model.changed?
    mock_model.track_changes
    assert mock_model.exclude_from_save?

    mock_model.name = 25.4
    mock_model.track_changes
    refute mock_model.exclude_from_save?
  end

  test 'track changes with multiple attributes' do
    create(:mock_model, name: 25.5, role: 1)
    mock_model = MockModel.all.first
    refute mock_model.exclude_from_save?
    refute mock_model.changed?
    mock_model.name = 20
    mock_model.role = '1'
    mock_model.role = 1
    mock_model.track_changes
    refute mock_model.exclude_from_save?
  end

  test 'track changes with marked for destruction' do
    create(:mock_model, name: 75)
    mock_model = MockModel.all.first
    mock_model.marked_for_destruction = true
    mock_model.track_changes
    refute mock_model.exclude_from_save?
    mock_model.name = '75'
    mock_model.name = 75
    mock_model.track_changes
    refute mock_model.exclude_from_save?
  end

  test 'change tracking on new object' do
    mock_model = MockModel.new
    refute mock_model.changed?
    mock_model.name = 'Bryce'
    assert mock_model.changed?
    assert mock_model.name_changed?
    assert mock_model.name_changed?(from: nil, to: 'Bryce')
    assert_nil mock_model.name_was
    assert_equal [nil, 'Bryce'], mock_model.name_change
    mock_model.name = 'Billy'
    assert_equal [nil, 'Billy'], mock_model.name_change
  end

  test 'change tracking on existing object' do
    create(:mock_model, name: 'Bryce')
    mock_model = MockModel.all.first
    refute mock_model.changed?
    mock_model.name = 'Billy'
    assert mock_model.changed?
    assert mock_model.name_changed?
    assert mock_model.name_changed?(from: 'Bryce', to: 'Billy')
    assert_equal 'Bryce', mock_model.name_was
  end
end
