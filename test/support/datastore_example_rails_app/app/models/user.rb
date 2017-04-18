class User
  include ActiveModel::Datastore

  attr_accessor :email, :enabled, :name, :role, :state

  before_validation :set_default_values
  after_validation :format_values

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }
  validates :role, presence: true

  def entity_properties
    %w[email enabled name role]
  end

  def set_default_values
    default_property_value :enabled, true
    default_property_value :role, 1
  end

  def format_values
    format_property_value :role, :integer
  end

  def self.parent_key
    CloudDatastore.dataset.key('Company', 12345)
  end
end
