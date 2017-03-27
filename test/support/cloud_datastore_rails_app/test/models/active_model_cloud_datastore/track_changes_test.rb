require 'test_helper'

class TrackChangesTest < ActiveSupport::TestCase
  def setup
    super
    create(:mock_model, name: 25.5, role: 1)
  end

  test 'track changes with single attribute' do
    mock_model = MockModel.all.first
    refute mock_model.exclude_from_save?
    refute mock_model.values_changed?
    assert mock_model.exclude_from_save?

    mock_model.name = '25.5'
    assert mock_model.changed?
    mock_model.name = 25.5
    assert mock_model.changed?
    refute mock_model.values_changed?
    assert mock_model.exclude_from_save?

    mock_model.name = 25.4
    assert mock_model.values_changed?
    refute mock_model.exclude_from_save?
  end

  test 'track changes with multiple attributes' do
    mock_model = MockModel.all.first
    refute mock_model.exclude_from_save?
    refute mock_model.changed?
    mock_model.name = 20
    mock_model.role = '1'
    mock_model.role = 1
    assert mock_model.values_changed?
    refute mock_model.exclude_from_save?
  end

  test 'track changes with marked for destruction' do
    mock_model = MockModel.all.first
    mock_model.marked_for_destruction = true
    assert mock_model.values_changed?
    refute mock_model.exclude_from_save?
    mock_model.name = '75'
    mock_model.name = 75
    assert mock_model.values_changed?
    refute mock_model.exclude_from_save?
  end

  test 'remove unmodified children' do
    class MockModelParentWithTracking
      include ActiveModel::Datastore
      attr_accessor :name
      attr_accessor :mock_models
      enable_change_tracking :name
    end
    mock_model_parent = MockModelParentWithTracking.new(name: 'whatever')
    mock_model_parent.mock_models = [MockModel.new(name: 'M1'), MockModel.new(name: 'M2')]
    mock_model_parent.nested_attributes = [:mock_models]
    mock_model_parent.reload!
    mock_model_parent.mock_models.each(&:reload!)
    refute mock_model_parent.values_changed?
    mock_model_parent.remove_unmodified_children
    assert_equal 0, mock_model_parent.mock_models.size
    mock_model_parent.mock_models = [MockModel.new(name: 'M1'), MockModel.new(name: 'M2')]
    mock_model_parent.nested_attributes = [:mock_models]
    mock_model_parent.mock_models.each(&:reload!)
    mock_model_parent.mock_models.first.name = 'M1 Modified'
    mock_model_parent.remove_unmodified_children
    assert_equal 1, mock_model_parent.mock_models.size
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
    mock_model = MockModel.all.first
    refute mock_model.changed?
    mock_model.name = 'Billy'
    assert mock_model.changed?
    assert mock_model.name_changed?
    assert mock_model.name_changed?(from: 25.5, to: 'Billy')
    assert_equal 25.5, mock_model.name_was
  end
end
