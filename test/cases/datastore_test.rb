require 'test_helper'
require 'minitest/mock'

class ActiveModel::DatastoreTest < ActiveSupport::TestCase
  def setup
    @preallocate_ids = ActiveModel::Datastore.preallocate_ids
    super
  end

  def teardown
    ActiveModel::Datastore.preallocate_ids = @preallocate_ids
    super
  end

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
    name = Faker::Lorem.characters(number: 1600)
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

  test 'save leaves id allocation to datastore by default and when disabled' do
    assert_equal false, ActiveModel::Datastore.preallocate_ids
    dataset = CloudDatastore.dataset
    [:default, false, 'false', '0', 'off', nil, ''].each do |configuration|
      unless configuration == :default
        ActiveModel::Datastore.preallocate_ids = true
        ActiveModel::Datastore.preallocate_ids = configuration
      end
      assert_equal false, ActiveModel::Datastore.preallocate_ids
      model = MockModel.new(name: 'Server assigned ID')
      saved_entities = nil
      save = lambda do |entity|
        assert entity.key.incomplete?
        entity.key.id = 12345
        saved_entities = [entity]
      end

      dataset.stub(:allocate_ids, ->(*) { flunk 'preallocation must be explicitly enabled' }) do
        dataset.stub(:save, save) do
          result = model.save
          assert_same saved_entities, result
        end
      end
      assert_equal 12345, model.id
    end
  end

  test 'save persists a preallocated key with its parent when enabled with a string' do
    ActiveModel::Datastore.preallocate_ids = 'true'
    assert_equal true, ActiveModel::Datastore.preallocate_ids
    model = MockModel.new(name: 'Preallocated entity')
    parent = CloudDatastore.dataset.key('Company', MOCK_PARENT_ID)

    assert model.save(parent)

    entity = MockModel.find_entity(model.id, parent)
    assert_equal 'Preallocated entity', entity['name']
    assert_equal model.id, entity.key.id
    assert_equal MOCK_PARENT_ID, model.parent_key_id
    assert_equal parent.to_grpc.path, entity.key.parent.to_grpc.path
    assert_equal 1, MockModel.count_test_entities
  end

  test 'save allocates a complete key before saving and preserves its parent' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    parent = dataset.key('Company', MOCK_PARENT_ID)
    [nil, parent, MockModel.parent_key(MOCK_PARENT_ID)].each do |expected_parent|
      model = MockModel.new(name: 'Allocated ID', parent_key_id: expected_parent&.id)
      allocated_key = dataset.key('MockModel', 12345)
      allocated_key.parent = expected_parent if expected_parent
      allocations = 0
      allocate = lambda do |key, count|
        allocations += 1
        assert key.incomplete?
        assert_equal 'MockModel', key.kind
        if expected_parent
          assert_equal expected_parent.to_grpc, key.parent.to_grpc
        else
          assert_nil key.parent
        end
        assert_equal 1, count
        [allocated_key]
      end
      saved_entities = nil
      save = lambda do |entity|
        assert entity.key.complete?
        assert_equal allocated_key, entity.key
        saved_entities = [entity]
      end

      dataset.stub(:allocate_ids, allocate) do
        dataset.stub(:save, save) do
          explicit_parent = expected_parent == parent ? parent : nil
          result = model.save(explicit_parent)
          assert_same saved_entities, result
        end
      end
      assert_equal 1, allocations
      assert_equal 12345, model.id
      if expected_parent
        assert_equal expected_parent.id, model.parent_key_id
      else
        assert_nil model.parent_key_id
      end
    end
  end

  test 'save retries with the same allocated key' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Retried create')
    allocated_key = dataset.key('MockModel', 12345)
    allocations = 0
    allocate = lambda do |*_args|
      allocations += 1
      [allocated_key]
    end
    attempts = []
    save = lambda do |entity|
      attempts << entity.key
      raise Google::Cloud::Error, 'commit response lost' if attempts.size == 1

      [entity]
    end

    capture_io do
      MockModel.stub(:sleep, ->(_) {}) do
        dataset.stub(:allocate_ids, allocate) do
          dataset.stub(:save, save) { assert model.save }
        end
      end
    end
    assert_equal [allocated_key, allocated_key], attempts
    assert_equal 1, allocations
    assert_equal 12345, model.id
  end

  test 'save retries allocation before attempting the write' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Retried allocation')
    allocated_key = dataset.key('MockModel', 12345)
    allocations = 0
    allocate = lambda do |*_args|
      allocations += 1
      raise Google::Cloud::Error, 'allocation unavailable' if allocations == 1

      [allocated_key]
    end
    save = lambda do |entity|
      assert_equal 2, allocations
      assert_equal allocated_key, entity.key
      [entity]
    end

    capture_io do
      MockModel.stub(:sleep, ->(_) {}) do
        dataset.stub(:allocate_ids, allocate) do
          dataset.stub(:save, save) { assert model.save }
        end
      end
    end
    assert_equal 2, allocations
    assert_equal 12345, model.id
  end

  test 'exhausted allocation retries prevent saving' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Failed allocation')
    parent = MockModel.parent_key(MOCK_PARENT_ID)
    attempts = 0
    allocate = lambda do |*_args|
      attempts += 1
      raise Google::Cloud::Error, 'allocation unavailable'
    end

    capture_io do
      MockModel.stub(:sleep, ->(_) {}) do
        dataset.stub(:allocate_ids, allocate) do
          dataset.stub(:save, ->(*) { flunk 'must not save without an allocated key' }) do
            assert_equal false, model.save(parent)
          end
        end
      end
    end
    assert_equal ActiveModel::Datastore::ALLOCATE_RETRY_COUNT + 1, attempts
    assert_nil model.id
    refute model.persisted?
    assert_equal MOCK_PARENT_ID, model.parent_key_id
    assert_equal parent.to_grpc.path, model.build_entity.key.parent.to_grpc.path
  end

  test 'empty allocation results are retried and logged' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Empty allocation')
    attempts = 0
    allocate = lambda do |*_args|
      attempts += 1
      []
    end

    out, = capture_io do
      MockModel.stub(:sleep, ->(_) {}) do
        dataset.stub(:allocate_ids, allocate) do
          dataset.stub(:save, ->(*) { flunk 'must not save without an allocated key' }) do
            assert_equal false, model.save
          end
        end
      end
    end
    assert_equal ActiveModel::Datastore::ALLOCATE_RETRY_COUNT + 1, attempts
    assert_includes out, 'allocate_ids returned no key'
    assert_nil model.id
  end

  test 'save bang raises entity not saved when allocation fails' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Invalid allocation')
    allocate = ->(*) { raise Google::Cloud::InvalidArgumentError, 'invalid allocation' }

    capture_io do
      dataset.stub(:allocate_ids, allocate) do
        dataset.stub(:save, ->(*) { flunk 'must not save without an allocated key' }) do
          assert_raises(ActiveModel::Datastore::EntityNotSavedError) { model.save! }
        end
      end
    end
    assert_nil model.id
  end

  test 'failed save does not assign the allocated id to the model' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    model = MockModel.new(name: 'Failed save')
    allocated_key = dataset.key('MockModel', 12345)
    parent = MockModel.parent_key(MOCK_PARENT_ID)
    allocated_key.parent = parent
    save = ->(*) { raise Google::Cloud::InvalidArgumentError, 'invalid entity' }

    capture_io do
      dataset.stub(:allocate_ids, [allocated_key]) do
        dataset.stub(:save, save) { assert_equal false, model.save(parent) }
      end
    end
    assert_nil model.id
    refute model.persisted?
    assert_equal MOCK_PARENT_ID, model.parent_key_id
    assert_equal parent.to_grpc.path, model.build_entity.key.parent.to_grpc.path
  end

  test 'saving and updating complete keys do not allocate ids' do
    ActiveModel::Datastore.preallocate_ids = true
    dataset = CloudDatastore.dataset
    [12345, 'named-key'].each do |id|
      [:save, :update].each do |operation|
        model = MockModel.new(name: 'Existing key', id: id)
        save = lambda do |entity|
          assert_equal dataset.key('MockModel', id).to_grpc, entity.key.to_grpc
          [entity]
        end
        dataset.stub(:allocate_ids, ->(*) { flunk 'must not allocate a complete key' }) do
          dataset.stub(:save, save) do
            args = operation == :update ? [{ name: 'Updated' }] : []
            assert model.public_send(operation, *args)
          end
        end
      end
    end
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
    assert query.instance_of?(Google::Cloud::Datastore::Query)
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
