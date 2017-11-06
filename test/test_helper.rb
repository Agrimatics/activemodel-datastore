require 'bundler/setup'
require 'active_support'
require 'active_support/testing/autorun'
require 'entity_class_method_extensions'
require 'minitest/reporters'
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
require 'active_model/datastore'
require 'action_controller/metal/strong_parameters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
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
      data_dir = File.join(File.expand_path('../..', __FILE__), 'tmp', 'test_datastore')
      # Start the test Cloud Datastore Emulator in 'testing' mode (data is stored in memory only).
      system("cloud_datastore_emulator start --port=8181 --testing #{data_dir} &")
      sleep 3
    end
    if defined?(Rails) != 'constant'
      ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
      ENV['GCLOUD_PROJECT'] = 'test-datastore'
    end
    CloudDatastore.dataset
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
