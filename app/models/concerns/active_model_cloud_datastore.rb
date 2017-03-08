# frozen_string_literal: true

##
# = Integrates ActiveModel with the Google::Cloud::Datastore
#
# Makes google-cloud-datastore compliant with active_model conventions.
#
# Start by...are we going to include the module or inherit?
#
#
module ActiveModelCloudDatastore
  extend ActiveSupport::Concern
  include ActiveModel::Model
  include ActiveModel::Dirty
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModelNestedAttr

  included do
    private_class_method :query_options, :query_sort, :query_property_filter
    define_model_callbacks :save, :update, :destroy
    attr_accessor :id, :exclude_from_save
  end

  def attributes
    []
  end

  def tracked_attributes
    []
  end

  ##
  # Used by ActiveModel for determining polymorphic routing.
  #
  def persisted?
    id.present?
  end

  ##
  # Sets a default value for the attribute if not currently set.
  #
  # Example:
  #   default :state, 0
  #
  # is equivalent to:
  #   self.state = state.presence || 0
  #
  # Example:
  #   default :enabled, false
  #
  # is equivalent to:
  #   self.enabled = false if enabled.nil?
  #
  def default(attr, value)
    if value.is_a?(TrueClass) || value.is_a?(FalseClass)
      send("#{attr.to_sym}=", value) if send(attr.to_sym).nil?
    else
      send("#{attr.to_sym}=", send(attr.to_sym).presence || value)
    end
  end

  ##
  # Converts the type of the attribute.
  #
  # Example:
  #   format :weight, :float
  #
  # is equivalent to:
  #   self.weight = weight.to_f if weight.present?
  #
  def format(attr, type)
    return unless send(attr.to_sym).present?
    case type.to_sym
    when :float
      send("#{attr.to_sym}=", send(attr.to_sym).to_f)
    when :integer
      send("#{attr.to_sym}=", send(attr.to_sym).to_i)
    else
      raise ArgumentError, 'Supported types are :float, :integer'
    end
  end

  # -------------------------------- start track_changes.rb --------------------------------

  ##
  # Resets the ActiveModel::Dirty tracked changes.
  #
  def reload!
    clear_changes_information
    self.exclude_from_save = false
  end

  def exclude_from_save?
    @exclude_from_save.nil? ? false : @exclude_from_save
  end

  ##
  # Determines if any attribute values have changed using ActiveModel::Dirty.
  # For attributes enabled for change tracking compares changed values. All values
  # submitted from an HTML form are strings, thus a string of 25.0 doesn't match an
  # original float of 25.0. Call this method after valid? to allow for any type coercing
  # occurring before saving to datastore.
  #
  # For example, consider the scenario in which the user submits an unchanged form value:
  # The initial value is a float, which during assign_attributes is set to a string and
  # then coerced back to a float during a validation callback.
  #
  # If none of the tracked attributes have changed, exclude_from_save is set to true.
  #
  def values_changed?
    unless tracked_attributes.present?
      raise TrackChangesError.new('Object has not been configured for change tracking.', self)
    end
    changed = marked_for_destruction? ? true : false
    tracked_attributes.each do |attr|
      break if changed
      if send("#{attr}_changed?")
        changed = send(attr) == send("#{attr}_was") ? false : true
      end
    end
    self.exclude_from_save = !changed
    changed
  end

  def remove_unmodified_children
    return unless tracked_attributes.present? && nested_attributes?
    nested_attributes.each do |attr|
      with_changes = Array(send(attr.to_sym)).select(&:values_changed?)
      send("#{attr}=", with_changes)
    end
    nested_attributes.delete_if { |attr| Array(send(attr.to_sym)).size.zero? }
  end

  # -------------------------------- end track_changes.rb --------------------------------

  ##
  # Builds the Cloud Datastore entity with attributes from the Model object.
  #
  # @return [Entity] The updated Google::Cloud::Datastore::Entity.
  #
  def build_entity(parent = nil)
    entity = CloudDatastore.dataset.entity(self.class.name, id)
    entity.key.parent = parent if parent.present?
    attributes.each do |attr|
      entity[attr] = instance_variable_get("@#{attr}")
    end
    entity
  end

  def save(parent = nil)
    save_entity(parent)
  end

  ##
  # For compatibility with libraries that require the bang method version (example, factory_girl).
  # If you require a save! method that supports parents (ancestor queries), override this method
  # in your own code with something like this:
  #
  #   def save!
  #     parent = nil
  #     if account_id.present?
  #       parent = CloudDatastore.dataset.key('Parent' + self.class.name, account_id.to_i)
  #     end
  #     msg = 'Failed to save the entity'
  #     save_entity(parent) || raise(ActiveModelCloudDatastore::EntityNotSavedError.new(msg, self))
  #   end
  #
  def save!
    save_entity || raise(EntityNotSavedError.new('Failed to save the entity', self))
  end

  def update(params)
    assign_attributes(params)
    return unless valid?
    run_callbacks :update do
      entity = build_entity
      self.class.retry_on_exception? { CloudDatastore.dataset.save(entity) }
    end
  end

  def destroy
    run_callbacks :destroy do
      key = CloudDatastore.dataset.key(self.class.name, id)
      self.class.retry_on_exception? { CloudDatastore.dataset.delete(key) }
    end
  end

  private

  def save_entity(parent = nil)
    return unless valid?
    run_callbacks :save do
      entity = build_entity(parent)
      success = self.class.retry_on_exception? { CloudDatastore.dataset.save(entity) }
      self.id = entity.key.id if success
      success
    end
  end

  # Methods defined here will be class methods whenever we 'include ActiveModelCloudDatastore'.
  module ClassMethods
    ##
    # Enables track changes functionality for the provided attributes using ActiveModel::Dirty.
    #
    # Calls define_attribute_methods for each attribute provided.
    #
    # Creates a setter for each attribute that will look something like this:
    #   def name=(value)
    #     name_will_change! unless value == @name
    #     @name = value
    #   end
    #
    # Overrides tracked_attributes to return an Array of the attributes configured for tracking.
    #
    def enable_change_tracking(*attributes)
      attributes = attributes.collect(&:to_sym)
      attributes.each do |attr|
        define_attribute_methods attr

        define_method("#{attr}=") do |value|
          send("#{attr}_will_change!") unless value == instance_variable_get("@#{attr}")
          instance_variable_set("@#{attr}", value)
        end
      end

      define_method('tracked_attributes') { attributes }
    end

    ##
    # Queries all objects from Cloud Datastore by named kind and using the provided options.
    #
    # @param [Hash] options The options to construct the query with.
    #
    # @option options [Google::Cloud::Datastore::Key] :ancestor Filter for inherited results.
    # @option options [Array] :where Adds a property filter of arrays in the format
    #   [name, operator, value].
    #
    # @return [Array<Model>] An array of ActiveModel results.
    #
    def all(options = {})
      query = CloudDatastore.dataset.query(name)
      query.ancestor(options[:ancestor]) if options[:ancestor]
      query_property_filter(query, options)
      entities = retry_on_exception { CloudDatastore.dataset.run(query) }
      from_entities(entities.flatten)
    end

    ##
    # Queries objects from Cloud Datastore in batches by named kind and using the provided options.
    # When a limit option is provided queries up to the limit and returns results with a cursor.
    #
    # @param [Hash] options The options to construct the query with. See build_query for options.
    #
    # @return [Array<Model>, String] An array of ActiveModel results and a cursor that can be used
    #   to query for additional results.
    #
    def find_in_batches(options = {})
      next_cursor = nil
      query = build_query(options)
      entities = retry_on_exception { CloudDatastore.dataset.run(query) }
      if options[:limit]
        next_cursor = entities.cursor if entities.size == options[:limit]
      else
        entities.all
      end
      model_entities = from_entities(entities.flatten)
      return model_entities, next_cursor
    end

    ##
    # Retrieves an entity by key and by an optional parent.
    #
    # @param [Integer or String] id_or_name The id or name value of the entity Key.
    # @param [Google::Cloud::Datastore::Key] parent The parent Key of the entity.
    #
    # @return [Entity, nil] a Google::Cloud::Datastore::Entity object or nil.
    #
    def find_entity(id_or_name, parent = nil)
      key = CloudDatastore.dataset.key(name, id_or_name)
      key.parent = parent if parent.present?
      retry_on_exception { CloudDatastore.dataset.find(key) }
    end

    ##
    # Retrieves the entities for the provided ids by key and by an optional parent.
    #
    # @param [Array] ids An array of ids to retrieve.
    # @param [Google::Cloud::Datastore::Key] parent The parent Key of the entity.
    #
    # @return [Array<Entity>] an array of Google::Cloud::Datastore::Entity objects.
    #
    def find_entities(*ids, parent: nil)
      ids = Array(ids).flatten.compact
      keys = ids.map { |id| CloudDatastore.dataset.key(name, id) }
      keys.map { |key| key.parent = parent } if parent.present?
      retry_on_exception { CloudDatastore.dataset.find_all(keys) }
    end

    ##
    # Find object by ID.
    #
    # @return [Model, nil] An ActiveModel object or nil.
    #
    def find(id)
      entity = find_entity(id.to_i)
      from_entity(entity)
    end

    ##
    # Find object by parent and ID.
    #
    # @return [Model, nil] An ActiveModel object or nil.
    #
    def find_by_parent(id, parent)
      entity = find_entity(id.to_i, parent)
      from_entity(entity)
    end

    ##
    # Find objects by parent and an array of IDs.
    #
    # @return [Array<Model>] An array of ActiveModel objects.
    #
    def find_all_by_parent(ids, parent)
      ids = ids.map(&:to_i)
      entities = find_entities(ids, parent: parent)
      from_entities(entities.flatten)
    end

    ##
    # Finds the first entity matching the specified condition.
    #
    # @param [Hash] args In which the key is the property and the value is the value to look for.
    # @option args [Google::Cloud::Datastore::Key] :ancestor filter for inherited results
    #
    # @return [Model, nil] An ActiveModel object or nil.
    #
    # @example
    #   User.find_by(name: 'Joe')
    #   User.find_by(name: 'Bryce', ancestor: parent)
    #
    def find_by(args)
      query = CloudDatastore.dataset.query(name)
      query.ancestor(args[:ancestor]) if args[:ancestor]
      query.limit(1)
      query.where(args.keys[0].to_s, '=', args.values[0])
      entities = retry_on_exception { CloudDatastore.dataset.run(query) }
      from_entity(entities.first)
    end

    def from_entities(entities)
      entities.map { |entity| from_entity(entity) }
    end

    ##
    # Translates between Google::Cloud::Datastore::Entity objects and ActiveModel::Model objects.
    #
    # @param [Entity] entity Entity from Cloud Datastore.
    # @return [Model] The translated ActiveModel object.
    #
    def from_entity(entity)
      return if entity.nil?
      model_entity = new
      model_entity.id = entity.key.id unless entity.key.id.nil?
      model_entity.id = entity.key.name unless entity.key.name.nil?
      entity.properties.to_hash.each do |name, value|
        model_entity.send "#{name}=", value
      end
      model_entity.reload!
      model_entity
    end

    def exclude_from_index(entity, boolean)
      entity.properties.to_h.keys.each do |value|
        entity.exclude_from_indexes! value, boolean
      end
    end

    ##
    # Constructs a Google::Cloud::Datastore::Query.
    #
    # @param [Hash] options The options to construct the query with.
    #
    # @option options [Google::Cloud::Datastore::Key] :ancestor Filter for inherited results.
    # @option options [String] :cursor Sets the cursor to start the results at.
    # @option options [Integer] :limit Sets a limit to the number of results to be returned.
    # @option options [String] :order Sort the results by property name.
    # @option options [String] :desc_order Sort the results by descending property name.
    # @option options [Array] :select Retrieve only select properties from the matched entities.
    # @option options [Array] :where Adds a property filter of arrays in the format
    #   [name, operator, value].
    #
    # @return [Query] A datastore query.
    #
    def build_query(options = {})
      query = CloudDatastore.dataset.query(name)
      query_options(query, options)
    end

    def retry_on_exception?
      retry_count = 0
      sleep_time = 0.5 # 0.5, 1, 2, 4 second between retries
      begin
        yield
      rescue => e
        puts "\e[33m[#{e.message.inspect}]\e[0m"
        puts 'Rescued exception, retrying...'
        sleep sleep_time
        sleep_time *= 2
        retry_count += 1
        return false if retry_count > 3
        retry
      end
      true
    end

    def retry_on_exception
      retry_count = 0
      sleep_time = 0.5 # 0.5, 1, 2, 4 second between retries
      begin
        yield
      rescue => e
        puts "\e[33m[#{e.message.inspect}]\e[0m"
        puts 'Rescued exception, retrying...'
        sleep sleep_time
        sleep_time *= 2
        retry_count += 1
        raise e if retry_count > 3
        retry
      end
    end

    def log_google_cloud_error
      yield
    rescue Google::Cloud::Error => e
      puts "\e[33m[#{e.message.inspect}]\e[0m"
      raise e
    end

    # **************** private ****************

    def query_options(query, options)
      query.ancestor(options[:ancestor]) if options[:ancestor]
      query.cursor(options[:cursor]) if options[:cursor]
      query.limit(options[:limit]) if options[:limit]
      query_sort(query, options)
      query.select(options[:select]) if options[:select]
      query_property_filter(query, options)
    end

    ##
    # Adds sorting to the results by a property name if included in the options.
    #
    def query_sort(query, options)
      query.order(options[:order]) if options[:order]
      query.order(options[:desc_order], :desc) if options[:desc_order]
      query
    end

    ##
    # Adds property filters to the query if included in the options.
    # Accepts individual or nested Arrays:
    #   [['superseded', '=', false], ['email', '=', 'something']]
    #
    def query_property_filter(query, options)
      if options[:where]
        opts = options[:where]
        if opts[0].is_a?(Array)
          opts.each do |opt|
            query.where(opt[0], opt[1], opt[2]) unless opt.nil?
          end
        else
          query.where(opts[0], opts[1], opts[2])
        end
      end
      query
    end
  end

  # -------------------------------- start errors.rb --------------------------------

  ##
  # Generic Active Model Cloud Datastore exception class.
  #
  class ActiveModelCloudDatastoreError < StandardError
    attr_reader :record

    def initialize(message = nil, record = nil)
      @record = record
      puts "\e[33m[#{self.record.errors.messages}]\e[0m"
      super(message)
    end
  end

  ##
  # Raised while attempting to save an invalid entity.
  #
  class EntityNotSavedError < ActiveModelCloudDatastoreError
  end

  ##
  # Raised when an entity is not configured for tracking changes.
  #
  class TrackChangesError < ActiveModelCloudDatastoreError
  end

  # --------------------------------- end errors.rb ---------------------------------
end
