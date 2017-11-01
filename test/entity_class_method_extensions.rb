##
# Additional methods added for testing only.
#
module EntityClassMethodExtensions
  def all_test_entities(namespace: nil)
    query = CloudDatastore.dataset.query(name)
    CloudDatastore.dataset.run(query, namespace: namespace)
  end

  def count_test_entities(namespace: nil)
    all_test_entities(namespace: namespace).length
  end
end
