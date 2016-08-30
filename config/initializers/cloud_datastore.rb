# Returns a Google::Cloud::Datastore::Dataset object for the configured dataset.
#
# The dataset instance is used to create, read, update, and delete entity objects.
# GCLOUD_KEYFILE_JSON is an environment variable that Datastore checks for credentials.
#
# ENV['GCLOUD_KEYFILE_JSON'] = '{
#   "private_key": "-----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n",
#   "client_email": "web-app@libra-pro.iam.gserviceaccount.com"
# }'
#
module CloudDatastore
  if Rails.env.development?
    ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8180'
    ENV['GCLOUD_PROJECT'] = 'local-datastore'
  elsif Rails.env.test?
    ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
    ENV['GCLOUD_PROJECT'] = 'test-datastore'
  else
    ENV['GCLOUD_KEYFILE_JSON'] = '{"private_key": "' + ENV['SERVICE_ACCOUNT_PRIVATE_KEY'] + '",
      "client_email": "' + ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'] + '"}'
  end

  # The way that the gRPC library within google cloud initializes does not persist properly across
  # forks. If you load it eagerly, you load it and then fork, so the sub-processes don't have
  # correct initialization. But if you fork and then load it in each worker, everything
  # initializes correctly. Creates one Gcloud gRPC client instance shared across all threads.
  #
  def self.dataset
    @dataset ||= begin
      require 'google/cloud/datastore'
      Google::Cloud.datastore(ENV['GCLOUD_PROJECT'])
    end
  end

  def self.reset_dataset
    @dataset = nil
  end
end
