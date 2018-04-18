##
# Batch operations
#
#
# Such batch calls are faster than making separate calls for each individual entity because they incur the overhead
# for only one service call.
#
# reference: https://cloud.google.com/datastore/docs/concepts/entities#batch_operations
#
# group = Group.find(params[:group_id])
# users = %w{ alice bob charlie }.map{ |name| User.new(name: name) }
# saved_users = ActiveModel::Datastore.save_all(users, parent: group)
#
module ActiveModel::Datastore
  def self.save_all(entries, parent: nil)
    invalid_entries = entries.reject{|entry| entry.valid?}
    return if invalid_entries.present?
    results = []
    entries.each_slice(500) do |sliced_entries|
      entities_to_save = []
      saved_entities = nil
      fn = lambda do |n|
        entry = sliced_entries[n]
        entry.run_callbacks(:save) do
          entities_to_save << entry.build_entity(parent)
          if n + 1 < sliced_entries.count
            # recursive call
            fn.call(n + 1)
          else
            # batch insert
            saved_entities = entry.class.retry_on_exception? { CloudDatastore.dataset.save entities_to_save }
          end
          sliced_entries[n].id = saved_entities[n].key.id if saved_entities
          sliced_entries[n].parent_key_id = saved_entities[n].key.parent.id if saved_entities && saved_entities[n].key.parent.present?
          results << sliced_entries if n == 0 && saved_entities
          saved_entities.present?
        end
      end
      fn.call(0)
    end
    results.flatten
  end
end
