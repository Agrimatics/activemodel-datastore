# frozen_string_literal: true

##
# Adds support for nested models to ActiveModel.
#
# Created by Bryce McLean on 2016-12-06.
#
module ActiveModelNestedAttr
  extend ActiveSupport::Concern
  include ActiveModel::Model

  included do
    attr_accessor :nested_attributes, :marked_for_destruction, :_destroy
  end

  def mark_for_destruction
    @marked_for_destruction = true
  end

  def marked_for_destruction?
    @marked_for_destruction
  end

  def nested_attributes?
    nested_attributes.is_a?(Array) && !nested_attributes.empty?
  end

  ##
  # If a model object has attributes containing nested models, the name of the attributes will
  # be stored in nested_attributes. For each attribute name in nested_attributes extract and
  # return the nested model objects.
  #
  def nested_models
    model_entities = []
    nested_attributes.each { |attr| model_entities << send(attr.to_sym) } if nested_attributes?
    model_entities.flatten
  end

  def nested_model_class_names
    entity_kinds = []
    if nested_attributes?
      nested_models.each { |x| entity_kinds << x.class.name }
    end
    entity_kinds.uniq
  end

  def nested_errors
    errors = []
    if nested_attributes?
      nested_attributes.each do |attr|
        send(attr.to_sym).each { |child| errors << child.errors }
      end
    end
    errors
  end

  ##
  #
  # Assigns the given nested child attributes to the parent association attribute name.
  #
  # Attribute hashes with an :id value matching an existing associated object will update
  # that object. Hashes without an :id value will build a new object for the association.
  # Hashes with a matching :id value and a :_destroy key set to a truthy value will mark
  # the matched object for destruction.

  # Pushes a key of the attribute name onto the parent object's nested_attributes attribute.
  # The nested_attributes can be used for determining when the parent has associated children.
  #
  # @param [Symbol] attr_name The attribute name of the associated children.
  # @param [ActiveSupport::HashWithIndifferentAccess, ActionController::Parameters] attributes
  #     The attributes provided by Rails ActionView. Typically new objects will arrive as
  #     ActiveSupport::HashWithIndifferentAccess and updates as ActionController::Parameters.
  #
  # For example:
  #
  #   assign_nested_attributes(:recipe_contents, {
  #     '0' => { id: '1', amount: '123 },
  #     '1' => { amount: '45' },
  #     '2' => { id: '2', _destroy: true }
  #   })
  #
  # Will update the amount of the RecipeContent with ID 1, build a new associated recipe content
  # with the amount of 45, and mark the associated RecipeContent with ID 2 for destruction.
  #
  def assign_nested_attributes(attr_name, attributes)
    attributes = validate_attributes(attributes)
    attr_name = attr_name.to_sym
    send("#{attr_name}=", []) if send(attr_name).nil?
    attributes.each do |_i, params|
      if params['id'].blank?
        params.delete(:_destroy) if params[:_destroy]
        send(attr_name).push(attr_name.to_c.new(params))
      else
        existing = send(attr_name).detect { |record| record.id.to_s == params['id'].to_s }
        assign_to_or_mark_for_destruction(existing, params)
      end
    end
    (self.nested_attributes ||= []).push(attr_name)
  end

  private

  UNASSIGNABLE_KEYS = %w(id _destroy).freeze

  def validate_attributes(attributes)
    attributes = attributes.to_h if attributes.respond_to?(:permitted?)
    unless attributes.is_a?(Hash)
      raise ArgumentError, "Hash expected, got #{attributes.class.name} (#{attributes.inspect})"
    end
    attributes
  end

  ##
  # Updates an object with attributes or marks it for destruction if has_destroy_flag? returns true.
  #
  def assign_to_or_mark_for_destruction(record, attributes)
    record.assign_attributes(attributes.except(*UNASSIGNABLE_KEYS))
    record.mark_for_destruction if destroy_flag?(attributes)
  end

  ##
  # Determines if a hash contains a truthy _destroy key.
  #
  def destroy_flag?(hash)
    [true, 1, '1', 't', 'T', 'true', 'TRUE'].include?(hash['_destroy'])
  end

  # Methods defined here will be class methods whenever we 'include DatastoreUtils'.
  module ClassMethods
    ##
    # Validates whether the associated object or objects are all valid, typically used with nested
    # attributes such as multi-model forms.
    #
    # NOTE: This validation will not fail if the association hasn't been assigned. If you want to
    # ensure that the association is both present and guaranteed to be valid, you also need to use
    # validates_presence_of.
    #
    # Nesting also requires that a <association_name>_attributes= method is defined in your
    # Model for non-ActiveRecord nested attributes. If an object with a "one-to-many" association
    # is instantiated with a params hash, and that hash has a key for the association, Rails will
    # call the <association_name>_attributes= method on that object.
    #
    # @example
    #   class Recipe
    #     attr_accessor :recipe_contents
    #     validates :recipe_contents, presence: true
    #     validates_associated :recipe_contents
    #
    #     def recipe_contents_attributes=(attributes)
    #       assign_nested_attributes(:recipe_contents, attributes)
    #     end
    #
    def validates_associated(*attr_names)
      validates_with AssociatedValidator, _merge_attributes(attr_names)
    end
  end

  class AssociatedValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return unless Array(value).reject(&:valid?).any?
      record.errors.add(attribute, :invalid, options.merge(value: value))
    end
  end
end

class Symbol
  def to_c
    to_s.singularize.camelize.constantize
  end
end
