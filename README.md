Active Model Google Cloud Datastore
===================================

An example Rails app using [Active Model](https://github.com/rails/rails/tree/master/activemodel) and 
the [Google Cloud client library for Ruby](https://github.com/GoogleCloudPlatform/google-cloud-ruby) with 
the highly-scalable NoSQL database [Cloud Datastore.](https://cloud.google.com/datastore) The rails app was generated with -O to skip ActiveRecord and is configured to run on Heroku.

Development Environment
-----------------------

Install the Google Cloud SDK.

    $ curl https://sdk.cloud.google.com | bash
    
You can check the version of the SDK and the components installed with:

    $ gcloud components list
    
Install the Cloud Datastore Emulator, which provides local emulation of the production Cloud 
Datastore environment and the gRPC API. However, you'll need to do a small amount of configuration 
before running the application against the emulator, see[here.](https://cloud.google.com/datastore/docs/tools/datastore-emulator)
    
    $ gcloud components install cloud-datastore-emulator 
    
Add the following line to your ~/.bash_profile:
        
    export PATH="~/google-cloud-sdk/platform/cloud-datastore-emulator:$PATH"
        
Restart your shell:
        
    exec -l $SHELL    

To create the local development datastore execute the following from the root of the project:

    $ cloud_datastore_emulator create tmp/local_datastore
    
To create the local test datastore execute the following from the root of the project:
    
    $ cloud_datastore_emulator create tmp/test_datastore
    
Install the Ruby on Rails dependencies:

    $ bundle install
    
Running Locally
---------------

To start the local GCD server:

    $ cloud_datastore_emulator start --port=8180 tmp/local_datastore
    
To start the local web server:

    $ rails server

Implementation
--------------

The Google::Cloud::Datastore::Dataset is implemented in config/initializers/cloud_datastore.rb.

The Active Model interface layer is implemented as a model concern, located in app/models/concerns.

Tests
-----

The active-model-cloud-datastore concern has tests, run them with rake test.

TODO
----

Release this is a gem.
