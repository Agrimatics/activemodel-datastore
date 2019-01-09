require 'active_model/type'

module ActiveModel::Datastore
  module PropertyValues
    extend ActiveSupport::Concern

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
      when :integer
        send("#{attr.to_sym}=", send(attr.to_sym).to_i)
      when :float
        send("#{attr.to_sym}=", send(attr.to_sym).to_f)
      when :boolean
        send("#{attr.to_sym}=", ActiveModel::Type::Boolean.new.cast(send(attr.to_sym)))
      else
        raise ArgumentError, 'Supported types are :boolean, :integer, :float'
      end
    end
  end
end
