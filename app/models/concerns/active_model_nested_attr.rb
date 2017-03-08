# frozen_string_literal: true

##
# = Cloud Datastore Active Model Nested Attributes
#
# Adds support for nested attributes to ActiveModel. Heavily inspired by Rails
# ActiveRecord::NestedAttributes.
#
# Nested attributes allow you to save attributes on associated records along with the parent.
# It's used in conjunction with fields_for to build the nested form elements.
#
# See Rails ActionView::Helpers::FormHelper::fields_for for more info.
#
# *NOTE*: Unlike ActiveRecord, the way that the relationship is modeled between the parent and
# child is not enforced. With NoSQL the relationship could be defined by any attribute, or with
# denormalization exist within the same entity. This library provides a way for the objects to
# be associated yet saved to the datastore in any way that you choose.
#
# You enable nested attributes by defining an +:attr_accessor+ on the parent with the pluralized
# name of the child model.
#
# Nesting also requires that a +<association_name>_attributes=+ writer method is defined in your
# parent model. If an object with an association is instantiated with a params hash, and that
# hash has a key for the association, Rails will call the +<association_name>_attributes=+
# method on that object. Within the writer method call +assign_nested_attributes+, passing in
# the association name and attributes.
#
# Let's say we have a parent Recipe with RecipeContent children.
#
# Start by defining within the Recipe model:
# * an attr_accessor of +:recipe_contents+
# * a writer method named +recipe_contents_attributes=+
# * the +validates_associated+ method can be used to validate the nested objects
#
# Example:
#   class Recipe
#     attr_accessor :recipe_contents
#     validates :recipe_contents, presence: true
#     validates_associated :recipe_contents
#
#     def recipe_contents_attributes=(attributes)
#       assign_nested_attributes(:recipe_contents, attributes)
#     end
#   end
#
# You may also set a +:reject_if+ proc to silently ignore any new record hashes if they fail to
# pass your criteria. For example:
#
#   class Recipe
#     def recipe_contents_attributes=(attributes)
#       reject_proc = proc { |attributes| attributes['name'].blank? }
#       assign_nested_attributes(:recipe_contents, attributes, reject_if: reject_proc)
#     end
#   end
#
# Alternatively, +:reject_if+ also accepts a symbol for using methods:
#
#   class Recipe
#     def recipe_contents_attributes=(attributes)
#       reject_proc = proc { |attributes| attributes['name'].blank? }
#       assign_nested_attributes(:recipe_contents, attributes, reject_if: reject_recipes)
#     end
#
#     def reject_recipes(attributes)
#       attributes['name'].blank?
#     end
#   end
#
# Within the parent model +valid?+ will validate the parent and associated children and
# +nested_models+ will return the child objects. If the nested form submitted params contained
# a truthy +_destroy+ key, the appropriate nested_models will have +marked_for_destruction+ set
# to True.
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
  # For each attribute name in nested_attributes extract and return the nested model objects.
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
  # Assigns the given nested child attributes.
  #
  # Attribute hashes with an +:id+ value matching an existing associated object will update
  # that object. Hashes without an +:id+ value will build a new object for the association.
  # Hashes with a matching +:id+ value and a +:_destroy+ key set to a truthy value will mark
  # the matched object for destruction.
  #
  # Pushes a key of the association name onto the parent object's +nested_attributes+ attribute.
  # The +nested_attributes+ can be used for determining when the parent has associated children.
  #
  # @param [Symbol] association_name The attribute name of the associated children.
  # @param [ActiveSupport::HashWithIndifferentAccess, ActionController::Parameters] attributes
  #     The attributes provided by Rails ActionView. Typically new objects will arrive as
  #     ActiveSupport::HashWithIndifferentAccess and updates as ActionController::Parameters.
  # @param [Hash] options The options to control how nested attributes are applied.
  #
  # @option options [Proc, Symbol] :reject_if Allows you to specify a Proc or a Symbol pointing
  #     to a method that checks whether a record should be built for a certain attribute
  #     hash. The hash is passed to the supplied Proc or the method and it should return either
  #     +true+ or +false+. Passing +:all_blank+ instead of a Proc will create a proc
  #     that will reject a record where all the attributes are blank.
  #
  # The following example will update the amount of the RecipeContent with ID 1, build a new
  # associated recipe content with the amount of 45, and mark the associated RecipeContent
  # with ID 2 for destruction.
  #
  #   assign_nested_attributes(:recipe_contents, {
  #     '0' => { id: '1', amount: '123' },
  #     '1' => { amount: '45' },
  #     '2' => { id: '2', _destroy: true }
  #   })
  #
  def assign_nested_attributes(association_name, attributes, options = {})
    attributes = validate_attributes(attributes)
    association_name = association_name.to_sym
    send("#{association_name}=", []) if send(association_name).nil?

    attributes.each do |_i, params|
      if params['id'].blank?
        unless reject_new_record?(params, options)
          send(association_name).push(association_name.to_c.new(params.except(*UNASSIGNABLE_KEYS)))
        end
      else
        existing = send(association_name).detect { |record| record.id.to_s == params['id'].to_s }
        assign_to_or_mark_for_destruction(existing, params)
      end
    end
    (self.nested_attributes ||= []).push(association_name)
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

  ##
  # Determines if a new record should be rejected by checking if a <tt>:reject_if</tt> option
  # exists and evaluates to +true+.
  #
  def reject_new_record?(attributes, options)
    call_reject_if(attributes, options)
  end

  ##
  # Determines if a record with the particular +attributes+ should be rejected by calling the
  # reject_if Symbol or Proc (if provided in options).
  #
  # Returns false if there is a +destroy_flag+ on the attributes.
  #
  def call_reject_if(attributes, options)
    return false if destroy_flag?(attributes)
    attributes = attributes.with_indifferent_access
    blank_proc = proc { |attrs| attrs.all? { |_key, value| value.blank? } }
    options[:reject_if] = blank_proc if options[:reject_if] == :all_blank
    case callback = options[:reject_if]
    when Symbol
      method(callback).arity.zero? ? send(callback) : send(callback, attributes)
    when Proc
      callback.call(attributes)
    else
      false
    end
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
