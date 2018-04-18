require 'bundler/setup'
require 'active_support'
require 'active_support/testing/autorun'
require 'entity_class_method_extensions'
require 'factory_bot'
require 'faker'

require 'google/cloud/datastore'
require 'active_model'
require 'carrierwave'
require 'active_model/datastore/carrier_wave_uploader'
require 'active_model/datastore/connection'
require 'active_model/datastore/errors'
require 'active_model/datastore/excluded_indexes'
require 'active_model/datastore/nested_attr'
require 'active_model/datastore/property_values'
require 'active_model/datastore/track_changes'
require 'active_model/datastore/batch_operation'
require 'active_model/datastore'
require 'action_controller/metal/strong_parameters'

FactoryBot.find_definitions

MOCK_PARENT_ID = 1010101010101010

class MockModel
  include ActiveModel::Datastore
  attr_accessor :name, :role, :image, :images
  validates :name, presence: true
  enable_change_tracking :name, :role

  def entity_properties
    %w[name role image images]
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

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  def setup
    if `lsof -t -i TCP:8181`.to_i.zero?
      puts 'Starting the cloud datastore emulator in test mode.'
      data_dir = File.join(File.expand_path('..', __dir__), 'tmp', 'test_datastore')
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
    if defined?(Rails) != 'constant'
      ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
      ENV['GCLOUD_PROJECT'] = 'test-datastore'
    end
    CloudDatastore.dataset
    carrierwave_init
  end

  def carrierwave_init
    CarrierWave.configure do |config|
      config.reset_config
      config.storage = :file
      config.enable_processing = false
      config.root = File.join(Dir.pwd, 'tmp', 'carrierwave-tests')
      config.cache_dir = 'carrierwave-cache'
    end
  end

  def teardown
    delete_all_test_entities!
    FileUtils.rm_rf(CarrierWave::Uploader::Base.root)
    CarrierWave.configure(&:reset_config)
    MockModel.clear_index_exclusions!
  end

  def delete_all_test_entities!
    entity_kinds = %w[MockModelParent MockModel]
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
