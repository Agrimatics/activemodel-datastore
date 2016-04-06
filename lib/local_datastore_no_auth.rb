require 'gcloud/datastore'

if Rails.env.development? || Rails.env.test?
  module Gcloud
    module Datastore
      # Override the authentication credentials needed for the actual Google Cloud Datastore.
      class Credentials
        def initialize
          # pass
        end

        def sign_http_request(request)
          request
        end
      end
    end
  end
end
