# Additional methods added for testing only.
module EntityInstanceMethodExtensions
  def save!
    parent = nil
    if account_id.present?
      versions = RedisUtils.increment_versions(1, account_id, self.class.name)
      self.id = versions.first
      parent = CloudDatastore.dataset.key('Parent' + self.class.name, account_id.to_i)
    end
    msg = 'Failed to save the entity'
    save_entity(parent) || raise(ActiveModelCloudDatastore::EntityNotSaved.new(msg, self))
  end
end
