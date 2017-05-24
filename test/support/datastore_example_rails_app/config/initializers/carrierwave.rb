if Rails.env.development?
  # SERVICE_ACCOUNT = YAML.load_file(Rails.root.join('config', 'service_account.yml'))[Rails.env]
  #
  # CarrierWave.configure do |config|
  #   config.fog_provider = 'fog/google'
  #   config.fog_credentials = {
  #     provider:                'Google',
  #     google_project:          SERVICE_ACCOUNT['gcloud_project'],
  #     google_client_email:     SERVICE_ACCOUNT['client_email'],
  #     google_json_key_string:  '{"private_key": "' + SERVICE_ACCOUNT['private_key'] + '",
  #       "client_email": "' + SERVICE_ACCOUNT['client_email'] + '"}'
  #   }
  #   config.fog_directory = SERVICE_ACCOUNT['cloud_storage_bucket_name']
  #   config.fog_public = false
  #   config.fog_attributes = { 'Cache-Control' => 'max-age=31536000' } # one year
  # end
  CarrierWave.configure do |config|
    config.storage = :file
    config.root = Rails.root.join('tmp')
    config.cache_dir = 'carrierwave-cache'
  end

elsif Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :file
    config.enable_processing = false
    config.root = Rails.root.join('tmp')
    config.cache_dir = 'carrierwave-cache'
  end

elsif Rails.env.production?
  CarrierWave.configure do |config|
    config.fog_provider = 'fog/google'
    config.fog_credentials = {
      provider:                'Google',
      google_project:          ENV['GCLOUD_PROJECT'],
      google_client_email:     ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'],
      google_json_key_string:  '{"private_key": "' + ENV['SERVICE_ACCOUNT_PRIVATE_KEY'] + '",
        "client_email": "' + ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'] + '"}'
    }
    config.fog_directory  = ENV['CLOUD_STORAGE_BUCKET_NAME']
    config.asset_host     = "https://storage.googleapis.com/#{ENV['CLOUD_STORAGE_BUCKET_NAME']}"
    config.fog_public     = true
    config.fog_attributes = { cache_control: 'max-age=31536000' } # one year
    config.root = Rails.root.join('tmp')
    config.cache_dir = 'carrierwave-cache'
  end
end
