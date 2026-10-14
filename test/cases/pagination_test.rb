require 'test_helper'
require 'minitest/mock'

class ActiveModel::DatastorePaginationTest < Minitest::Test
  def setup
    @service = Minitest::Mock.new(Object.new)
    @dataset = Google::Cloud::Datastore::Dataset.new(@service)
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

  def test_query_without_a_limit_still_returns_all_models_across_batches
    expect_batch([1, 2], limit: nil, more: :NOT_FINISHED)
    expect_batch([3], limit: nil, cursor: 'after-2')

    CloudDatastore.stub(:dataset, @dataset) do
      models = MockModel.all
      assert_equal [1, 2, 3], models.map(&:id)
    end
    @service.verify
  end

  private

  # Stub only the RPC responses: the real client follows NOT_FINISHED batches,
  # decodes entity cursors, and reduces the remaining limit on each request.
  def expect_batch(ids, limit:, cursor: '', more: :NO_MORE_RESULTS, entity_cursors: true)
    response = batch_response(ids, cursor, more)
    response.batch.entity_results.each { |result| result.cursor = '' } unless entity_cursors
    @service.expect(:run_query, response) do |query, _namespace, **_options|
      assert_equal cursor, query.start_cursor
      limit.nil? ? assert_nil(query.limit) : assert_equal(limit, query.limit.value)
      true
    end
  end

  def batch_response(ids, start_cursor, more)
    results = ids.map do |id|
      entity = @dataset.entity('MockModel', id)
      entity['name'] = "Entity#{id}"
      { entity: entity.to_grpc, cursor: "after-#{id}" }
    end
    Google::Cloud::Datastore::V1::RunQueryResponse.new(
      batch: {
        entity_results: results,
        end_cursor: ids.empty? ? start_cursor : "after-#{ids.last}",
        more_results: more
      }
    )
  end
end
