# ActiveModel Gcloud Datastore example Rails app
Example Rails app using the Google NoSQL Gcloud::Datastore. The rails app was generated with -O 
to skip ActiveRecord.

# Setup
Install the Google Cloud SDK.

    $ curl https://sdk.cloud.google.com | bash
    $ gcloud components install gcd-emulator
    
As of this release, the Datastore emulator that is part of the gcloud SDK is no longer 
compatible with gcloud-ruby. This is because the gcloud SDK’s Datastore emulator does 
not yet support gRPC as a transport layer.

A gRPC-compatible emulator is available until the gcloud SDK Datastore emulator supports gRPC. 
To use it you must download the [gRPC emulator]
(https://storage.googleapis.com/gcd/tools/gcd-grpc-1.0.0.zip)
and put it in ~/google-cloud-datastore-emulator.

Add the following line to your ~/.bash_profile:
        
    export PATH="~/google-cloud-datastore-emulator:$PATH"
        
Restart your shell:
        
    $ exec -l $SHELL   

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
The Gcloud::Datastore::Dataset is implemented in config/initializers/cloud_datastore.rb.

The ActiveModel wrapper is implemented as a model concern, located in app/models/concerns.

The database.yml contains the dataset_ids.

# Tests
The active-model-cloud-datastore concern has tests, run them with rake test.

# TODO
Consider turning this into a gem?
