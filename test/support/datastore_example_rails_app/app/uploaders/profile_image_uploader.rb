class ProfileImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  storage :fog if Rails.env.production?

  # Override the directory where uploaded files will be stored.
  # This is a sensible default for uploaders that are meant to be mounted:
  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  def default_url(*)
    ActionController::Base.helpers.asset_path([version_name, 'fallback_user.png'].compact.join('_'))
  end

  # Override as we don't want the files deleted from Cloud Storage.
  def remove!
    return unless model.respond_to?(:keep_file) && model.keep_file
    super
  end

  # Process files as they are uploaded:
  # Resize the image to fit within the specified dimensions while retaining the original aspect
  # ratio. The image may be shorter or narrower than specified in the smaller dimension but will
  # not be larger than the specified values.
  process resize_to_fit: [300, 200]

  def extension_whitelist
    %w[jpg jpeg gif png]
  end
end
