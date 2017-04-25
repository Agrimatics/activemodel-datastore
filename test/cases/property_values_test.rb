require 'test_helper'

class PropertyValuesTest < ActiveSupport::TestCase
  test 'default property value' do
    mock_model = MockModel.new
    mock_model.name = nil
    mock_model.default_property_value(:name, 'Default Name')
    assert_equal 'Default Name', mock_model.name
    mock_model.name = 'A New Name'
    mock_model.default_property_value(:name, 'Default Name')
    assert_equal 'A New Name', mock_model.name
    mock_model.name = ''
    mock_model.default_property_value(:name, 'Default Name')
    assert_equal 'Default Name', mock_model.name
  end

  test 'format integer property value' do
    mock_model = MockModel.new(name: '34')
    mock_model.format_property_value(:name, :integer)
    assert_equal 34, mock_model.name
  end

  test 'format float property value' do
    mock_model = MockModel.new(name: '34')
    mock_model.format_property_value(:name, :float)
    assert_equal 34.0, mock_model.name
  end

  test 'format boolean property value' do
    mock_model = MockModel.new(role: '0')
    mock_model.format_property_value(:role, :boolean)
    refute mock_model.role
    mock_model.role = 0
    mock_model.format_property_value(:role, :boolean)
    refute mock_model.role
    mock_model.role = '1'
    mock_model.format_property_value(:role, :boolean)
    assert mock_model.role
    mock_model.role = 1
    mock_model.format_property_value(:role, :boolean)
    assert mock_model.role
    mock_model.role = true
    mock_model.format_property_value(:role, :boolean)
    assert mock_model.role
    mock_model.role = false
    mock_model.format_property_value(:role, :boolean)
    refute mock_model.role
  end
end
