require 'test_helper'

class ExcludedIndexesTest < ActiveSupport::TestCase
  test 'responds to no index attributes' do
    mock_model = MockModel.new
    assert mock_model.respond_to? :no_index_attributes
    assert_empty mock_model.no_index_attributes
  end

  test 'excludes index of single attribute' do
    MockModel.no_indexes :name
    mock_model = MockModel.new
    assert_includes mock_model.no_index_attributes, 'name'
    assert_equal 1, mock_model.no_index_attributes.size
  end

  test 'excludes index of multiple attributes' do
    MockModel.no_indexes :name, :role
    mock_model = MockModel.new
    assert_includes mock_model.no_index_attributes, 'name'
    assert_includes mock_model.no_index_attributes, 'role'
    assert_equal 2, mock_model.no_index_attributes.size
  end
end
