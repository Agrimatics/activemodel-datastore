# Additional methods added for testing only.
module EntityInstanceMethodExtensions
  def save!
    parent = CloudDatastore.dataset.key('Company', 12345)
    msg = 'Failed to save the entity'
    save_entity(parent) || raise(ActiveModel::Datastore::EntityNotSavedError, msg)
  end
end
