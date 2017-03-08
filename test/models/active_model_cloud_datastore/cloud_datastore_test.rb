require 'test_helper'

class CloudDatastoreTest < ActiveSupport::TestCase
  # Instance method tests.

  test 'entity properties' do
    class MockModelNoAttr
      include ActiveModelCloudDatastore
    end
    mock_model = MockModelNoAttr.new
    assert_equal [], mock_model.entity_properties
  end

  test 'persisted?' do
    mock_model = MockModel.new
    refute mock_model.persisted?
    mock_model.id = 1
    assert mock_model.persisted?
  end

  test 'default' do
    mock_model = MockModel.new
    mock_model.default(:name, 'Default Name')
    assert_equal 'Default Name', mock_model.name
    mock_model.name = 'A New Name'
    mock_model.default(:name, 'Default Name')
    assert_equal 'A New Name', mock_model.name
  end

  test 'format' do
    mock_model = MockModel.new(name: '34')
    mock_model.format(:name, :integer)
    assert_equal 34, mock_model.name
    mock_model.format(:name, :float)
    assert_equal 34.0, mock_model.name
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
    mock_model = create(:mock_model)
    id = mock_model.id
    count = MockModel.count_test_entities
    mock_model.update(name: 'different name')
    assert_equal 'different name', mock_model.name
    assert_equal id, mock_model.id
    assert_equal count, MockModel.count_test_entities
  end

  test 'destroy' do
    mock_model = create(:mock_model)
    count = MockModel.count_test_entities
    mock_model.destroy
    assert_equal count - 1, MockModel.count_test_entities
  end

  # Class method tests.

  test 'all' do
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    15.times do
      create(:mock_model, name: Faker::Name.name)
    end
    15.times do
      mock_model = MockModel.new(attributes_for(:mock_model, name: Faker::Name.name))
      mock_model.save(parent)
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
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    10.times do
      mock_model = MockModel.new(attributes_for(:mock_model, name: Faker::Name.name))
      mock_model.save(parent)
    end
    mock_model = MockModel.new(attributes_for(:mock_model, name: 'MockModel'))
    mock_model.save(parent)
    create(:mock_model, name: 'MockModel No Ancestor')
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
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    entity = MockModel.find_entity(mock_model_1.id)
    assert entity.is_a?(Google::Cloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 1', entity.properties['name']
    assert_equal 'Entity 1', entity['name']
    assert_equal 'Entity 1', entity[:name]
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    mock_model_2 = MockModel.new(attributes_for(:mock_model, name: 'Entity 2'))
    mock_model_2.save(parent)
    entity = MockModel.find_entity(mock_model_2.id)
    assert_nil entity
    entity = MockModel.find_entity(mock_model_2.id, parent)
    assert entity.is_a?(Google::Cloud::Datastore::Entity), entity.inspect
    assert_equal 'Entity 2', entity.properties['name']
  end

  test 'find entities' do
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    mock_model_2 = create(:mock_model, name: 'Entity 2')
    entities = MockModel.find_entities(mock_model_1.id, mock_model_2.id)
    assert_equal 2, entities.size
    entities.each { |entity| assert entity.is_a?(Google::Cloud::Datastore::Entity), entity.inspect }
    assert_equal 'Entity 1', entities[0][:name]
    assert_equal 'Entity 2', entities[1][:name]
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    mock_model_3 = MockModel.new(attributes_for(:mock_model, name: 'Entity 3'))
    mock_model_3.save(parent)
    entities = MockModel.find_entities([mock_model_1.id, mock_model_2.id, mock_model_3.id])
    assert_equal 2, entities.size
    entities = MockModel.find_entities(mock_model_2.id, mock_model_3.id, parent: parent)
    assert_equal 1, entities.size
    assert_equal 'Entity 3', entities[0][:name]
  end

  test 'find' do
    mock_model = create(:mock_model, name: 'Entity')
    model_entity = MockModel.find(mock_model.id)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity', model_entity.name
  end

  test 'find by parent' do
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    mock_model = MockModel.new(attributes_for(:mock_model, name: 'Entity With Parent'))
    mock_model.save(parent)
    model_entity = MockModel.find_by_parent(mock_model.id, parent)
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Entity With Parent', model_entity.name
  end

  test 'find all by parent' do
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    mock_model_1 = MockModel.new(attributes_for(:mock_model, name: 'Entity 1 With Parent'))
    mock_model_1.save(parent)
    mock_model_2 = MockModel.new(attributes_for(:mock_model, name: 'Entity 2 With Parent'))
    mock_model_2.save(parent)
    model_entities = MockModel.find_all_by_parent([mock_model_1.id, mock_model_2.id], parent)
    model_entities.each { |model| assert model.is_a?(MockModel), model.inspect }
    assert_equal 'Entity 1 With Parent', model_entities[0].name
    assert_equal 'Entity 2 With Parent', model_entities[1].name
  end

  test 'find by' do
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert_nil model_entity
    create(:mock_model, name: 'Billy Bob')
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert model_entity.is_a?(MockModel), model_entity.inspect
    assert_equal 'Billy Bob', model_entity.name
    parent = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    mock_model_2 = MockModel.new(attributes_for(:mock_model, name: 'Entity With Parent'))
    mock_model_2.save(parent)
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert_equal 'Billy Bob', model_entity.name
    model_entity = MockModel.find_by(name: 'Billy Bob', ancestor: parent)
    assert_nil model_entity
    model_entity = MockModel.find_by(name: 'Entity With Parent', ancestor: parent)
    assert_equal 'Entity With Parent', model_entity.name
  end

  test 'from_entity' do
    entity = CloudDatastore.dataset.entity
    key = CloudDatastore.dataset.key('MockEntity', '12345')
    key.parent = CloudDatastore.dataset.key('Parent', 11111)
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
    parent_int_key = CloudDatastore.dataset.key('Parent', MOCK_ACCOUNT_ID)
    grpc = MockModel.build_query(ancestor: parent_int_key).to_grpc
    ancestor_filter = grpc.filter.composite_filter.filters.first
    assert_equal '__key__', ancestor_filter.property_filter.property.name
    assert_equal :HAS_ANCESTOR, ancestor_filter.property_filter.op
    key = ancestor_filter.property_filter.value.key_value.path[0]
    assert_equal parent_int_key.kind, key.kind
    assert_equal parent_int_key.id, key.id
    assert_equal key.id_type, :id
    parent_string_key = CloudDatastore.dataset.key('Parent', 'ABCDEF')
    grpc = MockModel.build_query(ancestor: parent_string_key).to_grpc
    ancestor_filter = grpc.filter.composite_filter.filters.first
    key = ancestor_filter.property_filter.value.key_value.path[0]
    assert_equal parent_string_key.kind, key.kind
    assert_equal key.id_type, :name
    assert_equal parent_string_key.name, key.name
  end
end
