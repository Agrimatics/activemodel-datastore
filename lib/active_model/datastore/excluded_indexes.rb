module ActiveModel::Datastore
  module ExcludedIndexes
    extend ActiveSupport::Concern

    def no_index_attributes
      []
    end

    ##
    # Sets all entity properties to be included/excluded from the Datastore indexes.
    #
    def exclude_from_index(entity, boolean)
      entity.properties.to_h.each_key do |value|
        entity.exclude_from_indexes! value, boolean
      end
    end

    module ClassMethods
      ##
      # Sets attributes to be excluded from the Datastore indexes.
      #
      # Overrides no_index_attributes to return an Array of the attributes configured
      # to be indexed.
      #
      # For example, an indexed string property can not exceed 1500 bytes. String properties
      # that are not indexed can be up to 1,048,487 bytes. All properties indexed by default.
      #
      def no_indexes(*attributes)
        attributes = attributes.collect(&:to_s)
        define_method('no_index_attributes') { attributes }
      end

      def clear_index_exclusions!
        define_method('no_index_attributes') { [] }
      end
    end
  end
end
