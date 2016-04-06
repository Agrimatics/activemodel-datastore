require 'gcloud/datastore'

# Returns a Gcloud::Datastore::Dataset object for the configured dataset.
# The dataset instance is used to create, read, update, and delete entity objects.
# GCLOUD_KEYFILE_JSON is an environment variable that Datastore checks for credentials.
# ENV['GCLOUD_KEYFILE_JSON'] = '{
#   "private_key": "-----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n",
#   "client_email": "web-app@libra-pro.iam.gserviceaccount.com"
# }'
module CloudDatastore
  def self.dataset
    config = Rails.application.config.database_configuration[Rails.env]['dataset_id']
    if Rails.env.development? or Rails.env.test?
      require 'local_datastore_no_auth'
      @dataset ||= Gcloud::Datastore::Dataset.new(config, Gcloud::Datastore::Credentials.new)
    else
      ENV['GCLOUD_KEYFILE_JSON'] = '{"private_key": "' + ENV['SERVICE_ACCOUNT_PRIVATE_KEY'] + '",
        "client_email": "' + ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'] + '"}'
      @dataset ||= Gcloud.datastore config
    end
  end

  def self.reset_dataset
    @dataset = nil
  end
end
