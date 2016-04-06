require 'test_helper'

class ActiveModelCloudDatastoreTest < ActiveSupport::TestCase
  # Instance method tests.

  test 'persisted?' do
    mock_model = MockModel.new
    refute mock_model.persisted?
    mock_model.id = 1
    assert mock_model.persisted?
  end

  test 'update model attributes' do
    mock_model = MockModel.new
    assert_nil mock_model.name
    mock_model.update_model_attributes(name: 'Test')
    assert_equal 'Test', mock_model.name
  end

  test 'build entity' do
    mock_model = MockModel.new(name: 'Entity Test')
    entity = mock_model.build_entity
    assert_equal 'Entity Test', entity.properties['name']
    assert_equal 'MockModel', entity.key.kind
    assert_nil entity.key.id
    assert_nil entity.key.name
    assert_nil entity.key.parent
  end

  test 'build existing entity' do
    mock_model = MockModel.new(name: 'Entity Test')
    mock_model.id = 12345
    entity = mock_model.build_entity
    assert_equal 'Entity Test', entity.properties['name']
    assert_equal 'MockModel', entity.key.kind
    assert_equal 12345, entity.key.id
    assert_nil entity.key.name
    assert_nil entity.key.parent
  end

  test 'build entity with parent' do
    mock_model = MockModel.new(name: 'Entity Test')
    parent_key = Gcloud::Datastore::Key.new 'Parent', 212121
    entity = mock_model.build_entity(parent_key)
    assert_equal 'Entity Test', entity.properties['name']
    assert_equal 'MockModel', entity.key.kind
    assert_nil entity.key.id
    assert_equal 'Parent', entity.key.parent.kind
    assert_equal 212121, entity.key.parent.id
  end

  test 'save' do
    count = MockModel.count_test_entities
    mock_model = MockModel.new
    refute mock_model.save
    assert_equal count, MockModel.count_test_entities
    mock_model = MockModel.new(name: 'Save Test')
    assert mock_model.save
    assert_equal count + 1, MockModel.count_test_entities
    assert_not_nil mock_model.id
  end

  test 'update' do
    mock_model = MockModel.create! name: 'Update Test'
    id = mock_model.id
    count = MockModel.count_test_entities
    mock_model.update(name: 'different name')
    assert_equal 'different name', mock_model.name
    assert_equal id, mock_model.id
    assert_equal count, MockModel.count_test_entities
  end

  test 'destroy' do
    mock_model = MockModel.create! name: 'Destroy Test'
    count = MockModel.count_test_entities
    mock_model.destroy
    assert_equal count - 1, MockModel.count_test_entities
  end

  # Class method tests.

  test 'all' do
    parent = Gcloud::Datastore::Key.new 'ParentMockModel', MOCK_ACCOUNT_ID
    15.times do
      MockModel.create! name: Faker::Name.name
    end
    15.times do
      MockModel.create! name: Faker::Name.name, account_id: MOCK_ACCOUNT_ID
    end
    objects = MockModel.all
    assert_equal 30, objects.size
    objects = MockModel.all(ancestor: parent)
    assert_equal 15, objects.size
    name = objects[5].name
    objects = MockModel.all(ancestor: parent, where: ['name', '=', name])
    assert_equal 1, objects.size
    assert_equal name, objects.first.name
    assert objects.first.is_a?(MockModel)
  end

  test 'find in batches' do
    parent = Gcloud::Datastore::Key.new 'ParentMockModel', MOCK_ACCOUNT_ID
    10.times do
      MockModel.create! name: Faker::Name.name, account_id: MOCK_ACCOUNT_ID
    end
    mock_model = MockModel.create! name: 'MockModel', account_id: MOCK_ACCOUNT_ID
    MockModel.create! name: 'MockModel No Ancestor'
    objects, _cursor = MockModel.find_in_batches
    assert_equal MockModel, objects.first.class
    assert_equal 12, objects.count
    objects, _cursor = MockModel.find_in_batches(ancestor: parent)
    assert_equal 11, objects.count
    objects, start_cursor = MockModel.find_in_batches(ancestor: parent, limit: 7)
    assert_equal 7, objects.count
    refute_nil start_cursor # requested 7 results and there are 4 more
    objects, _cursor = MockModel.find_in_batches(ancestor: parent, cursor: start_cursor)
    assert_equal 4, objects.count
    objects, cursor = MockModel.find_in_batches(ancestor: parent, cursor: start_cursor, limit: 5)
    assert_equal 4, objects.count
    assert_nil cursor # query started where we left off, requested 5 results and there were 4 more
    objects, cursor = MockModel.find_in_batches(ancestor: parent, cursor: start_cursor, limit: 4)
    assert_equal 4, objects.count
    refute_nil cursor # query started where we left off, requested 4 results and there were 4 more
    objects, _cursor = MockModel.find_in_batches(ancestor: parent,
                                                 where: ['name', '=', mock_model.name])
    assert_equal 1, objects.count
    objects, _cursor = MockModel.find_in_batches(ancestor: parent, select: 'name', limit: 1)
    assert_equal 1, objects.count
    refute_nil objects.first.name
  end

  test 'find entity' do
    mock_model_1 = MockModel.create! name: 'Entity 1'
    entity = MockModel.find_entity(mock_model_1.id)
    assert entity.is_a?(Gcloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 1', entity.properties['name']
    assert_equal 'Entity 1', entity['name']
    mock_model_2 = MockModel.create! name: 'Entity 2', account_id: MOCK_ACCOUNT_ID
    entity = MockModel.find_entity(mock_model_2.id)
    assert_nil entity
    parent = Gcloud::Datastore::Key.new 'ParentMockModel', MOCK_ACCOUNT_ID
    entity = MockModel.find_entity(mock_model_2.id, parent)
    assert entity.is_a?(Gcloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 2', entity.properties['name']
  end

  test 'find' do
    mock_model = MockModel.create! name: 'Entity'
    model_entity = MockModel.find(mock_model.id)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity', model_entity.name
  end

  test 'find by parent' do
    parent = Gcloud::Datastore::Key.new 'ParentMockModel', MOCK_ACCOUNT_ID
    mock_model = MockModel.create! name: 'Entity With Parent', account_id: MOCK_ACCOUNT_ID
    model_entity = MockModel.find_by_parent(mock_model.id, parent)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity With Parent', model_entity.name
  end

  test 'build query' do
    query = MockModel.build_query(kind: 'MockModel')
    assert query.class == Gcloud::Datastore::Query
    proto = query.to_proto
    assert proto.kind.name.include? 'MockModel'
    assert_nil proto.filter
    assert_nil proto.limit
    assert_nil proto.start_cursor
    assert_nil proto.projection
    proto = MockModel.build_query(where: ['name', '=', 'something']).to_proto
    refute_nil proto.filter
    proto = MockModel.build_query(limit: 5).to_proto
    refute_nil proto.limit
    assert_equal 5, proto.limit
    proto = MockModel.build_query(select: 'name').to_proto
    refute_nil proto.projection
    assert_equal 1, proto.projection.count
    proto = MockModel.build_query(cursor: 'a_cursor').to_proto
    refute_nil proto.start_cursor
    parent_key = Gcloud::Datastore::Key.new 'ParentMockModel', MOCK_ACCOUNT_ID
    proto = MockModel.build_query(ancestor: parent_key).to_proto
    ancestor_filter = proto.filter.composite_filter.filter.first
    assert_equal '__key__', ancestor_filter.property_filter.property.name
    assert_equal Gcloud::Datastore::Proto::PropertyFilter::Operator::HAS_ANCESTOR,
                 ancestor_filter.property_filter.operator
    key = Gcloud::Datastore::Proto.from_proto_value(ancestor_filter.property_filter.value)
    assert_equal parent_key.kind, key.kind
    assert_equal parent_key.id, key.id
    assert_equal parent_key.name, key.name
  end
end
