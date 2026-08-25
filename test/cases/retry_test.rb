require 'test_helper'
require 'minitest/mock'

class ActiveModel::DatastoreRetryTest < Minitest::Test
  def teardown
    ActiveModel::Datastore.logger = nil
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
end
