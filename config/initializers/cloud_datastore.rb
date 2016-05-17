require 'gcloud/datastore'

# Returns a Gcloud::Datastore::Dataset object for the configured dataset.
# The dataset instance is used to create, read, update, and delete entity objects.
# GCLOUD_KEYFILE_JSON is an environment variable that Datastore checks for credentials.
# ENV['GCLOUD_KEYFILE_JSON'] = '{
#   "private_key": "-----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n",
#   "client_email": "web-app@libra-pro.iam.gserviceaccount.com"
# }'
module CloudDatastore
  if Rails.env.development?
    ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8180'
  elsif Rails.env.test?
    ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
  else
    ENV['GCLOUD_KEYFILE_JSON'] = '{"private_key": "' + ENV['SERVICE_ACCOUNT_PRIVATE_KEY'] + '",
      "client_email": "' + ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'] + '"}'
  end

  def self.dataset
    config = Rails.application.config.database_configuration[Rails.env]['dataset_id']
    @dataset ||= Gcloud.datastore(config)
  end

  def self.reset_dataset
    @dataset = nil
  end
end
