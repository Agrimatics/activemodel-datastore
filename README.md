Active Model Google Cloud Datastore
===================================

Makes [google-cloud-datastore](https://github.com/GoogleCloudPlatform/google-cloud-ruby/tree/master/google-cloud-datastore) compliant with [active_model](https://github.com/rails/rails/tree/master/activemodel) conventions and compatible with your Rails 5 applications. 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

 Why would you want to use Google's NoSQL [Cloud Datastore](https://cloud.google.com/datastore) 
 with Rails? When you want a Rails app backed by a managed, massively-scalable datastore solution. 
 First, generate a Rails app with -O to skip ActiveRecord.
 
 Let's start by implementing the model:

    class User
      include ActiveModelCloudDatastore

      attr_accessor :email, :name, :enabled, :state

      before_validation :set_default_values
      before_save { puts '** something can happen before save **'}
      after_save { puts '** something can happen after save **'}

      validates :email, presence: true, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
      validates :name, presence: true, length: { maximum: 30 }

      def entity_properties
        %w(email name enabled)
      end

      def set_default_values
        default_property_value :enabled, true
      end

      def format_values
        format_property_value :role, :integer
      end
    end

Using `attr_accessor` the attributes of the model are defined. Validations and Callbacks all work 
as you would expect. However, `entity_properties` is new. Data objects in Google Cloud Datastore
are known as entities. Entities are of a kind. An entity has one or more named properties, each
of which can have one or more values. Think of them like this:
* 'Kind' (which is your table)
* 'Entity' (which is the record from the table)
* 'Property' (which is the attribute of the record)
The `entity_properties` method defines an Array of the properties that belong to the entity in
cloud datastore. With this approach, Rails deals solely with ActiveModel objects. The objects are
converted to/from entities as needed during save/query operations.

We have also added the ability to set default property values and typecast the format of values
for entities.

Now on to the controller! A scaffold generated controller works out of the box:

    class UsersController < ApplicationController
      before_action :set_user, only: [:show, :edit, :update, :destroy]

      def index
        @users = User.all
      end

      def show
      end

      def new
        @user = User.new
      end

      def edit
      end

      def create
        @user = User.new(user_params)
        respond_to do |format|
          if @user.save
            format.html { redirect_to @user, notice: 'User was successfully created.' }
          else
            format.html { render :new }
          end
        end
      end

      def update
        respond_to do |format|
          if @user.update(user_params)
            format.html { redirect_to @user, notice: 'User was successfully updated.' }
          else
            format.html { render :edit }
          end
        end
      end

      def destroy
        @user.destroy
        respond_to do |format|
          format.html { redirect_to users_url, notice: 'User was successfully destroyed.' }
        end
      end

      private

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:email, :name)
      end
    end

TODO: describe eventual consistency with ancestor queries and entity groups.

TODO: describe the available query options.

TODO: describe indexes.

TODO: describe the change tracking implementation.

Cloud Datastore Active Model Nested Attributes
----------------------------------------------

Adds support for nested attributes to ActiveModel. Heavily inspired by 
Rails ActiveRecord::NestedAttributes.

Nested attributes allow you to save attributes on associated records along with the parent.
It's used in conjunction with fields_for to build the nested form elements.

See Rails ActionView::Helpers::FormHelper::fields_for for more info.

*NOTE*: Unlike ActiveRecord, the way that the relationship is modeled between the parent and
child is not enforced. With NoSQL the relationship could be defined by any attribute, or with
denormalization exist within the same entity. This library provides a way for the objects to
be associated yet saved to the datastore in any way that you choose.

You enable nested attributes by defining an `:attr_accessor` on the parent with the pluralized 
name of the child model.

Nesting also requires that a `<association_name>_attributes=` writer method is defined in your
parent model. If an object with an association is instantiated with a params hash, and that
hash has a key for the association, Rails will call the `<association_name>_attributes=`
method on that object. Within the writer method call `assign_nested_attributes`, passing in
the association name and attributes.

Let's say we have a parent Recipe with RecipeContent children.

Start by defining within the Recipe model:
* an attr_accessor of `:recipe_contents`
* a writer method named `recipe_contents_attributes=`
* the `validates_associated` method can be used to validate the nested objects

Example:

    class Recipe
      attr_accessor :recipe_contents
      validates :recipe_contents, presence: true
      validates_associated :recipe_contents

      def recipe_contents_attributes=(attributes)
        assign_nested_attributes(:recipe_contents, attributes)
      end
    end

You may also set a `:reject_if` proc to silently ignore any new record hashes if they fail to
pass your criteria. For example:

   class Recipe
     def recipe_contents_attributes=(attributes)
       reject_proc = proc { |attributes| attributes['name'].blank? }
       assign_nested_attributes(:recipe_contents, attributes, reject_if: reject_proc)
     end
   end

 Alternatively,`:reject_if` also accepts a symbol for using methods:

    class Recipe
      def recipe_contents_attributes=(attributes)
        reject_proc = proc { |attributes| attributes['name'].blank? }
        assign_nested_attributes(:recipe_contents, attributes, reject_if: reject_recipes)
      end

      def reject_recipes(attributes)
        attributes['name'].blank?
      end
    end

Within the parent model `valid?` will validate the parent and associated children and
`nested_models` will return the child objects. If the nested form submitted params contained
a truthy `_destroy` key, the appropriate nested_models will have `marked_for_destruction` set
to True.

Development Environment
-----------------------

Install the Google Cloud SDK.

    $ curl https://sdk.cloud.google.com | bash
    
You can check the version of the SDK and the components installed with:

    $ gcloud components list
    
Install the Cloud Datastore Emulator, which provides local emulation of the production Cloud 
Datastore environment and the gRPC API. However, you'll need to do a small amount of configuration 
before running the application against the emulator, see [here.](https://cloud.google.com/datastore/docs/tools/datastore-emulator)
    
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

    $ ./start-local-datastore.sh
    
To start the local web server:

    $ rails server

Implementation
--------------

The Google::Cloud::Datastore::Dataset is implemented in config/initializers/cloud_datastore.rb.

The Active Model interface layer is implemented as a model concern, located in app/models/concerns.

Tests
-----

The active-model-cloud-datastore concern has tests, run them with rake test.