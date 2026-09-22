require 'test_helper'
require 'minitest/mock'

class ActiveModel::DatastoreRetryTest < Minitest::Test
  def setup
    @delays = []
    @read_retry_count = ActiveModel::Datastore.read_retry_count
  end

  def teardown
    ActiveModel::Datastore.logger = nil
    ActiveModel::Datastore.read_retry_count = @read_retry_count
  end

  def test_retry_on_exception_question_mark_returns_successful_result_without_retrying
    result = MockModel.retry_on_exception? { :success }

    assert_equal :success, result
  end

  def test_retry_on_exception_returns_successful_result_without_retrying
    result = MockModel.retry_on_exception { :success }

    assert_equal :success, result
  end

  def test_retry_on_exception_question_mark_preserves_the_legacy_message
    logger = Minitest::Mock.new
    message = "\e[33mRescued exception \"retry error\", retrying in 0.25\e[0m"
    logger.expect(:warn, nil, [message])
    ActiveModel::Datastore.logger = logger
    attempts = 0

    result = MockModel.retry_on_exception?(1) do
      attempts += 1
      raise Google::Cloud::Error, 'retry error' if attempts == 1

      :retried
    end

    assert_equal :retried, result
    logger.verify
  end

  def test_retry_on_exception_preserves_the_legacy_message
    logger = Minitest::Mock.new
    message = "\e[33mRescued exception \"retry error\", retrying in 0.25\e[0m"
    logger.expect(:warn, nil, [message])
    ActiveModel::Datastore.logger = logger
    attempts = 0

    result = MockModel.retry_on_exception(1) do
      attempts += 1
      raise Google::Cloud::Error, 'retry error' if attempts == 1

      :retried
    end

    assert_equal :retried, result
    logger.verify
  end

  def test_retry_on_exception_question_mark_logs_enhanced_context_for_an_operation
    logger = Minitest::Mock.new
    message = "\e[33mDatastore transaction failed for Local after 0 ms: \"retry error\"; " \
              "retrying in 0.25 s\e[0m"
    logger.expect(:warn, nil, [message])
    ActiveModel::Datastore.logger = logger
    attempts = 0

    result = Process.stub(:clock_gettime, 1.0) do
      MockModel.retry_on_exception?(1, operation: 'transaction', kind: 'Local') do
        attempts += 1
        raise Google::Cloud::Error, 'retry error' if attempts == 1

        :retried
      end
    end

    assert_equal :retried, result
    logger.verify
  end

  def test_retry_on_exception_logs_enhanced_context_for_an_operation
    logger = Minitest::Mock.new
    message = "\e[33mDatastore transaction failed for Local after 0 ms: \"retry error\"; " \
              "retrying in 0.25 s\e[0m"
    logger.expect(:warn, nil, [message])
    ActiveModel::Datastore.logger = logger
    attempts = 0

    result = Process.stub(:clock_gettime, 1.0) do
      MockModel.retry_on_exception(1, operation: 'transaction', kind: 'Local') do
        attempts += 1
        raise Google::Cloud::Error, 'retry error' if attempts == 1

        :retried
      end
    end

    assert_equal :retried, result
    logger.verify
  end

  def test_retry_on_exception_question_mark_returns_false_when_retries_are_exhausted
    result = MockModel.retry_on_exception?(0) { raise Google::Cloud::Error, 'retry error' }

    refute result
  end

  def test_retry_on_exception_raises_when_retries_are_exhausted
    error = assert_raises(Google::Cloud::Error) do
      MockModel.retry_on_exception(0) { raise Google::Cloud::Error, 'retry error' }
    end

    assert_equal 'retry error', error.message
  end

  [:retry_on_exception, :retry_on_exception?].each do |helper|
    define_method("test_#{helper}_preserves_successful_values") do
      [nil, false, :success].each do |value|
        attempts = 0
        result = run_retry(helper) do
          attempts += 1
          value
        end

        assert_same value, result
        assert_equal 1, attempts
        assert_empty @delays
      end
    end

    define_method("test_#{helper}_does_not_retry_invalid_arguments") do
      error = Google::Cloud::InvalidArgumentError.new('invalid cursor')
      attempts = 0
      assert_failure(helper, error) do
        run_retry(helper) do
          attempts += 1
          raise error
        end
      end

      assert_equal 1, attempts
      assert_empty @delays
    end

    define_method("test_#{helper}_retries_transient_errors") do
      attempts = 0
      result = run_retry(helper) do
        attempts += 1
        raise Google::Cloud::UnavailableError, 'unavailable' if attempts == 1

        :recovered
      end

      assert_equal :recovered, result
      assert_equal 2, attempts
      assert_equal [0.25], @delays
    end

    define_method("test_#{helper}_exhausts_default_retries") do
      error = Google::Cloud::DeadlineExceededError.new('timeout')
      attempts = 0
      assert_failure(helper, error) do
        run_retry(helper) do
          attempts += 1
          raise error
        end
      end

      assert_equal 6, attempts
      assert_equal [0.25, 0.5, 1, 2, 4], @delays
    end

    define_method("test_#{helper}_honors_explicit_retry_limits") do
      [0, 2].each do |limit|
        @delays.clear
        error = Google::Cloud::UnavailableError.new('unavailable')
        attempts = 0
        assert_failure(helper, error) do
          run_retry(helper, limit) do
            attempts += 1
            raise error
          end
        end

        assert_equal limit + 1, attempts
        assert_equal [0.25, 0.5].take(limit), @delays
      end
    end

    define_method("test_#{helper}_stops_when_a_retry_has_invalid_arguments") do
      error = Google::Cloud::InvalidArgumentError.new('invalid cursor')
      attempts = 0
      assert_failure(helper, error) do
        run_retry(helper) do
          attempts += 1
          raise Google::Cloud::UnavailableError, 'unavailable' if attempts == 1

          raise error
        end
      end

      assert_equal 2, attempts
      assert_equal [0.25], @delays
    end

    define_method("test_#{helper}_propagates_unrelated_errors") do
      error = ArgumentError.new('unrelated error')
      attempts = 0
      raised = assert_raises(ArgumentError) do
        run_retry(helper) do
          attempts += 1
          raise error
        end
      end

      assert_same error, raised
      assert_equal 1, attempts
      assert_empty @delays
    end
  end

  def test_read_retry_count_defaults_to_five
    assert_equal 5, ActiveModel::Datastore.read_retry_count
  end

  def test_find_entity_uses_configured_read_retry_count
    assert_read_retry_count(:find) { MockModel.find_entity(1) }
  end

  def test_find_entities_uses_configured_read_retry_count
    assert_read_retry_count(:find_all) { MockModel.find_entities(1, 2) }
  end

  def test_find_uses_configured_read_retry_count
    assert_read_retry_count(:find) { MockModel.find(1) }
    assert_read_retry_count(:find_all) { MockModel.find(1, 2) }
  end

  def test_all_uses_configured_read_retry_count
    assert_read_retry_count(:run) { MockModel.all(limit: 1) }
  end

  def test_find_by_uses_configured_read_retry_count
    assert_read_retry_count(:run) { MockModel.find_by(name: 'Example') }
  end

  [:save, :update, :destroy].each do |operation|
    define_method("test_read_retry_count_does_not_change_#{operation}_retries") do
      ActiveModel::Datastore.read_retry_count = 0
      model = MockModel.new(name: 'Example', id: 1)
      arguments = operation == :update ? [{ name: 'Updated' }] : []
      rpc = operation == :destroy ? :delete : :save
      result = with_failing_datastore(rpc) { model.public_send(operation, *arguments) }

      assert_equal false, result
      assert_equal 6, @attempts
      assert_equal [0.25, 0.5, 1, 2, 4], @delays
    end
  end

  private

  def run_retry(helper, *limits, &block)
    with_recorded_sleeps { MockModel.public_send(helper, *limits, &block) }
  end

  def with_recorded_sleeps
    result = nil
    capture_io do
      MockModel.stub(:sleep, ->(delay) { @delays << delay }) do
        result = yield
      end
    end
    result
  end

  def assert_failure(helper, error, &block)
    if helper == :retry_on_exception
      assert_same error, assert_raises(error.class, &block)
    else
      assert_equal false, block.call
    end
  end

  def assert_read_retry_count(rpc, &block)
    [0, 2, 5].each do |count|
      ActiveModel::Datastore.read_retry_count = count
      @delays.clear
      assert_raises(Google::Cloud::UnavailableError) do
        with_failing_datastore(rpc, &block)
      end

      assert_equal count + 1, @attempts
      assert_equal [0.25, 0.5, 1, 2, 4].take(count), @delays
    end
  end

  def with_failing_datastore(rpc, &block)
    @attempts = 0
    failure = lambda do |*_args|
      @attempts += 1
      raise Google::Cloud::UnavailableError, 'unavailable'
    end
    dataset = Google::Cloud::Datastore::Dataset.new(nil)
    with_recorded_sleeps do
      CloudDatastore.stub(:dataset, dataset) do
        dataset.stub(rpc, failure, &block)
      end
    end
  end
end
