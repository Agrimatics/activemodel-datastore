require 'test_helper'

class NestedAttrTest < ActiveSupport::TestCase
  def setup
    super
    MockModelParent.clear_validators!
    MockModelParent.validates_associated(:mock_models)
    @mock_model_parent = MockModelParent.new(name: 'whatever')
    MockModel.clear_validators!
    MockModel.validates :name, presence: true
  end

  # Instance method tests.
  test 'nested_attributes?' do
    MockModelParent.validates_associated(:mock_models)
    @mock_model_parent.mock_models = [MockModel.new(name: 'M1'), MockModel.new(name: 'M2')]
    refute @mock_model_parent.nested_attributes?
    @mock_model_parent.nested_attributes = :mock_model
    refute @mock_model_parent.nested_attributes?
    @mock_model_parent.nested_attributes = [:mock_model]
    assert @mock_model_parent.nested_attributes?
  end

  test 'should extract and return nested models' do
    assert_empty @mock_model_parent.nested_models
    @mock_model_parent.mock_models = [m1 = MockModel.new(name: 'M'), m2 = MockModel.new(name: 'M2')]
    assert_empty @mock_model_parent.nested_models
    @mock_model_parent.nested_attributes = [:mock_models]
    nested_models = @mock_model_parent.nested_models
    assert_equal 2, nested_models.size
    assert_equal m1, nested_models[0]
    assert_equal m2, nested_models[1]
  end

  test 'should return a list of nested model class names' do
    @mock_model_parent.mock_models = [MockModel.new(name: 'M'), MockModel.new(name: 'M2')]
    @mock_model_parent.nested_attributes = [:mock_models]
    classes = @mock_model_parent.nested_model_class_names
    assert_equal 1, classes.size
    assert_equal ['MockModel'], classes
  end

  test 'should return a list of nested error objects' do
    @mock_model_parent.mock_models = [MockModel.new, MockModel.new, MockModel.new(name: 'M3')]
    @mock_model_parent.nested_attributes = [:mock_models]
    errors = @mock_model_parent.nested_errors
    assert errors.is_a? Array
    # Each model should have an ActiveModel::Errors object, regardless of validation status
    assert_equal 3, errors.size
  end

  test 'assigns new nested objects with hash attributes' do
    assert_nil @mock_model_parent.nested_attributes
    params = { '0' => { name: 'Mock Model 1', role: 0 },
               '1' => { name: 'Mock Model 2', role: 1 } }
    @mock_model_parent.assign_nested_attributes(:mock_models, params)
    assert @mock_model_parent.mock_models.is_a? Array
    assert_equal 2, @mock_model_parent.mock_models.size
    mock_model_1 = @mock_model_parent.mock_models[0]
    mock_model_2 = @mock_model_parent.mock_models[1]
    assert mock_model_1.is_a? MockModel
    assert mock_model_2.is_a? MockModel
    assert_equal 'Mock Model 1', mock_model_1.name
    assert_equal 0, mock_model_1.role
    assert_equal 'Mock Model 2', mock_model_2.name
    assert_equal 1, mock_model_2.role
    assert_equal [:mock_models], @mock_model_parent.nested_attributes
  end

  test 'updates existing nested objects' do
    mock_model_1 = create(:mock_model, name: 'Model 1', role: 0)
    mock_model_2 = create(:mock_model, name: 'Model 2', role: 0)
    @mock_model_parent.mock_models = [mock_model_1, mock_model_2]
    params_1 = ActionController::Parameters.new(id: mock_model_1.id, name: 'Model 1A', role: 1)
    params_2 = ActionController::Parameters.new(id: mock_model_2.id, name: 'Model 2A', role: 1)
    form_params = ActionController::Parameters.new('0' => params_1, '1' => params_2)
    params = form_params.permit('0' => [:id, :name, :role], '1' => [:id, :name, :role])
    @mock_model_parent.assign_nested_attributes(:mock_models, params)
    assert @mock_model_parent.mock_models.is_a? Array
    assert_equal 2, @mock_model_parent.mock_models.size
    mock_model_1 = @mock_model_parent.mock_models[0]
    mock_model_2 = @mock_model_parent.mock_models[1]
    assert_equal 'Model 1A', mock_model_1.name
    assert_equal 1, mock_model_1.role
    assert_equal 'Model 2A', mock_model_2.name
    assert_equal 1, mock_model_2.role
  end

  test 'marks a deleted object for destruction' do
    mock_model_1 = create(:mock_model, name: 'Model 1', role: 0)
    mock_model_2 = create(:mock_model, name: 'Model 2', role: 0)
    @mock_model_parent.mock_models = [mock_model_1, mock_model_2]
    params_1 = ActionController::Parameters.new(id: mock_model_1.id, _destroy: '1')
    form_params = ActionController::Parameters.new('0' => params_1)
    params = form_params.permit('0' => [:id, :name, :role, :_destroy])
    @mock_model_parent.assign_nested_attributes(:mock_models, params)
    assert mock_model_1.marked_for_destruction
    refute mock_model_2.marked_for_destruction
  end

  test 'does not respond to underscore_destroy without id' do
    params = { '0' => { name: 'Mock Model 1', role: 0, _destroy: '1' } }
    @mock_model_parent.assign_nested_attributes(:mock_models, params)
    mock_model_1 = @mock_model_parent.mock_models[0]
    refute mock_model_1.marked_for_destruction
  end

  # Class method tests.

  test 'validates associated' do
    @mock_model_parent.mock_models = [m = MockModel.new, m2 = MockModel.new(name: 'Model 2'),
                                      m3 = MockModel.new, m4 = MockModel.new(name: 'Model 4')]
    assert !@mock_model_parent.valid?
    assert @mock_model_parent.errors[:mock_models].any?
    assert_equal 1, m.errors.count
    assert_equal 0, m2.errors.count
    assert_equal 1, m3.errors.count
    assert_equal 0, m4.errors.count
    m.name = m3.name = 'non-empty'
    assert @mock_model_parent.valid?
  end
end

class MockModelParent
  include ActiveModelNestedAttr
  attr_accessor :name
  attr_accessor :mock_models
end
