# ActiveModel Gcloud Datastore example Rails app
Example Rails app using the Google NoSQL Gcloud::Datastore. The rails app was generated with -O 
to skip ActiveRecord.

# Setup
Install the Google Cloud SDK.

    $ curl https://sdk.cloud.google.com | bash
    $ gcloud components install gcd-emulator
    
Add the following line to your ~/.bash_profile:
        
    export PATH="~/google-cloud-sdk/platform/gcd:$PATH"
        
Restart your shell:
        
    $ exec -l $SHELL   

To create the local development datastore execute the following from the root of the project:

    $ gcd.sh create --project_id=local-datastore tmp/local_datastore
    
To create the local automated test datastore execute the following from the root of the project:
    
    $ gcd.sh create --project_id=test-datastore tmp/test_datastore
    
Install the Ruby on Rails dependencies:

    $ bundle install
    
# Running Locally
To start the local GCD server:

    $ gcd.sh start --port=8180 tmp/local_datastore
    
To start the local web server:

    $ rails server

# Implementation
The Gcloud::Datastore::Dataset is implemented in config/initializers/cloud_datastore.rb.
The local environment variables are implemented in config/initializers/development.rb.
The ActiveModel wrapper is implemented as a model concern, located in app/models/concerns.
The database.yml contains the dataset_ids.
The local datastore credentials monkey patch is in lib/local_datastore_no_auth.rb.

# Tests
The active-model-cloud-datastore concern has tests, run them with rake test.

# TODO
Consider turning this into a gem?
