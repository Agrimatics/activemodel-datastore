##
# Batch operations
#
#
# Such batch calls are faster than making separate calls for each individual entity because they
# incur the overhead for only one service call.
#
# reference: https://cloud.google.com/datastore/docs/concepts/entities#batch_operations
#
# group = Group.find(params[:group_id])
# users = %w{ alice bob charlie }.map{ |name| User.new(name: name) }
# saved_users = ActiveModel::Datastore.save_all(users, parent: group)
#
module ActiveModel::Datastore
  def self.save_all(entries, parent: nil)
    return if entries.reject(&:valid?).present?
    entries.each_slice(500).map do |sliced_entries|
      entities = []
      results = nil
      fn = lambda do |n|
        entry = sliced_entries[n]
        entry.run_callbacks(:save) do
          entities << entry.build_entity(parent)
          if n + 1 < sliced_entries.count
            # recursive call
            fn.call(n + 1)
          else
            # batch insert
            results = entry.class.retry_on_exception? { CloudDatastore.dataset.save entities }
          end
          sliced_entries[n].fill_id_from_entity(results[n]) if results.present?
          results.present?
        end
      end
      fn.call(0)
      sliced_entries
    end.flatten
  end
end
