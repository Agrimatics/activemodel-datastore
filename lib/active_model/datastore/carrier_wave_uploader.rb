module CarrierWaveUploader
  include CarrierWave::Mount

  private

  def mount_base(column, uploader = nil, options = {}, &block)
    super

    # include CarrierWave::Validations::ActiveModel
    #
    # validates_integrity_of column if uploader_option(column.to_sym, :validate_integrity)
    # validates_processing_of column if uploader_option(column.to_sym, :validate_processing)
    # validates_download_of column if uploader_option(column.to_sym, :validate_download)

    after_save :"store_#{column}!"
    after_update :"store_#{column}!"
    after_destroy :"remove_#{column}!"

    class_eval <<-RUBY, __FILE__, __LINE__ + 1
      ##
      # Override for setting the file urls on the entity.
      #
      def build_entity(parent = nil)
        entity = super(parent)
        self.class.uploaders.keys.each do |col|
          entity[col.to_s] = send("get_" + col.to_s + "_identifiers")
        end
        entity
      end

      ##
      # Override to append file names for mount_uploaders.
      # Works with multiple files stored as an Array.
      #
      def update(params)
        existing_files = {}
        self.class.uploaders.keys.each do |attr_name|
           existing_files[attr_name] = uploader_file_names(attr_name) if send(attr_name).is_a? Array
        end
        assign_attributes(params)
        return unless valid?
        run_callbacks :update do
          entity = build_entity
          self.class.uploaders.keys.each do |attr_name|
            entity[attr_name] = append_files(entity[attr_name], existing_files[attr_name])
          end
          self.class.retry_on_exception? { CloudDatastore.dataset.save entity }
        end
      end

      ##
      # For new entities, set the identifiers (file names).
      # For deleted entities, set the identifier (which will be nil).
      # For updated entities, set the identifiers if they have changed. The
      # identifier will be nil if files were not uploaded during the update.
      #
      def get_#{column}_identifiers
        identifier = write_#{column}_identifier
        if persisted? && !remove_#{column}? && identifier.nil?
          if defined?(#{column}_identifier) && #{column}_identifier.present?
           #{column}_identifier if defined?(#{column}_identifier) && #{column}_identifier.present?
          elsif defined?(#{column}_identifiers) && #{column}_identifiers.present?
            #{column}_identifiers
          end
        else
          identifier
        end
      end

      ##
      # Called by CarrierWave::Mount.mount_uploaders -> write_#{column}_identifier.
      #
      def write_uploader(column, identifier)
        identifier
      end

      ##
      # This gets called whenever the uploaders instance variable is nil.
      # It returns the uploader identifiers (file names) for the desired column.
      #
      def read_uploader(column)
        if entity_property_values.present? && entity_property_values.key?(column.to_s)
          entity_property_values[column.to_s]
        end
      end

      ##
      # Reset cached mounter on record reload.
      #
      def reload!
        @_mounters = nil
        super
      end

      ##
      # Reset cached mounter on record dup.
      #
      def initialize_dup(other)
        @_mounters = nil
        super
      end

      # private

      def uploader_file_names(attr_name)
        send(attr_name).map { |x| x.file.filename }
      end

      def append_files(files, new_files)
        if files.is_a?(Array) && !new_files.nil?
          files = files.push(*new_files).flatten.compact.uniq
        end
        files
      end
    RUBY
  end
end
