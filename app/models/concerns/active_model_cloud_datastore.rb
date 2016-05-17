# frozen_string_literal: true

# Integrates ActiveModel with the Google Gcloud::Datastore
module ActiveModelCloudDatastore
  extend ActiveSupport::Concern
  include ActiveModel::Model
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks

  included do
    private_class_method :query_options, :query_sort, :query_property_filter, :find_all
    define_model_callbacks :save, :update, :destroy
    attr_accessor :id
  end

  def attributes
    []
  end

  # Used by ActiveModel for determining polymorphic routing.
  def persisted?
    id.present?
  end

  # Updates attribute values on the ActiveModel::Model object with the provided params.
  # Example, such as submitted form params.
  #
  # @param [Hash] params
  def update_model_attributes(params)
    params.each do |name, value|
      send "#{name}=", value if respond_to? "#{name}="
    end
  end

  # Builds the Cloud Datastore entity with attributes from the Model object.
  #
  # @return [Entity] the updated Gcloud::Datastore::Entity
  def build_entity(parent = nil)
    entity = Gcloud::Datastore::Entity.new
    entity.key = Gcloud::Datastore::Key.new(self.class.name, id)
    entity.key.parent = parent if parent
    attributes.each do |attr|
      entity[attr] = instance_variable_get("@#{attr}")
    end
    entity
  end

  def save(parent = nil)
    run_callbacks :save do
      if valid?
        entity = build_entity(parent)
        success = self.class.retry_on_exception { CloudDatastore.dataset.save(entity) }
        if success
          self.id = entity.key.id
          return true
        end
      end
      false
    end
  end

  def update(params)
    run_callbacks :update do
      update_model_attributes(params)
      if valid?
        entity = build_entity
        self.class.retry_on_exception { CloudDatastore.dataset.save(entity) }
      else
        false
      end
    end
  end

  def destroy
    run_callbacks :destroy do
      key = Gcloud::Datastore::Key.new(self.class.name, id)
      self.class.retry_on_exception { CloudDatastore.dataset.delete(key) }
    end
  end

  # Methods defined here will be class methods whenever we 'include DatastoreUtils'.
  module ClassMethods
    # Queries all objects from Cloud Datastore by named kind and using the provided options.
    #
    # @param [Hash] options the options to construct the query with.
    #
    # @option options [Gcloud::Datastore::Key] :ancestor filter for results that inherit from a key
    # @option options [Hash] :where filter, Array in the format [name, operator, value]
    #
    # @return [Array<Model>] an array of ActiveModel results.
    def all(options = {})
      query = Gcloud::Datastore::Query.new
      query.kind(name)
      query.ancestor(options[:ancestor]) if options[:ancestor]
      query_property_filter(query, options)
      entities = log_gcloud_error { CloudDatastore.dataset.run(query) }
      from_entities(entities.flatten)
    end

    # Queries objects from Cloud Datastore in batches by named kind and using the provided options.
    # When a limit option is provided queries up to the limit and returns results with a cursor.
    #
    # @param [Hash] options the options to construct the query with. See build_query for options.
    #
    # @return [Array<Model>, String] an array of ActiveModel results and a cursor that can be used
    # to query for additional results.
    def find_in_batches(options = {})
      next_cursor = nil
      query = build_query(options)
      if options[:limit]
        entities = log_gcloud_error { CloudDatastore.dataset.run(query) }
        next_cursor = entities.cursor if entities.size == options[:limit]
      else
        batch_size = Rails.application.config_for(:settings)['batch_size']
        query.limit(batch_size)
        entities = find_all(query, batch_size)
      end
      model_entities = from_entities(entities.flatten)
      return model_entities, next_cursor
    end

    # Retrieves an entity by key and by an optional parent.
    #
    # @param [Integer or String] id_or_name id or name value of the entity Key.
    # @param [Gcloud::Datastore::Key] parent the parent Key of the entity.
    #
    # @return [Entity, nil] a Gcloud::Datastore::Entity object or nil.
    def find_entity(id_or_name, parent = nil)
      key = Gcloud::Datastore::Key.new(name, id_or_name)
      key.parent = parent if parent
      CloudDatastore.dataset.find(key)
    end

    # Find object by ID.
    #
    # @return [Model, nil] an ActiveModel object or nil.
    def find(id)
      entity = find_entity(id.to_i)
      from_entity(entity)
    end

    # Find object by parent and ID.
    #
    # @return [Model, nil] an ActiveModel object or nil.
    def find_by_parent(id, parent)
      entity = find_entity(id.to_i, parent)
      from_entity(entity)
    end

    def from_entities(entities)
      entities.map { |entity| from_entity(entity) }
    end

    # Translates between Gcloud::Datastore::Entity objects and ActiveModel::Model objects.
    #
    # @param [Entity] entity from Cloud Datastore
    # @return [Model] the translated ActiveModel object.
    def from_entity(entity)
      return if entity.nil?
      model_entity = new
      model_entity.id = entity.key.id unless entity.key.id.nil?
      model_entity.id = entity.key.name unless entity.key.name.nil?
      entity.properties.to_hash.each do |name, value|
        model_entity.send "#{name}=", value
      end
      model_entity
    end

    def exclude_from_index(entity, boolean)
      entity.properties.to_h.keys.each do |value|
        entity.exclude_from_indexes! value, boolean
      end
    end

    # Constructs a Gcloud::Datastore::Query.
    #
    # @param [Hash] options the options to construct the query with.
    #
    # @option options [Gcloud::Datastore::Key] :ancestor filter for results that inherit from a key
    # @option options [String] :cursor sets the cursor to start the results at
    # @option options [Integer] :limit sets a limit to the number of results to be returned
    # @option options [String] :order sort the results by property name
    # @option options [String] :desc_order sort the results by descending property name
    # @option options [Array] :select retrieve only select properties from the matched entities
    # @option options [Hash] :where filter, Array in the format [name, operator, value]
    #
    # @return [Query] a gcloud datastore query.
    def build_query(options = {})
      query = Gcloud::Datastore::Query.new
      query.kind(name)
      query_options(query, options)
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
        return false if retry_count > 3
        retry
      end
      true
    end

    def log_gcloud_error
      yield
    rescue Gcloud::Error => e
      puts "\e[33m[#{e.message.inspect}]\e[0m"
      raise e
    end

    # private

    def query_options(query, options)
      query.ancestor(options[:ancestor]) if options[:ancestor]
      query.cursor(options[:cursor]) if options[:cursor]
      query.limit(options[:limit]) if options[:limit]
      query_sort(query, options)
      query.select(options[:select]) if options[:select]
      query_property_filter(query, options)
    end

    # Adds sorting to the results by a property name if included in the options.
    def query_sort(query, options)
      query.order(options[:order]) if options[:order]
      query.order(options[:desc_order], :desc) if options[:desc_order]
      query
    end

    # Adds property filters to the query if included in the options.
    # Accepts individual or nested Arrays:
    # [['superseded', '=', false], ['email', '=', 'something']]
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

    def find_all(query, batch_size)
      entities = []
      loop do
        results = log_gcloud_error { CloudDatastore.dataset.run(query) }
        entities << results
        break if results.size < batch_size
        query.cursor(results.cursor)
      end
      entities
    end
  end
end
