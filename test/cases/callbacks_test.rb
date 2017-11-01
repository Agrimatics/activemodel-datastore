require 'test_helper'

class CallbacksTest < ActiveSupport::TestCase
  def setup
    super
    @mock_model = MockModel.new
    @mock_model.name = 'Initial Name'
    @mock_model.namespace = nil
  end

  test 'before validation callback on save' do
    class << @mock_model
      before_validation { self.name = nil }
    end
    refute @mock_model.save
    assert_nil @mock_model.name
    assert_equal 0, MockModel.count_test_entities(namespace: @mock_model.namespace)
  end

  test 'after validation callback on save' do
    class << @mock_model
      after_validation { self.name = nil }
    end
    assert @mock_model.save
    assert_nil @mock_model.name
    assert_equal 1, MockModel.count_test_entities(namespace: @mock_model.namespace)
  end

  test 'before save callback' do
    class << @mock_model
      before_save { self.name = 'Name changed before save' }
    end
    assert @mock_model.save
    assert_equal 'Name changed before save', @mock_model.name
    ns = @mock_model.namespace
    assert_equal 'Name changed before save', MockModel.all(namespace: ns).first.name
  end

  test 'after save callback' do
    class << @mock_model
      after_save { self.name = 'Name changed after save' }
    end
    assert @mock_model.save
    assert_equal 'Name changed after save', @mock_model.name
    ns = @mock_model.namespace
    assert_equal 'Initial Name', MockModel.all(namespace: ns).first.name
  end

  test 'before validation callback on update' do
    class << @mock_model
      before_validation { self.name = nil }
    end
    refute @mock_model.update(name: 'Different Name')
    assert_nil @mock_model.name
  end

  test 'after validation callback on update' do
    class << @mock_model
      after_validation { self.name = nil }
    end
    assert @mock_model.update(name: 'Different Name')
    assert_nil @mock_model.name
  end

  test 'before update callback' do
    class << @mock_model
      before_update { self.name = 'Name changed before update' }
    end
    assert @mock_model.update(name: 'This name should get changed')
    assert_equal 'Name changed before update', @mock_model.name
    ns = @mock_model.namespace
    assert_equal 'Name changed before update', MockModel.all(namespace: ns).first.name
  end

  test 'after update callback' do
    class << @mock_model
      after_update { self.name = 'Name changed after update' }
    end
    assert @mock_model.update(name: 'This name should make it into datastore')
    assert_equal 'Name changed after update', @mock_model.name
    ns = @mock_model.namespace
    assert_equal 'This name should make it into datastore', MockModel.all(namespace: ns).first.name
  end
end
