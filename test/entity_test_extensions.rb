# Additional methods added for testing only.
module EntityTestExtensions
  def delete_all_test_entities!
    entity_kinds = %w(MockModel)
    entity_kinds.each do |kind|
      query = CloudDatastore.dataset.query(kind)
      loop do
        entities = CloudDatastore.dataset.run(query)
        break if entities.empty?
        CloudDatastore.dataset.delete(*entities)
      end
    end
  end

  # Defined as a bang method as it will create an entity in the datastore with whatever
  # attributes are provided (they are not validated).
  def create!(attributes)
    entity = CloudDatastore.dataset.entity
    key = CloudDatastore.dataset.key(name)
    if attributes[:account_id]
      key.parent = CloudDatastore.dataset.key('Parent' + name, attributes[:account_id].to_i)
      attributes.delete(:account_id)
    end
    entity.key = key
    attributes.each do |attr_key, attr_val|
      entity[attr_key.to_s] = attr_val
    end
    entity = CloudDatastore.dataset.save(entity)
    from_entity(entity.first) unless entity.empty?
  end

  def all_test_entities
    query = CloudDatastore.dataset.query(name)
    CloudDatastore.dataset.run(query)
  end

  def count_test_entities
    all_test_entities.length
  end
end
