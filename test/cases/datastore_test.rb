require 'test_helper'

class ActiveModel::DatastoreTest < ActiveSupport::TestCase
  # Packaging tests.

  test 'test that it has a version number' do
    refute_nil ::ActiveModel::Datastore::VERSION
  end

  # Instance method tests.

  test 'entity properties' do
    class MockModelNoAttr
      include ActiveModel::Datastore
    end
    mock_model = MockModelNoAttr.new
    assert_equal [], mock_model.entity_properties
  end

  test 'parent?' do
    mock_model = MockModel.new
    refute mock_model.parent?
    mock_model.parent_key_id = 12345
    assert mock_model.parent?
  end

  test 'persisted?' do
    mock_model = MockModel.new
    refute mock_model.persisted?
    mock_model.id = 1
    assert mock_model.persisted?
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

  test 'build entity with parent key id' do
    mock_model = MockModel.new(name: 'Entity Test', parent_key_id: MOCK_PARENT_ID)
    entity = mock_model.build_entity
    assert_equal 'Entity Test', entity.properties['name']
    assert_equal 'MockModel', entity.key.kind
    assert_nil entity.key.id
    assert_nil entity.key.name
    assert_nil entity.key.id
    assert_equal 'ParentMockModel', entity.key.parent.kind
    assert_equal MOCK_PARENT_ID, entity.key.parent.id
  end

  test 'build entity with index exclusion' do
    MockModel.no_indexes :name
    name = Faker::Lorem.characters(1600)
    mock_model = MockModel.new(name: name)
    mock_model.save
    entity = mock_model.build_entity
    assert_equal name, entity.properties['name']
    assert entity.exclude_from_indexes? 'name'
    assert entity.exclude_from_indexes? :name
    refute entity.exclude_from_indexes? :role
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
    assert_nil mock_model.parent_key_id
  end

  test 'save with parent' do
    count = MockModel.count_test_entities
    parent_key = CloudDatastore.dataset.key('Company', MOCK_PARENT_ID)
    mock_model = MockModel.new(name: 'Save Test')
    assert mock_model.save(parent_key)
    assert_equal count + 1, MockModel.count_test_entities
    assert_not_nil mock_model.id
    assert_equal MOCK_PARENT_ID, mock_model.parent_key_id
    key = CloudDatastore.dataset.key 'MockModel', mock_model.id
    key.parent = parent_key
    entity = CloudDatastore.dataset.find key
    assert_equal mock_model.id, entity.key.id
    assert_equal 'MockModel', entity.key.kind
    assert_equal 'Company', entity.key.parent.kind
    assert_equal MOCK_PARENT_ID, entity.key.parent.id
  end

  test 'save within default entity group' do
    count = MockModel.count_test_entities
    mock_model = MockModel.new(name: 'Ancestor Test', parent_key_id: MOCK_PARENT_ID)
    assert mock_model.save
    assert_equal count + 1, MockModel.count_test_entities
    assert_not_nil mock_model.id
    key = CloudDatastore.dataset.key 'MockModel', mock_model.id
    key.parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_PARENT_ID)
    entity = CloudDatastore.dataset.find key
    assert_equal mock_model.id, entity.key.id
    assert_equal 'MockModel', entity.key.kind
    assert_equal 'ParentMockModel', entity.key.parent.kind
    assert_equal MOCK_PARENT_ID, entity.key.parent.id
  end

  test 'update' do
    mock_model = create(:mock_model)
    id = mock_model.id
    count = MockModel.count_test_entities
    mock_model.update(name: 'different name')
    assert_equal id, mock_model.id
    assert_equal count, MockModel.count_test_entities
    key = CloudDatastore.dataset.key 'MockModel', mock_model.id
    entity = CloudDatastore.dataset.find key
    assert_equal id, entity.key.id
    assert_equal 'MockModel', entity.key.kind
    assert_nil entity.key.parent
    assert_equal 'different name', entity['name']
  end

  test 'update within entity group' do
    mock_model = create(:mock_model, parent_key_id: MOCK_PARENT_ID)
    id = mock_model.id
    count = MockModel.count_test_entities
    mock_model.update(name: 'different name')
    assert_equal id, mock_model.id
    assert_equal count, MockModel.count_test_entities
    key = CloudDatastore.dataset.key 'MockModel', mock_model.id
    key.parent = CloudDatastore.dataset.key('ParentMockModel', MOCK_PARENT_ID)
    entity = CloudDatastore.dataset.find key
    assert_equal id, entity.key.id
    assert_equal 'MockModel', entity.key.kind
    assert_equal 'ParentMockModel', entity.key.parent.kind
    assert_equal 'different name', entity['name']
  end

  test 'destroy' do
    mock_model = create(:mock_model)
    count = MockModel.count_test_entities
    mock_model.destroy
    assert_equal count - 1, MockModel.count_test_entities
  end

  test 'destroy within entity group' do
    mock_model = create(:mock_model, parent_key_id: MOCK_PARENT_ID)
    count = MockModel.count_test_entities
    mock_model.destroy
    assert_equal count - 1, MockModel.count_test_entities
  end

  # Class method tests.
  test 'parent key' do
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    assert parent_key.is_a? Google::Cloud::Datastore::Key
    assert_equal 'ParentMockModel', parent_key.kind
    assert_equal MOCK_PARENT_ID, parent_key.id
  end

  test 'all' do
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    15.times do
      create(:mock_model, name: Faker::Name.name)
    end
    15.times do
      attr = attributes_for(:mock_model, name: Faker::Name.name, parent_key_id: MOCK_PARENT_ID)
      mock_model = MockModel.new(attr)
      mock_model.save
    end
    objects = MockModel.all
    assert_equal 30, objects.size
    objects = MockModel.all(ancestor: parent_key)
    assert_equal 15, objects.size
    name = objects[5].name
    objects = MockModel.all(ancestor: parent_key, where: ['name', '=', name])
    assert_equal 1, objects.size
    assert_equal name, objects.first.name
    assert objects.first.is_a?(MockModel)
  end

  test 'find in batches' do
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    10.times do
      attr = attributes_for(:mock_model, name: Faker::Name.name, parent_key_id: MOCK_PARENT_ID)
      mock_model = MockModel.new(attr)
      mock_model.save
    end
    attr = attributes_for(:mock_model, name: 'MockModel', parent_key_id: MOCK_PARENT_ID)
    mock_model = MockModel.new(attr)
    mock_model.save
    create(:mock_model, name: 'MockModel No Ancestor')
    objects = MockModel.all
    assert_equal MockModel, objects.first.class
    assert_equal 12, objects.count
    objects = MockModel.all(ancestor: parent_key)
    assert_equal 11, objects.count
    objects, start_cursor = MockModel.all(ancestor: parent_key, limit: 7)
    assert_equal 7, objects.count
    refute_nil start_cursor # requested 7 results and there are 4 more
    objects = MockModel.all(ancestor: parent_key, cursor: start_cursor)
    assert_equal 4, objects.count
    objects, cursor = MockModel.all(ancestor: parent_key, cursor: start_cursor, limit: 5)
    assert_equal 4, objects.count
    assert_nil cursor # query started where we left off, requested 5 results and there were 4 more
    objects, cursor = MockModel.all(ancestor: parent_key, cursor: start_cursor, limit: 4)
    assert_equal 4, objects.count
    refute_nil cursor # query started where we left off, requested 4 results and there were 4 more
    objects = MockModel.all(ancestor: parent_key, where: ['name', '=', mock_model.name])
    assert_equal 1, objects.count
    objects, _cursor = MockModel.all(ancestor: parent_key, select: 'name', limit: 1)
    assert_equal 1, objects.count
    refute_nil objects.first.name
  end

  test 'find entity' do
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    entity = MockModel.find_entity(mock_model_1.id)
    assert entity.is_a?(Google::Cloud::Datastore::Entity)
    assert_equal 'Entity 1', entity.properties['name']
    assert_equal 'Entity 1', entity['name']
    assert_equal 'Entity 1', entity[:name]
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    attr = attributes_for(:mock_model, name: 'Entity 2', parent_key_id: MOCK_PARENT_ID)
    mock_model_2 = MockModel.new(attr)
    mock_model_2.save
    entity = MockModel.find_entity(mock_model_2.id)
    assert_nil entity
    entity = MockModel.find_entity(mock_model_2.id, parent_key)
    assert entity.is_a?(Google::Cloud::Datastore::Entity)
    assert_equal 'Entity 2', entity.properties['name']
    assert_nil MockModel.find_entity(mock_model_2.id + 1)
  end

  test 'find entities' do
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    mock_model_2 = create(:mock_model, name: 'Entity 2')
    entities = MockModel.find_entities(mock_model_1.id, mock_model_2.id)
    assert_equal 2, entities.size
    entities.each { |entity| assert entity.is_a?(Google::Cloud::Datastore::Entity) }
    assert_equal 'Entity 1', entities[0][:name]
    assert_equal 'Entity 2', entities[1][:name]
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    attr = attributes_for(:mock_model, name: 'Entity 3', parent_key_id: MOCK_PARENT_ID)
    mock_model_3 = MockModel.new(attr)
    mock_model_3.save
    entities = MockModel.find_entities([mock_model_1.id, mock_model_2.id, mock_model_3.id])
    assert_equal 2, entities.size
    entities = MockModel.find_entities(mock_model_2.id, mock_model_3.id, parent: parent_key)
    assert_equal 1, entities.size
    assert_equal 'Entity 3', entities[0][:name]
    assert_empty MockModel.find_entities(mock_model_3.id + 1)
  end

  test 'find entities should exclude duplicates' do
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    entities = MockModel.find_entities(mock_model_1.id, mock_model_1.id, mock_model_1.id)
    assert_equal 1, entities.size
  end

  test 'find entities should exclude nil ids' do
    mock_model_1 = create(:mock_model, name: 'Entity 1')
    entities = MockModel.find_entities(mock_model_1.id, nil)
    assert_equal 1, entities.size
  end

  test 'find' do
    mock_model = create(:mock_model, name: 'Entity')
    model_entity = MockModel.find(mock_model.id)
    assert model_entity.is_a?(MockModel)
    assert_equal 'Entity', model_entity.name
  end

  test 'find by parent' do
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    attr = attributes_for(:mock_model, name: 'Entity With Parent', parent_key_id: MOCK_PARENT_ID)
    mock_model = MockModel.new(attr)
    mock_model.save
    model_entity = MockModel.find(mock_model.id, parent: parent_key)
    assert model_entity.is_a?(MockModel)
    assert_equal 'Entity With Parent', model_entity.name
  end

  test 'find all by parent' do
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    attr = attributes_for(:mock_model, name: 'Entity 1 With Parent', parent_key_id: MOCK_PARENT_ID)
    mock_model_1 = MockModel.new(attr)
    mock_model_1.save
    attr = attributes_for(:mock_model, name: 'Entity 2 With Parent', parent_key_id: MOCK_PARENT_ID)
    mock_model_2 = MockModel.new(attr)
    mock_model_2.save
    model_entities = MockModel.find(mock_model_1.id, mock_model_2.id, parent: parent_key)
    model_entities.each { |model| assert model.is_a?(MockModel) }
    assert_equal 'Entity 1 With Parent', model_entities[0].name
    assert_equal 'Entity 2 With Parent', model_entities[1].name
  end

  test 'find without result' do
    assert_nil MockModel.find(99999)
    assert_empty MockModel.find([99999])
  end

  test 'find without results' do
    assert_empty MockModel.find(99999, 88888)
    assert_empty MockModel.find([99999, 88888])
  end

  test 'find by' do
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert_nil model_entity
    create(:mock_model, name: 'Billy Bob')
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert model_entity.is_a?(MockModel)
    assert_equal 'Billy Bob', model_entity.name
    parent_key = MockModel.parent_key(MOCK_PARENT_ID)
    attr = attributes_for(:mock_model, name: 'Entity With Parent', parent_key_id: MOCK_PARENT_ID)
    mock_model_2 = MockModel.new(attr)
    mock_model_2.save
    model_entity = MockModel.find_by(name: 'Billy Bob')
    assert_equal 'Billy Bob', model_entity.name
    model_entity = MockModel.find_by(name: 'Billy Bob', ancestor: parent_key)
    assert_nil model_entity
    model_entity = MockModel.find_by(name: 'Entity With Parent', ancestor: parent_key)
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
    assert model_entity.is_a?(MockModel)
    refute model_entity.role_changed?
    assert model_entity.entity_property_values.is_a? Hash
    assert_equal model_entity.entity_property_values['name'], 'A Mock Entity'
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
    grpc = MockModel.build_query(select: %w[name role]).to_grpc
    refute_nil grpc.projection
    assert_equal 2, grpc.projection.count
    grpc = MockModel.build_query(distinct_on: 'name').to_grpc
    refute_nil grpc.distinct_on
    assert_equal 1, grpc.distinct_on.count
    assert_equal 'name', grpc.distinct_on.first.name
    grpc = MockModel.build_query(distinct_on: %w[name role]).to_grpc
    refute_nil grpc.distinct_on
    assert_equal 2, grpc.distinct_on.count
    assert_equal 'role', grpc.distinct_on.last.name
    grpc = MockModel.build_query(cursor: 'a_cursor').to_grpc
    refute_nil grpc.start_cursor
    parent_int_key = CloudDatastore.dataset.key('Parent', MOCK_PARENT_ID)
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
