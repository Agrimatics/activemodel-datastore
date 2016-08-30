# ActiveModel Google Cloud Datastore example Rails app
Example Rails app using the Google::Cloud::Datastore. The rails app was generated with -O 
to skip ActiveRecord.

# Setup
Install the Google Cloud SDK.

    $ curl https://sdk.cloud.google.com | bash
    $ gcloud components install cloud-datastore-emulator 
    
You can check the version of the SDK and the components installed with:

    $ gcloud components list
    
Add the following line to your ~/.bash_profile for the new emulator which supports gRPC and 
Cloud Datastore API:
        
    export PATH="~/google-cloud-sdk/platform/cloud-datastore-emulator:$PATH"
        
Restart your shell:
        
    exec -l $SHELL    

To create the local development datastore execute the following from the root of the project:

    $ gcd.sh create tmp/local_datastore
    
To create the local automated test datastore execute the following from the root of the project:
    
    $ gcd.sh create tmp/test_datastore
    
Install the Ruby on Rails dependencies:

    $ bundle install
    
# Running Locally
To start the local GCD server:

    $ gcd.sh start --port=8180 tmp/local_datastore
    
To start the local web server:

    $ rails server

# Implementation
The Google::Cloud::Datastore::Dataset is implemented in config/initializers/cloud_datastore.rb.

The ActiveModel wrapper is implemented as a model concern, located in app/models/concerns.

# Tests
The active-model-cloud-datastore concern has tests, run them with rake test.

# TODO
Consider turning this into a gem?
