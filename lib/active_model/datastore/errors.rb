module ActiveModel::Datastore
  ##
  # Generic Active Model Cloud Datastore exception class.
  #
  class Error < StandardError
  end

  ##
  # Raised while attempting to save an invalid entity.
  #
  class EntityNotSavedError < Error
  end

  ##
  # Raised when an entity is not configured for tracking changes.
  #
  class TrackChangesError < Error
  end

  ##
  # Raised when unable to find an entity by given id or set of ids.
  #
  class EntityError < Error
  end
end
