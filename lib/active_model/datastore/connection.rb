##
# Returns a Google::Cloud::Datastore::Dataset object for the configured dataset.
#
# The dataset instance is used to create, read, update, and delete entity objects.
#
# GCLOUD_PROJECT is an environment variable representing the Datastore project ID.
# DATASTORE_KEYFILE_JSON is an environment variable that Datastore checks for credentials.
#
# ENV['GCLOUD_KEYFILE_JSON'] = '{
#   "private_key": "-----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n",
#   "client_email": "web-app@app-name.iam.gserviceaccount.com"
# }'
#
module CloudDatastore
  if defined?(Rails) == 'constant'
    if Rails.env.development?
      ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8180'
      ENV['GCLOUD_PROJECT'] = 'local-datastore'
    elsif Rails.env.test?
      ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
      ENV['GCLOUD_PROJECT'] = 'test-datastore'
    elsif ENV['SERVICE_ACCOUNT_PRIVATE_KEY'].present? &&
          ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'].present?
      ENV['GCLOUD_KEYFILE_JSON'] = '{"private_key": "' + ENV['SERVICE_ACCOUNT_PRIVATE_KEY'] + '",
      "client_email": "' + ENV['SERVICE_ACCOUNT_CLIENT_EMAIL'] + '"}'
    end
  else
    ENV['DATASTORE_EMULATOR_HOST'] = 'localhost:8181'
    ENV['GCLOUD_PROJECT'] = 'test-datastore'
  end

  def self.dataset
    @dataset ||= Google::Cloud.datastore(ENV['GCLOUD_PROJECT'])
  end

  def self.reset_dataset
    @dataset = nil
  end
end
