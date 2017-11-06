##
# = Active Model Datastore
#
# Makes the google-cloud-datastore gem compliant with active_model conventions and compatible with
# your Rails 5+ applications.
#
# Let's start by implementing the model:
#
#   class User
#     include ActiveModel::Datastore
#
#     attr_accessor :email, :enabled, :name, :role, :state
#
#     before_validation :set_default_values
#     after_validation :format_values
#
#     before_save { puts '** something can happen before save **'}
#     after_save { puts '** something can happen after save **'}
#
#     validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
#     validates :name, presence: true, length: { maximum: 30 }
#     validates :role, presence: true
#
#     def entity_properties
#       %w[email enabled name role]
#     end
#
#     def set_default_values
#       default_property_value :enabled, true
#       default_property_value :role, 1
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
module ActiveModel::Datastore
  extend ActiveSupport::Concern
  include ActiveModel::Model
  include ActiveModel::Dirty
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModel::Datastore::NestedAttr
  include ActiveModel::Datastore::PropertyValues
  include ActiveModel::Datastore::TrackChanges

  included do
    private_class_method :query_options, :query_sort, :query_property_filter, :find_all_entities
    define_model_callbacks :save, :update, :destroy
    attr_accessor :id, :parent_key_id, :entity_property_values
  end

  def entity_properties
    []
  end

  ##
  # Used to determine if the ActiveModel object belongs to an entity group.
  #
  def parent?
    parent_key_id.present?
  end

  ##
  # Used by ActiveModel for determining polymorphic routing.
  #
  def persisted?
    id.present?
  end

  ##
  # Builds the Cloud Datastore entity with attributes from the Model object.
  #
  # @param [Google::Cloud::Datastore::Key] parent An optional parent Key of the entity.
  #
  # @return [Entity] The updated Google::Cloud::Datastore::Entity.
  #
  def build_entity(parent = nil)
    entity = CloudDatastore.dataset.entity self.class.name, id
    if parent.present?
      raise ArgumentError, 'Must be a Key' unless parent.is_a? Google::Cloud::Datastore::Key
      entity.key.parent = parent
    elsif parent?
      entity.key.parent = self.class.parent_key(parent_key_id)
    end
    entity_properties.each do |attr|
      entity[attr] = instance_variable_get("@#{attr}")
    end
    entity
  end

  def save(parent = nil)
    save_entity(parent)
  end

  ##
  # For compatibility with libraries that require the bang method version (example, factory_bot).
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
      key.parent = self.class.parent_key(parent_key_id) if parent?
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
      self.parent_key_id = entity.key.parent.id if entity.key.parent.present?
      success
    end
  end

  # Methods defined here will be class methods when 'include ActiveModel::Datastore'.
  module ClassMethods
    ##
    # A default parent key for specifying an ancestor path and creating an entity group.
    #
    def parent_key(parent_id)
      CloudDatastore.dataset.key('Parent' + name, parent_id.to_i)
    end

    ##
    # Retrieves an entity by id or name and by an optional parent.
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
    #   User.find_by(name: 'Bryce', ancestor: parent_key)
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
      model_entity = build_model(entity)
      model_entity.entity_property_values = entity.properties.to_h
      entity.properties.to_h.each do |name, value|
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

    def build_model(entity)
      model_entity = new
      model_entity.id = entity.key.id unless entity.key.id.nil?
      model_entity.id = entity.key.name unless entity.key.name.nil?
      model_entity.parent_key_id = entity.key.parent.id if entity.key.parent.present?
      model_entity
    end
  end
end
