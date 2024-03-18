require 'test_helper'

class ActiveModel::BatchOperationTest < ActiveSupport::TestCase
  def setup
    super
    @mock_models = %w[alice bob charlie].map do |name|
      MockModel.new(name: name, parent_key_id: MOCK_PARENT_ID)
    end
  end

  test 'batch save' do
    count = MockModel.count_test_entities
    assert ActiveModel::Datastore.save_all(@mock_models)
    assert_equal count + @mock_models.count, MockModel.count_test_entities
    @mock_models.each do |mock_model|
      assert_not_nil mock_model.id
      key = CloudDatastore.dataset.key 'MockModel', mock_model.id
      key.parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_PARENT_ID)
      entity = CloudDatastore.dataset.find key
      assert_equal mock_model.id, entity.key.id
      assert_equal 'MockModel', entity.key.kind
      assert_equal 'ParentMockModel', entity.key.parent.kind
      assert_equal MOCK_PARENT_ID, entity.key.parent.id
    end
  end

  test 'before validation callback on batch save' do
    @mock_models.each do |mock_model|
      class << mock_model
        before_validation { self.name = nil }
      end
    end
    refute ActiveModel::Datastore.save_all(@mock_models)
    @mock_models.each do |mock_model|
      assert_nil mock_model.name
    end
    assert_equal 0, MockModel.count_test_entities
  end

  test 'after validation callback on batch save' do
    @mock_models.each do |mock_model|
      class << mock_model
        after_validation { self.name = nil }
      end
    end
    assert ActiveModel::Datastore.save_all(@mock_models)
    @mock_models.each do |mock_model|
      assert_nil mock_model.name
    end
    assert_equal @mock_models.count, MockModel.count_test_entities
  end

  test 'before save callback on batch save' do
    @mock_models.each do |mock_model|
      class << mock_model
        before_save { self.name = name.upcase }
      end
    end
    assert ActiveModel::Datastore.save_all(@mock_models)
    @mock_models.each_with_index do |mock_model, index|
      assert_equal mock_model.name, %w[alice bob charlie][index].upcase
      assert_equal MockModel.all[index].name, %w[alice bob charlie][index].upcase
    end
  end

  test 'after save callback on batch save' do
    @mock_models.each do |mock_model|
      class << mock_model
        after_save { self.name = name.upcase }
      end
    end
    assert ActiveModel::Datastore.save_all(@mock_models)
    @mock_models.each_with_index do |mock_model, index|
      assert_equal mock_model.name, %w[alice bob charlie][index].upcase
      assert_equal MockModel.all[index].name, %w[alice bob charlie][index]
    end
  end
end
