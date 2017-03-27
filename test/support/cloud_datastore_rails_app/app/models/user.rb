# frozen_string_literal: true

class User
  include ActiveModel::Datastore

  attr_accessor :email, :name, :enabled, :role

  before_validation :set_default_values
  after_validation :format_values

  before_save { puts '** something can happen before save **' }
  after_save { puts '** something can happen after save **' }

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }

  def entity_properties
    %w(email name enabled)
  end

  def set_default_values
    default_property_value :enabled, true
  end

  def format_values
    format_property_value :role, :integer
  end
end
