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
    parent_key = CloudDatastore.dataset.key('Parent', 212121)
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
    parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_ACCOUNT_ID)
    15.times do
      MockModel.create! name: Faker::Name.name, role: 1
    end
    15.times do
      MockModel.create! name: Faker::Name.name, role: 0, account_id: MOCK_ACCOUNT_ID
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
    parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_ACCOUNT_ID)
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
    assert entity.is_a?(Google::Cloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 1', entity.properties['name']
    assert_equal 'Entity 1', entity['name']
    mock_model_2 = MockModel.create! name: 'Entity 2', account_id: MOCK_ACCOUNT_ID
    entity = MockModel.find_entity(mock_model_2.id)
    assert_nil entity
    parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_ACCOUNT_ID)
    entity = MockModel.find_entity(mock_model_2.id, parent)
    assert entity.is_a?(Google::Cloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 2', entity.properties['name']
  end

  test 'find' do
    mock_model = MockModel.create! name: 'Entity'
    model_entity = MockModel.find(mock_model.id)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity', model_entity.name
  end

  test 'find by parent' do
    parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_ACCOUNT_ID)
    mock_model = MockModel.create! name: 'Entity With Parent', account_id: MOCK_ACCOUNT_ID
    model_entity = MockModel.find_by_parent(mock_model.id, parent)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity With Parent', model_entity.name
  end

  test 'from_entity' do
    entity = CloudDatastore.dataset.entity
    key = CloudDatastore.dataset.key('MockEntity', '12345')
    key.parent = CloudDatastore.dataset.key('ParentMockEntity', 11111)
    entity.key = key
    entity['name'] = 'A Mock Entity'
    entity['role'] = 1
    assert_nil MockModel.from_entity(nil)
    model_entity = MockModel.from_entity(entity)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    refute model_entity.role_changed?
  end

  test 'build query' do
    query = MockModel.build_query(kind: 'MockModel')
    assert query.class == Google::Cloud::Datastore::Query
    grpc = query.to_grpc
    assert_equal 'MockModel', grpc.kind[0].name
    assert_nil grpc.filter
    assert_nil grpc.limit
    assert_equal '', grpc.start_cursor
    assert_empty grpc.projection
    grpc = MockModel.build_query(where: ['name', '=', 'something']).to_grpc
    refute_nil grpc.filter
    grpc = MockModel.build_query(limit: 5).to_grpc
    refute_nil grpc.limit
    assert_equal 5, grpc.limit.value
    grpc = MockModel.build_query(select: 'name').to_grpc
    refute_nil grpc.projection
    assert_equal 1, grpc.projection.count
    grpc = MockModel.build_query(cursor: 'a_cursor').to_grpc
    refute_nil grpc.start_cursor
    parent_int_key = CloudDatastore.dataset.key('ParentMockModel', MOCK_ACCOUNT_ID)
    grpc = MockModel.build_query(ancestor: parent_int_key).to_grpc
    ancestor_filter = grpc.filter.composite_filter.filters.first
    assert_equal '__key__', ancestor_filter.property_filter.property.name
    assert_equal :HAS_ANCESTOR, ancestor_filter.property_filter.op
    key = ancestor_filter.property_filter.value.key_value.path[0]
    assert_equal parent_int_key.kind, key.kind
    assert_equal parent_int_key.id, key.id
    assert_equal key.id_type, :id
    parent_string_key = CloudDatastore.dataset.key('ParentMockModel', 'ABCDEF')
    grpc = MockModel.build_query(ancestor: parent_string_key).to_grpc
    ancestor_filter = grpc.filter.composite_filter.filters.first
    key = ancestor_filter.property_filter.value.key_value.path[0]
    assert_equal parent_string_key.kind, key.kind
    assert_equal key.id_type, :name
    assert_equal parent_string_key.name, key.name
  end
end
