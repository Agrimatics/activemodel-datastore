ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../config/environment', __dir__)
require 'entity_class_method_extensions'
require 'rails/test_help'

MOCK_ACCOUNT_ID = 1010101010101010

class MockModel
  include ActiveModel::Datastore
  attr_accessor :name, :role
  validates :name, presence: true
  enable_change_tracking :name, :role

  def entity_properties
    %w[name role]
  end
end

class MockModelParent
  include ActiveModel::Datastore::NestedAttr
  attr_accessor :name
  attr_accessor :mock_models
end

# Make the methods within EntityTestExtensions available as class methods.
MockModel.send :extend, EntityClassMethodExtensions
MockModelParent.send :extend, EntityClassMethodExtensions
User.send :extend, EntityClassMethodExtensions

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  def setup
    if `lsof -t -i TCP:8181`.to_i.zero?
      puts 'Starting the cloud datastore emulator in test mode.'
      data_dir = Rails.root.join('tmp', 'test_datastore')
      spawn "cloud_datastore_emulator start --port=8181 --testing #{data_dir} > /dev/null 2>&1"
      loop do
        begin
          Net::HTTP.get('localhost', '/', '8181').include? 'Ok'
          break
        rescue Errno::ECONNREFUSED
          sleep 0.2
        end
      end
    end
    CloudDatastore.dataset
  end

  def teardown
    delete_all_test_entities!
  end

  def delete_all_test_entities!
    entity_kinds = %w[MockModelParent MockModel User]
    entity_kinds.each do |kind|
      query = CloudDatastore.dataset.query(kind)
      loop do
        entities = CloudDatastore.dataset.run(query)
        break if entities.empty?

        CloudDatastore.dataset.delete(*entities)
      end
    end
  end
end
