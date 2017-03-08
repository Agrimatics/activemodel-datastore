class User
  include ActiveModelCloudDatastore
  attr_accessor :email, :name, :enabled

  before_validation :set_default_values
  # after_save :something_can_go_here
  # after_destroy :something_can_go_here

  validates :email, presence: true, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }

  def entity_properties
    %w(email name enabled)
  end

  def set_default_values
    default :enabled, true
  end
end
