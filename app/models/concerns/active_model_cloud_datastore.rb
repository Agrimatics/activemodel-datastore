# frozen_string_literal: true

##
# = Active Model Datastore
#
# Makes the google-cloud-datastore gem compliant with active_model conventions and compatible with
# your Rails 5 applications.
#
# Let's start by implementing the model:
#
#   class User
#     include ActiveModelCloudDatastore
#
#     attr_accessor :email, :name, :enabled, :state
#
#     before_validation :set_default_values
#     before_save { puts '** something can happen before save **' }
#     after_save { puts '** something can happen after save **' }
#
#     validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
#     validates :name, presence: true, length: { maximum: 30 }
#
#     def entity_properties
#       %w(email name enabled)
#     end
#
#     def set_default_values
#       default_property_value :enabled, true
#     end
#
#     def format_values
#       format_property_value :role, :integer
#     end
#   end
#
# Using `attr_accessor` the attributes of the model are defined. Validations and Callbacks all work
# as you would expect. However, `entity_properties` is new. Data objects in Google Cloud Datastore
# are known as entities. Entities are of a kind. An entity has one or more named properties, each
# of which can have one or more values. Think of them like this:
# * 'Kind' (which is your table)
# * 'Entity' (which is the record from the table)
# * 'Property' (which is the attribute of the record)
#
# The `entity_properties` method defines an Array of the properties that belong to the entity in
# cloud datastore. With this approach, Rails deals solely with ActiveModel objects. The objects are
# converted to/from entities as needed during save/query operations.
#
# We have also added the ability to set default property values and type cast the format of values
# for entities.
#
# Now on to the controller! A scaffold generated controller works out of the box:
#
#   class UsersController < ApplicationController
#     before_action :set_user, only: [:show, :edit, :update, :destroy]
#
#     def index
#       @users = User.all
#     end
#
#     def show
#     end
#
#     def new
#       @user = User.new
#     end
#
#     def edit
#     end
#
#     def create
#       @user = User.new(user_params)
#       respond_to do |format|
#         if @user.save
#           format.html { redirect_to @user, notice: 'User was successfully created.' }
#         else
#           format.html { render :new }
#         end
#       end
#     end
#
#     def update
#       respond_to do |format|
#         if @user.update(user_params)
#           format.html { redirect_to @user, notice: 'User was successfully updated.' }
#         else
#           format.html { render :edit }
#         end
#       end
#     end
#
#     def destroy
#       @user.destroy
#       respond_to do |format|
#         format.html { redirect_to users_url, notice: 'User was successfully destroyed.' }
#       end
#     end
#
#     private
#
#     def set_user
#       @user = User.find(params[:id])
#     end
#
#     def user_params
#       params.require(:user).permit(:email, :name)
#     end
#   end
#
# TODO: describe eventual consistency with ancestor queries and entity groups.
# TODO: describe the available query options.
# TODO: describe indexes.
# TODO: describe the change tracking implementation.
#
module ActiveModelCloudDatastore
  extend ActiveSupport::Concern
  include ActiveModel::Model
  include ActiveModel::Dirty
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModelNestedAttr

  included do
    private_class_method :query_options, :query_sort, :query_property_filter, :find_all_entities
    define_model_callbacks :save, :update, :destroy
    attr_accessor :id, :exclude_from_save
  end

  def entity_properties
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
  # Sets a default value for the property if not currently set.
  #
  # Example:
  #   default_property_value :state, 0
  #
  # is equivalent to:
  #   self.state = state.presence || 0
  #
  # Example:
  #   default_property_value :enabled, false
  #
  # is equivalent to:
  #   self.enabled = false if enabled.nil?
  #
  def default_property_value(attr, value)
    if value.is_a?(TrueClass) || value.is_a?(FalseClass)
      send("#{attr.to_sym}=", value) if send(attr.to_sym).nil?
    else
      send("#{attr.to_sym}=", send(attr.to_sym).presence || value)
    end
  end

  ##
  # Converts the type of the property.
  #
  # Example:
  #   format_property_value :weight, :float
  #
  # is equivalent to:
  #   self.weight = weight.to_f if weight.present?
  #
  def format_property_value(attr, type)
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
      raise TrackChangesError, 'Object has not been configured for change tracking.'
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
    entity = CloudDatastore.dataset.entity self.class.name, id
    entity.key.parent = parent if parent.present?
    entity_properties.each do |attr|
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
  #       parent = CloudDatastore.dataset.key 'Parent' + self.class.name, account_id.to_i
  #     end
  #     msg = 'Failed to save the entity'
  #     save_entity(parent) || raise(ActiveModelCloudDatastore::EntityNotSavedError, msg)
  #   end
  #
  def save!
    save_entity || raise(EntityNotSavedError, 'Failed to save the entity')
  end

  def update(params)
    assign_attributes(params)
    return unless valid?
    run_callbacks :update do
      entity = build_entity
      self.class.retry_on_exception? { CloudDatastore.dataset.save entity }
    end
  end

  def destroy
    run_callbacks :destroy do
      key = CloudDatastore.dataset.key self.class.name, id
      self.class.retry_on_exception? { CloudDatastore.dataset.delete key }
    end
  end

  private

  def save_entity(parent = nil)
    return unless valid?
    run_callbacks :save do
      entity = build_entity(parent)
      success = self.class.retry_on_exception? { CloudDatastore.dataset.save entity }
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
    # Retrieves an entity by key and by an optional parent.
    #
    # @param [Integer or String] id_or_name The id or name value of the entity Key.
    # @param [Google::Cloud::Datastore::Key] parent The parent Key of the entity.
    #
    # @return [Entity, nil] a Google::Cloud::Datastore::Entity object or nil.
    #
    def find_entity(id_or_name, parent = nil)
      key = CloudDatastore.dataset.key name, id_or_name
      key.parent = parent if parent.present?
      retry_on_exception { CloudDatastore.dataset.find key }
    end

    ##
    # Retrieves the entities for the provided ids by key and by an optional parent.
    # The find_all method returns LookupResults, which is a special case Array with
    # additional values. LookupResults are returned in batches, and the batch size is
    # determined by the Datastore API. Batch size is not guaranteed. It will be affected
    # by the size of the data being returned, and by other forces such as how distributed
    # and/or consistent the data in Datastore is. Calling `all` on the LookupResults retrieves
    # all results by repeatedly loading #next until #next? returns false. The `all` method
    # returns an enumerator unless passed a block. We iterate on the enumerator to return
    # the model entity objects.
    #
    # @param [Integer, String] ids_or_names One or more ids to retrieve.
    # @param [Google::Cloud::Datastore::Key] parent The parent Key of the entity.
    #
    # @return [Array<Entity>] an array of Google::Cloud::Datastore::Entity objects.
    #
    def find_entities(*ids_or_names, parent: nil)
      ids_or_names = ids_or_names.flatten.compact.uniq
      lookup_results = find_all_entities(ids_or_names, parent)
      lookup_results.all.collect { |x| x }
    end

    ##
    # Queries entities from Cloud Datastore by named kind and using the provided options.
    # When a limit option is provided queries up to the limit and returns results with a cursor.
    #
    # This method may make several API calls until all query results are retrieved. The `run`
    # method returns a QueryResults object, which is a special case Array with additional values.
    # QueryResults are returned in batches, and the batch size is determined by the Datastore API.
    # Batch size is not guaranteed. It will be affected by the size of the data being returned,
    # and by other forces such as how distributed and/or consistent the data in Datastore is.
    # Calling `all` on the QueryResults retrieves all results by repeatedly loading #next until
    # #next? returns false. The `all` method returns an enumerator which from_entities iterates on.
    #
    # Be sure to use as narrow a search criteria as possible. Please use with caution.
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
    # @return [Array<Model>, String] An array of ActiveModel results
    #
    # or if options[:limit] was provided:
    #
    # @return [Array<Model>, String] An array of ActiveModel results and a cursor that
    #   can be used to query for additional results.
    #
    def all(options = {})
      next_cursor = nil
      query = build_query(options)
      query_results = retry_on_exception { CloudDatastore.dataset.run query }
      if options[:limit]
        next_cursor = query_results.cursor if query_results.size == options[:limit]
        return from_entities(query_results.all), next_cursor
      end
      from_entities(query_results.all)
    end

    ##
    # Find entity by id - this can either be a specific id (1), a list of ids (1, 5, 6),
    # or an array of ids ([5, 6, 10]). The parent key is optional.
    #
    # @param [Integer] ids One or more ids to retrieve.
    # @param [Google::Cloud::Datastore::Key] parent The parent key of the entity.
    #
    # @return [Model, nil] An ActiveModel object or nil for a single id.
    # @return [Array<Model>] An array of ActiveModel objects for more than one id.
    #
    def find(*ids, parent: nil)
      expects_array = ids.first.is_a?(Array)
      ids = ids.flatten.compact.uniq.map(&:to_i)

      case ids.size
      when 0
        raise EntityError, "Couldn't find #{name} without an ID"
      when 1
        entity = find_entity(ids.first, parent)
        model_entity = from_entity(entity)
        expects_array ? [model_entity].compact : model_entity
      else
        lookup_results = find_all_entities(ids, parent)
        from_entities(lookup_results.all)
      end
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
      query = CloudDatastore.dataset.query name
      query.ancestor(args[:ancestor]) if args[:ancestor]
      query.limit(1)
      query.where(args.keys[0].to_s, '=', args.values[0])
      query_results = retry_on_exception { CloudDatastore.dataset.run query }
      from_entity(query_results.first)
    end

    ##
    # Translates an Enumerator of Datastore::Entity objects to ActiveModel::Model objects.
    #
    # Results provided by the dataset `find_all` or `run query` will be a Dataset::LookupResults or
    # Dataset::QueryResults object. Invoking `all` on those objects returns an enumerator.
    #
    # @param [Enumerator] entities An enumerator representing the datastore entities.
    #
    def from_entities(entities)
      raise ArgumentError, 'Entities param must be an Enumerator' unless entities.is_a? Enumerator
      entities.map { |entity| from_entity(entity) }
    end

    ##
    # Translates between Datastore::Entity objects and ActiveModel::Model objects.
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
        model_entity.send "#{name}=", value if model_entity.respond_to? "#{name}="
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
      query = CloudDatastore.dataset.query name
      query_options(query, options)
    end

    def retry_on_exception?(max_retry_count = 5)
      retries = 0
      sleep_time = 0.25
      begin
        yield
      rescue => e
        return false if retries >= max_retry_count
        puts "\e[33mRescued exception #{e.message.inspect}, retrying in #{sleep_time}\e[0m"
        # 0.25, 0.5, 1, 2, and 4 second between retries.
        sleep sleep_time
        retries += 1
        sleep_time *= 2
        retry
      end
    end

    def retry_on_exception(max_retry_count = 5)
      retries = 0
      sleep_time = 0.25
      begin
        yield
      rescue => e
        raise e if retries >= max_retry_count
        puts "\e[33mRescued exception #{e.message.inspect}, retrying in #{sleep_time}\e[0m"
        # 0.25, 0.5, 1, 2, and 4 second between retries.
        sleep sleep_time
        retries += 1
        sleep_time *= 2
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

    ##
    # Finds entities by keys using the provided array items. Results provided by the
    # dataset `find_all` is a Dataset::LookupResults object.
    #
    # @param [Array<Integer>, Array<String>] ids_or_names An array of ids or names.
    #
    #
    def find_all_entities(ids_or_names, parent)
      keys = ids_or_names.map { |id| CloudDatastore.dataset.key name, id }
      keys.map { |key| key.parent = parent } if parent.present?
      retry_on_exception { CloudDatastore.dataset.find_all keys }
    end
  end

  # -------------------------------- start errors.rb --------------------------------

  ##
  # Generic Active Model Cloud Datastore exception class.
  #
  class ActiveModelDatastoreError < StandardError
  end

  ##
  # Raised while attempting to save an invalid entity.
  #
  class EntityNotSavedError < ActiveModelDatastoreError
  end

  ##
  # Raised when an entity is not configured for tracking changes.
  #
  class TrackChangesError < ActiveModelDatastoreError
  end

  ##
  # Raised when unable to find an entity by given id or set of ids.
  #
  class EntityError < ActiveModelDatastoreError
  end

  # --------------------------------- end errors.rb ---------------------------------
end
