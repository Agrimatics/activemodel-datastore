Active Model Datastore
===================================

Makes the [google-cloud-datastore](https://github.com/GoogleCloudPlatform/google-cloud-ruby/tree/master/google-cloud-datastore) gem compliant with [active_model](https://github.com/rails/rails/tree/master/activemodel) conventions and compatible with your Rails 5 applications. 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Why would you want to use Google's NoSQL [Cloud Datastore](https://cloud.google.com/datastore) 
with Rails? 

When you want a Rails app backed by a managed, massively-scalable datastore solution. Cloud Datastore 
automatically handles sharding and replication, providing you with a highly available and durable 
database that scales automatically to handle your applications' load.
 
## Table of contents
 
- [Setup](#setup)
- [Model Example](#model)
- [Controller Example](#controller)
- [Retrieving Entities](#queries)
- [Datastore Emulator](#emulator)
- [Example Rails App](#rails)
- [Nested Forms](#nested)
- [Datastore Gotchas](#gotchas)
- [Work In Progress](#wip)
 
## <a name="setup"></a>Setup
 
Generate your Rails app without ActiveRecord:
 
```bash
rails new my_app -O
```

You can remove the db/ directory as it won't be needed.

To install, add this line to your `Gemfile` and run `bundle install`:
 
```ruby
gem 'activemodel-datastore'
```
  
Create a Google Cloud account [here](https://cloud.google.com) and create a project.

Google Cloud requires the Project ID and Service Account Credentials to connect to the Datastore API.
 
*Follow the [activation instructions](https://cloud.google.com/datastore/docs/activate) to enable the 
Google Cloud Datastore API. You will create a service account with the role of editor and generate 
json credentials.*

Set your project id in an `ENV` variable named `GCLOUD_PROJECT`.

To locate your project ID:

1. Go to the Cloud Platform Console.
2. From the projects list, select the name of your project.
3. On the left, click Dashboard. The project name and ID are displayed in the Dashboard.

When running on Google Cloud Platform environments the Service Account credentials will be discovered automatically. 
When running on other environments (such as AWS or Heroku), the Service Account credentials need to be 
specified in two additional `ENV` variables named `SERVICE_ACCOUNT_CLIENT_EMAIL` and `SERVICE_ACCOUNT_PRIVATE_KEY`.
The values for these two `ENV` variables will be in the downloaded service account json file. 

```bash
SERVICE_ACCOUNT_PRIVATE_KEY = -----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n
SERVICE_ACCOUNT_CLIENT_EMAIL = web-app@app-name.iam.gserviceaccount.com
```

On Heroku the `ENV` variables can be set under 'Settings' -> 'Config Variables'.

Active Model Datastore will then handle the authentication for you, and the datastore instance can 
be accessed with `CloudDatastore.dataset`.

There is an example Puma config file [here](https://github.com/Agrimatics/activemodel-datastore/blob/master/test/support/datastore_example_rails_app/config/puma.rb).
 
## <a name="model"></a>Model Example
 
Let's start by implementing the model:

```ruby
class User
  include ActiveModel::Datastore

  attr_accessor :email, :name, :enabled, :state

  def entity_properties
    %w[email name enabled]
  end
end
```

Data objects in Cloud Datastore are known as entities. Entities are of a kind. An entity has one 
or more named properties, each of which can have one or more values. Think of them like this:
* 'Kind' (which is your table and the name of your Rails model)
* 'Entity' (which is the record from the table)
* 'Property' (which is the attribute of the record)

The `entity_properties` method defines an Array of properties that belong to the entity in cloud 
datastore. Define the attributes of your model using `attr_accessor`. With this approach, Rails 
deals solely with ActiveModel objects. The objects are converted to/from entities automatically 
during save/query operations. You can still use virtual attributes on the model (such as the 
`:state` attribute above) by simply excluding it from `entity_properties`. In this example state 
is available to the model but won't be persisted with the entity in datastore.

Validations work as you would expect:

```ruby
class User
  include ActiveModel::Datastore

  attr_accessor :email, :name, :enabled, :state

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }

  def entity_properties
    %w[email name enabled]
  end
end
```

Callbacks work as you would expect. We have also added the ability to set default values through 
[`default_property_value`](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore:default_property_value) 
and type cast the format of values through [`format_property_value`](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore:format_property_value):

```ruby
class User
  include ActiveModel::Datastore

  attr_accessor :email, :name, :enabled, :state

  before_validation :set_default_values
  after_validation :format_values
  before_save { puts '** something can happen before save **'}
  after_save { puts '** something can happen after save **'}

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }

  def entity_properties
    %w[email name enabled]
  end

  def set_default_values
    default_property_value :enabled, true
  end

  def format_values
    format_property_value :role, :integer
  end
end
```

## <a name="controller"></a>Controller Example

Now on to the controller! A scaffold generated controller works out of the box:

```ruby
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
```

## <a name="queries"></a>Retrieving Entities

####[all(options = {})](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:all)
Queries entities using the provided options. When a limit option is provided queries up to the limit 
and returns results with a cursor.
```ruby
users = User.all(options = {})

parent = CloudDatastore.dataset.key('Parent', 12345)
users = User.all(ancestor: parent)

users = User.all(ancestor: parent, where: ['name', '=', 'Bryce'])

users = User.all(where: [['name', '=', 'Ian'], ['enabled', '=', true]])

users, cursor = User.all(limit: 7)

# @param [Hash] options The options to construct the query with.
#
# @option options [Google::Cloud::Datastore::Key] :ancestor Filter for inherited results.
# @option options [String] :cursor Sets the cursor to start the results at.
# @option options [Integer] :limit Sets a limit to the number of results to be returned.
# @option options [String] :order Sort the results by property name.
# @option options [String] :desc_order Sort the results by descending property name.
# @option options [Array] :select Retrieve only select properties from the matched entities.
# @option options [Array] :where Adds a property filter of arrays in the format[name, operator, value].
```

####[find(*ids, parent: nil)](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:find)
Find entity by id - this can either be a specific id (1), a list of ids (1, 5, 6), or an array of ids ([5, 6, 10]). 
The parent key is optional.
```ruby
user = User.find(1)

parent = CloudDatastore.dataset.key('Parent', 12345)
user = User.find(1, parent: parent)

users = User.find(1, 2, 3)
```

####[find_by(args)](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:find_by)
Finds the first entity matching the specified condition.
```ruby
user = User.find_by(name: 'Joe')

user = User.find_by(name: 'Bryce', ancestor: parent)
```

Cloud Datastore has excellent documentation on how [Datastore Queries](https://cloud.google.com/datastore/docs/concepts/queries#datastore-basic-query-ruby) 
work, and pay special attention to the the [restrictions](https://cloud.google.com/datastore/docs/concepts/queries#restrictions_on_queries).

## <a name="emulator"></a>Datastore Emulator

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

To start the local Cloud Datastore emulator:

    $ cloud_datastore_emulator start --port=8180 tmp/local_datastore
    
## <a name="rails"></a>Example Rails App

There is an example Rails 5 app in the test directory [here](https://github.com/Agrimatics/activemodel-datastore/tree/master/test/support/datastore_example_rails_app).

 ```bash
 $ bundle
 $ cloud_datastore_emulator create tmp/local_datastore
 $ cloud_datastore_emulator create tmp/test_datastore
 $ ./start-local-datastore.sh
 $ rails s
 ```
 
 Navigate to http://localhost:3000.

## <a name="nested"></a>Nested Forms

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

Let's say we have a parent Recipe with Ingredient children.

Start by defining within the Recipe model:
* an attr_accessor of `:ingredients`
* a writer method named `ingredients_attributes=`
* the `validates_associated` method can be used to validate the nested objects

Example:

```ruby
class Recipe
  attr_accessor :ingredients
  validates :ingredients, presence: true
  validates_associated :ingredients

  def ingredients_attributes=(attributes)
    assign_nested_attributes(:ingredients, attributes)
  end
end
```

You may also set a `:reject_if` proc to silently ignore any new record hashes if they fail to
pass your criteria. For example:

```ruby
class Recipe
 def ingredients_attributes=(attributes)
   reject_proc = proc { |attributes| attributes['name'].blank? }
   assign_nested_attributes(:ingredients, attributes, reject_if: reject_proc)
 end
end
```

 Alternatively,`:reject_if` also accepts a symbol for using methods:

```ruby
class Recipe
  def ingredients_attributes=(attributes)
    reject_proc = proc { |attributes| attributes['name'].blank? }
    assign_nested_attributes(:ingredients, attributes, reject_if: reject_recipes)
  end

  def reject_recipes(attributes)
    attributes['name'].blank?
  end
end
```

Within the parent model `valid?` will validate the parent and associated children and
`nested_models` will return the child objects. If the nested form submitted params contained
a truthy `_destroy` key, the appropriate nested_models will have `marked_for_destruction` set
to True.

## <a name="gotchas"></a>Datastore Gotchas
#### Ordering of query results is undefined when no sort order is specified.
When a query does not specify a sort order, the results are returned in the order they are retrieved. 
As Cloud Datastore implementation evolves (or if a project's indexes change), this order may change. 
Therefore, if your application requires its query results in a particular order, be sure to specify 
that sort order explicitly in the query.

## <a name="wip"></a>Work In Progress

TODO: document datastore eventual consistency and mitigation using ancestor queries and entity groups.

TODO: document indexes.

TODO: document using the datastore emulator to generate the index.yaml.

TODO: document the change tracking implementation.