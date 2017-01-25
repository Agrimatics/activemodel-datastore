##
# Additional methods added for testing only.
#
module EntityClassMethodExtensions
  def all_test_entities
    query = CloudDatastore.dataset.query(name)
    CloudDatastore.dataset.run(query)
  end

  def count_test_entities
    all_test_entities.length
  end
end
