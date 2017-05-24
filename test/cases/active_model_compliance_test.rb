require 'test_helper'

class ActiveModelComplianceTest < ActiveSupport::TestCase
  include ActiveModel::Lint::Tests

  def setup
    @model = MockModel.new
  end

  def teardown
  end
end
