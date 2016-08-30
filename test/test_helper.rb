# frozen_string_literal: true
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'entity_test_extensions'
require 'rails/test_help'
require 'minitest/reporters'
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

MOCK_ACCOUNT_ID = 1010101010101010

class MockModel
  include ActiveModelCloudDatastore
  attr_accessor :name
  attr_reader :role
  validates :name, presence: true

  # ActiveModel::Dirty tracking
  define_attribute_methods :role

  def role=(val)
    role_will_change! unless val == @role
    @role = val
  end

  def attributes
    %w(name role)
  end
end

# Make the methods within EntityTestExtensions available as class methods.
MockModel.send :extend, EntityTestExtensions

module ActiveSupport
  class TestCase
    def setup
      if `lsof -t -i TCP:8181`.to_i == 0
        data_dir = Rails.root.join('tmp', 'test_datastore')
        # Start the test Cloud Datastore Emulator in 'testing' mode (data is stored in memory only).
        system("cloud_datastore_emulator start --port=8181 --testing #{data_dir} &")
        sleep 3
      end
      CloudDatastore.dataset
    end

    def teardown
      MockModel.delete_all_test_entities!
    end
  end
end
