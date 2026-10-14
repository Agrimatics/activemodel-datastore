require 'test_helper'
require 'minitest/mock'

class ActiveModel::DatastorePaginationTest < Minitest::Test
  def setup
    @service = Minitest::Mock.new(Object.new)
    @dataset = Google::Cloud::Datastore::Dataset.new(@service)
    @delays = []
    @read_retry_count = ActiveModel::Datastore.read_retry_count
    @slow_operation_threshold = ActiveModel::Datastore.slow_operation_threshold
  end

  def teardown
    super
    ActiveModel::Datastore.read_retry_count = @read_retry_count
    ActiveModel::Datastore.slow_operation_threshold = @slow_operation_threshold
  end

  def test_split_page_returns_last_cursor_and_resumes_without_gaps_or_duplicates
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
    expect_batch([3, 4], limit: 2, cursor: 'after-2', more: :MORE_RESULTS_AFTER_LIMIT)
    expect_batch([5, 6], limit: 4, cursor: 'after-4')

    CloudDatastore.stub(:dataset, @dataset) do
      first_page, cursor = MockModel.all(limit: 4)
      assert_equal [1, 2, 3, 4], first_page.map(&:id)
      assert_equal 'after-4', cursor&.to_grpc
      assert_equal %w[Entity1 Entity2 Entity3 Entity4], first_page.map(&:name)
      assert(first_page.all? { |model| model.is_a?(MockModel) && !model.changed? })

      last_page, last_cursor = MockModel.all(limit: 4, cursor: cursor.to_s)
      assert_equal [1, 2, 3, 4, 5, 6], (first_page + last_page).map(&:id)
      assert_nil last_cursor
    end
    @service.verify
  end

  def test_single_batch_full_page_preserves_its_cursor
    expect_batch([1, 2], limit: 2, more: :MORE_RESULTS_AFTER_LIMIT)

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 2)
      assert_equal [1, 2], models.map(&:id)
      assert_equal 'after-2', cursor.to_grpc
    end
    @service.verify
  end

  def test_single_batch_uses_end_cursor_when_entity_cursors_are_missing
    expect_batch([1, 2], limit: 2, more: :MORE_RESULTS_AFTER_LIMIT, entity_cursors: false)

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 2)
      assert_equal [1, 2], models.map(&:id)
      assert_equal 'after-2', cursor&.to_grpc
    end
    @service.verify
  end

  def test_split_page_resumes_from_final_batch_when_entity_cursors_are_missing
    expect_batch([1], limit: 2, more: :NOT_FINISHED, entity_cursors: false)
    expect_batch([2], limit: 1, cursor: 'after-1', more: :MORE_RESULTS_AFTER_LIMIT,
                      entity_cursors: false)
    expect_batch([3], limit: 2, cursor: 'after-2', entity_cursors: false)

    CloudDatastore.stub(:dataset, @dataset) do
      first_page, cursor = MockModel.all(limit: 2)
      assert_equal [1, 2], first_page.map(&:id)
      assert_equal 'after-2', cursor&.to_grpc

      last_page, last_cursor = MockModel.all(limit: 2, cursor: cursor.to_s)
      assert_equal [1, 2, 3], (first_page + last_page).map(&:id)
      assert_nil last_cursor
    end
    @service.verify
  end

  def test_split_short_page_has_no_cursor
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
    expect_batch([3], limit: 2, cursor: 'after-2')

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 4)
      assert_equal [1, 2, 3], models.map(&:id)
      assert_nil cursor
    end
    @service.verify
  end

  def test_exactly_full_final_page_still_returns_a_cursor
    expect_batch([1], limit: 2, more: :NOT_FINISHED)
    expect_batch([2], limit: 1, cursor: 'after-1')

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 2)
      assert_equal [1, 2], models.map(&:id)
      assert_equal 'after-2', cursor&.to_grpc
    end
    @service.verify
  end

  def test_empty_page_has_no_cursor
    expect_batch([], limit: 4)

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 4)
      assert_empty models
      assert_nil cursor
    end
    @service.verify
  end

  def test_zero_limit_returns_the_batch_cursor_without_entities
    start_cursor = Google::Cloud::Datastore::Cursor.from_grpc('after-2')
    expect_batch([], limit: 0, cursor: 'after-2', more: :MORE_RESULTS_AFTER_LIMIT)

    CloudDatastore.stub(:dataset, @dataset) do
      models, cursor = MockModel.all(limit: 0, cursor: start_cursor.to_s)
      assert_empty models
      assert_equal start_cursor, cursor
    end
    @service.verify
  end

  def test_query_without_a_limit_still_returns_all_models_across_batches
    expect_batch([1, 2], limit: nil, more: :NOT_FINISHED)
    expect_batch([3], limit: nil, cursor: 'after-2')

    CloudDatastore.stub(:dataset, @dataset) do
      models = MockModel.all
      assert_equal [1, 2, 3], models.map(&:id)
    end
    @service.verify
  end

  def test_failed_later_batch_retries_the_whole_page_with_the_original_limit
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
    expect_unavailable(limit: 2, cursor: 'after-2')
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
    expect_batch([3, 4], limit: 2, cursor: 'after-2', more: :MORE_RESULTS_AFTER_LIMIT)

    output = with_recorded_sleeps do
      models, cursor = MockModel.all(limit: 4)
      assert_equal [1, 2, 3, 4], models.map(&:id)
      assert_equal 'after-4', cursor&.to_grpc
    end

    assert_equal ['Datastore run query failed for MockModel after 0 ms: "unavailable"; ' \
                  'retrying in 0.25 s'], log_lines(output)
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_later_batch_that_keeps_failing_raises_after_the_read_retry_count
    ActiveModel::Datastore.read_retry_count = 2
    3.times do
      expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
      expect_unavailable(limit: 2, cursor: 'after-2')
    end

    output = with_recorded_sleeps do
      error = assert_raises(Google::Cloud::UnavailableError) { MockModel.all(limit: 4) }
      assert_equal 'unavailable', error.message
    end

    failure = 'Datastore run query failed for MockModel after 0 ms: "unavailable"; '
    endings = ['retrying in 0.25 s', 'retrying in 0.5 s', 'giving up after 3 attempts']
    assert_equal(endings.map { |ending| failure + ending }, log_lines(output))
    assert_equal [0.25, 0.5], @delays
    @service.verify
  end

  def test_non_retryable_later_batch_error_gives_up_without_rereading_the_page
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED)
    expect_batch([], limit: 2, cursor: 'after-2') do
      raise Google::Cloud::InvalidArgumentError, 'invalid cursor'
    end

    output = with_recorded_sleeps do
      error = assert_raises(Google::Cloud::InvalidArgumentError) { MockModel.all(limit: 4) }
      assert_equal 'invalid cursor', error.message
    end

    assert_equal ['Datastore run query failed for MockModel after 0 ms: "invalid cursor"; ' \
                  'giving up after 1 attempts'], log_lines(output)
    assert_empty @delays
    @service.verify
  end

  def test_retry_from_a_cursor_restarts_at_that_cursor_and_discards_partial_rows
    start_cursor = Google::Cloud::Datastore::Cursor.from_grpc('after-4').to_s
    expect_batch([5, 6], limit: 4, cursor: 'after-4', more: :NOT_FINISHED)
    expect_unavailable(limit: 2, cursor: 'after-6')
    expect_batch([5, 6, 7], limit: 4, cursor: 'after-4', more: :NOT_FINISHED)
    expect_batch([8], limit: 1, cursor: 'after-7', more: :MORE_RESULTS_AFTER_LIMIT)

    with_recorded_sleeps do
      models, cursor = MockModel.all(limit: 4, cursor: start_cursor)
      assert_equal [5, 6, 7, 8], models.map(&:id)
      assert_equal 'after-8', cursor&.to_grpc
    end
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_slow_later_batch_counts_toward_the_page_slow_operation_warning
    clock = 0.0
    expect_batch([1, 2], limit: 4, more: :NOT_FINISHED) { clock += 1 }
    expect_batch([3, 4], limit: 2, cursor: 'after-2', more: :MORE_RESULTS_AFTER_LIMIT) do
      clock += 5
    end

    output, = capture_io do
      Process.stub(:clock_gettime, ->(_) { clock }) do
        CloudDatastore.stub(:dataset, @dataset) do
          models, cursor = MockModel.all(limit: 4)
          assert_equal [1, 2, 3, 4], models.map(&:id)
          assert_equal 'after-4', cursor&.to_grpc
        end
      end
    end

    assert_equal "\e[33mDatastore run query for MockModel took 6000 ms\e[0m\n", output
    @service.verify
  end

  def test_query_without_a_limit_retries_only_the_failed_later_batch
    expect_batch([1, 2], limit: nil, more: :NOT_FINISHED)
    expect_unavailable(limit: nil, cursor: 'after-2')
    expect_batch([3], limit: nil, cursor: 'after-2')

    output = with_recorded_sleeps do
      assert_equal [1, 2, 3], MockModel.all.map(&:id)
    end

    assert_equal ['Datastore run query failed for MockModel after 0 ms: "unavailable"; ' \
                  'retrying in 0.25 s'], log_lines(output)
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_query_without_a_limit_raises_when_a_later_batch_keeps_failing
    ActiveModel::Datastore.read_retry_count = 1
    expect_batch([1, 2], limit: nil, more: :NOT_FINISHED)
    2.times { expect_unavailable(limit: nil, cursor: 'after-2') }

    output = with_recorded_sleeps do
      assert_raises(Google::Cloud::UnavailableError) { MockModel.all }
    end

    failure = 'Datastore run query failed for MockModel after 0 ms: "unavailable"; '
    endings = ['retrying in 0.25 s', 'giving up after 2 attempts']
    assert_equal(endings.map { |ending| failure + ending }, log_lines(output))
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_query_without_a_limit_times_each_later_batch
    clock = 0.0
    expect_batch([1, 2], limit: nil, more: :NOT_FINISHED) { clock += 1 }
    expect_batch([3], limit: nil, cursor: 'after-2') { clock += 6 }

    output, = capture_io do
      Process.stub(:clock_gettime, ->(_) { clock }) do
        CloudDatastore.stub(:dataset, @dataset) do
          assert_equal [1, 2, 3], MockModel.all.map(&:id)
        end
      end
    end

    assert_equal "\e[33mDatastore run query for MockModel took 6000 ms\e[0m\n", output
    @service.verify
  end

  def test_find_retries_only_the_failed_deferred_lookup
    expect_lookup([1, 2, 3], found: [1], deferred: [2, 3])
    expect_lookup([2, 3]) { raise Google::Cloud::UnavailableError, 'unavailable' }
    expect_lookup([2, 3], found: [2, 3])

    output = with_recorded_sleeps do
      models = MockModel.find(1, 2, 3)
      assert_equal [1, 2, 3], models.map(&:id)
      assert(models.all?(MockModel))
    end

    assert_equal ['Datastore find all failed for MockModel after 0 ms: "unavailable"; ' \
                  'retrying in 0.25 s'], log_lines(output)
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_find_entities_raises_when_a_deferred_lookup_keeps_failing
    ActiveModel::Datastore.read_retry_count = 1
    expect_lookup([1, 2], found: [1], deferred: [2])
    2.times { expect_lookup([2]) { raise Google::Cloud::UnavailableError, 'unavailable' } }

    output = with_recorded_sleeps do
      assert_raises(Google::Cloud::UnavailableError) { MockModel.find_entities(1, 2) }
    end

    failure = 'Datastore find all failed for MockModel after 0 ms: "unavailable"; '
    endings = ['retrying in 0.25 s', 'giving up after 2 attempts']
    assert_equal(endings.map { |ending| failure + ending }, log_lines(output))
    assert_equal [0.25], @delays
    @service.verify
  end

  def test_find_entities_returns_found_and_deferred_entities
    expect_lookup([1, 2], found: [1], deferred: [2])
    expect_lookup([2], found: [2])

    CloudDatastore.stub(:dataset, @dataset) do
      entities = MockModel.find_entities(1, 2)
      assert_instance_of Array, entities
      assert_equal([1, 2], entities.map { |entity| entity.key.id })
    end
    @service.verify
  end

  private

  # Freezes the clock so retry logs report 0 ms, and records backoff delays instead of sleeping.
  def with_recorded_sleeps(&block)
    output, = capture_io do
      Process.stub(:clock_gettime, 1.0) do
        MockModel.stub(:sleep, ->(delay) { @delays << delay }) do
          CloudDatastore.stub(:dataset, @dataset, &block)
        end
      end
    end
    output
  end

  def log_lines(output)
    output.lines.map { |line| line.chomp.gsub(/\e\[\d+m/, '') }
  end

  # Stub only the RPC responses: the real client follows NOT_FINISHED batches,
  # decodes entity cursors, and reduces the remaining limit on each request.
  # An optional block runs during the request, e.g. to raise an error or advance a clock.
  def expect_batch(ids, limit:, cursor: '', more: :NO_MORE_RESULTS, entity_cursors: true)
    response = batch_response(ids, cursor, more)
    response.batch.entity_results.each { |result| result.cursor = '' } unless entity_cursors
    @service.expect(:run_query, response) do |query, _namespace, **_options|
      assert_equal cursor, query.start_cursor
      limit.nil? ? assert_nil(query.limit) : assert_equal(limit, query.limit.value)
      yield if block_given?
      true
    end
  end

  def expect_unavailable(limit:, cursor:)
    expect_batch([], limit: limit, cursor: cursor) do
      raise Google::Cloud::UnavailableError, 'unavailable'
    end
  end

  # Stubs one Lookup RPC for the given ids, returning found entities and deferred keys.
  def expect_lookup(ids, found: [], deferred: [])
    response = Google::Cloud::Datastore::V1::LookupResponse.new(
      found: found.map { |id| { entity: mock_entity(id).to_grpc } },
      deferred: deferred.map { |id| @dataset.key('MockModel', id).to_grpc }
    )
    @service.expect(:lookup, response) do |*keys, **_options|
      assert_equal(ids, keys.map { |key| key.path.last.id })
      yield if block_given?
      true
    end
  end

  def mock_entity(id)
    entity = @dataset.entity('MockModel', id)
    entity['name'] = "Entity#{id}"
    entity
  end

  def batch_response(ids, start_cursor, more)
    results = ids.map { |id| { entity: mock_entity(id).to_grpc, cursor: "after-#{id}" } }
    Google::Cloud::Datastore::V1::RunQueryResponse.new(
      batch: {
        entity_results: results,
        end_cursor: ids.empty? ? start_cursor : "after-#{ids.last}",
        more_results: more
      }
    )
  end
end
