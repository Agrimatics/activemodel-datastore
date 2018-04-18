Active Model Datastore
===================================

Makes the [google-cloud-datastore](https://github.com/GoogleCloudPlatform/google-cloud-ruby/tree/master/google-cloud-datastore) gem compliant with [active_model](https://github.com/rails/rails/tree/master/activemodel) conventions and compatible with your Rails 5 applications. 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Why would you want to use Google's NoSQL [Cloud Datastore](https://cloud.google.com/datastore) 
with Rails? 

When you want a Rails app backed by a managed, massively-scalable datastore solution. Cloud Datastore 
automatically handles sharding and replication. It is a highly available and durable database that 
automatically scales to handle your applications' load. Cloud Datastore is a schemaless database 
suited for unstructured or semi-structured application data.

[![Gem Version](https://badge.fury.io/rb/activemodel-datastore.svg)](https://badge.fury.io/rb/activemodel-datastore)
[![Build Status](https://travis-ci.org/Agrimatics/activemodel-datastore.svg?branch=master)](https://travis-ci.org/Agrimatics/activemodel-datastore)
 
## Table of contents
 
- [Setup](#setup)
- [Model Example](#model)
- [Controller Example](#controller)
- [Retrieving Entities](#queries)
- [Datastore Consistency](#consistency)
- [Datastore Indexes](#indexes)
- [Datastore Emulator](#emulator)
- [Example Rails App](#rails)
- [CarrierWave File Uploads](#carrierwave)
- [Track Changes](#track_changes)
- [Nested Forms](#nested)
- [Datastore Gotchas](#gotchas)
 
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
Google Cloud Datastore API. When running on Google Cloud Platform environments the Service Account 
credentials will be discovered automatically. When running on other environments (such as AWS or Heroku)
you need to create a service account with the role of editor and generate json credentials.*

Set your project id in an `ENV` variable named `GCLOUD_PROJECT`.

To locate your project ID:

1. Go to the Cloud Platform Console.
2. From the projects list, select the name of your project.
3. On the left, click Dashboard. The project name and ID are displayed in the Dashboard.

If you have an external application running on a platform outside of Google Cloud you also need to 
provide the Service Account credentials. They are specified in two additional `ENV` variables named 
`SERVICE_ACCOUNT_CLIENT_EMAIL` and `SERVICE_ACCOUNT_PRIVATE_KEY`. The values for these two `ENV` 
variables will be in the downloaded service account json credentials file.

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

  attr_accessor :email, :enabled, :name, :role, :state

  def entity_properties
    %w[email enabled name role]
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

  attr_accessor :email, :enabled, :name, :role, :state

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }

  def entity_properties
    %w[email enabled name role]
  end
end
```

Callbacks work as you would expect. We have also added the ability to set default values through 
[`default_property_value`](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel/Datastore/PropertyValues#default_property_value-instance_method) 
and type cast the format of values through [`format_property_value`](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel/Datastore/PropertyValues#format_property_value-instance_method):

```ruby
class User
  include ActiveModel::Datastore

  attr_accessor :email, :enabled, :name, :role, :state

  before_validation :set_default_values
  after_validation :format_values
  
  before_save { puts '** something can happen before save **'}
  after_save { puts '** something can happen after save **'}

  validates :email, format: { with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i }
  validates :name, presence: true, length: { maximum: 30 }
  validates :role, presence: true

  def entity_properties
    %w[email enabled name role]
  end

  def set_default_values
    default_property_value :enabled, true
    default_property_value :role, 1
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

Each entity in Cloud Datastore has a key that uniquely identifies it. The key consists of the 
following components:

* the kind of the entity, which is User in these examples
* an identifier for the individual entity, which can be either a a key name string or an integer numeric ID
* an optional ancestor path locating the entity within the Cloud Datastore hierarchy

#### [all(options = {})](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:all)
Queries entities using the provided options. When a limit option is provided queries up to the limit 
and returns results with a cursor.
```ruby
users = User.all(options = {})

parent_key = CloudDatastore.dataset.key('Parent', 12345)
users = User.all(ancestor: parent_key)

users = User.all(ancestor: parent_key, where: ['name', '=', 'Bryce'])

users = User.all(where: [['name', '=', 'Ian'], ['enabled', '=', true]])

users = User.all(sort: {name: :asc, created_at: :desc})

users, cursor = User.all(limit: 7)

# @param [Hash] options The options to construct the query with.
#
# @option options [Google::Cloud::Datastore::Key] :ancestor Filter for inherited results.
# @option options [String] :cursor Sets the cursor to start the results at.
# @option options [Integer] :limit Sets a limit to the number of results to be returned.
# @option options [Array, Hash] :sort Sort the results in one of these formats
#   [:name, :asc]
#   [ [:name, :asc], [:created_at, :desc] ]
#   { name: :asc, created_at: :desc }
#   { name: 1, created_at: -1 }
# @option options [String] :order Sort the results by property name. (deprecated)
# @option options [String] :desc_order Sort the results by descending property name. (deprecated)
# @option options [Array] :select Retrieve only select properties from the matched entities.
# @option options [Array] :where Adds a property filter of arrays in the format[name, operator, value].
```

#### [find(*ids, parent: nil)](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:find)
Find entity by id - this can either be a specific id (1), a list of ids (1, 5, 6), or an array of ids ([5, 6, 10]). 
The parent key is optional. This method is a lookup by key and results will be strongly consistent.
```ruby
user = User.find(1)

parent_key = CloudDatastore.dataset.key('Parent', 12345)
user = User.find(1, parent: parent_key)

users = User.find(1, 2, 3)
```

#### [find_by(args)](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:find_by)
Queries for the first entity matching the specified condition.
```ruby
user = User.find_by(name: 'Joe')

user = User.find_by(name: 'Bryce', ancestor: parent_key)
```

Cloud Datastore has documentation on how [Datastore Queries](https://cloud.google.com/datastore/docs/concepts/queries#datastore-basic-query-ruby) 
work, and pay special attention to the the [restrictions](https://cloud.google.com/datastore/docs/concepts/queries#restrictions_on_queries).

## <a name="consistency"></a>Datastore Consistency

Cloud Datastore is a non-relational databases, or NoSQL database. It distributes data over many 
machines and uses synchronous replication over a wide geographic area. Because of this architecture 
it offers a balance of strong and eventual consistency.

What is eventual consistency?

It means that an updated entity value may not be immediately visible when executing a query. 
Eventual consistency is a theoretical guarantee that, provided no new updates to an entity are made, 
all reads of the entity will eventually return the last updated value.

In the context of a Rails app, there are times that eventual consistency is not ideal. For example,
let's say you create a user entity with a key that looks like this:

`@key=#<Google::Cloud::Datastore::Key @kind="User", @id=1>`

and then immediately redirect to the index view of users. There is a good chance that your new user 
is not yet visible in the list. If you perform a refresh on the index view a second or two later 
the user will appear.

"Wait a minute!" you say. "This is crap!" you say. Fear not! We can make the query of users strongly
consistent. We just need to use entity groups and ancestor queries. An entity group is a hierarchy 
formed by a root entity and its children. To create an entity group, you specify an ancestor path 
for the entity which is a parent key as part of the child key.

Before using the `save` method, assign the `parent_key_id` attribute an ID. Let's say that 12345 
represents the ID of the company that the users belong to. The key of the user entity will now 
look like this:

`@key=#<Google::Cloud::Datastore::Key @kind="User", @id=1, @parent=#<Google::Cloud::Datastore::Key @kind="ParentUser", @id=12345>>`

All of the User entities will now belong to an entity group named ParentUser and can be queried by the 
Company ID. When we query for the users we will provide User.parent_key(12345) as the ancestor option.
 
*Ancestor queries are always strongly consistent.*

However, there is a small downside. Entities with the same ancestor are limited to 1 write per second.
Also, the entity group relationship cannot be changed after creating the entity (as you can't modify 
an entity's key after it has been saved).

The Users controller would now look like this:

```ruby
class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  def index
    @users = User.all(ancestor: User.parent_key(12345))
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
    @user.parent_key_id = 12345
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
    @user = User.find(params[:id], parent: User.parent_key(12345))
  end

  def user_params
    params.require(:user).permit(:email, :name)
  end
end
```

See here for the Cloud Datastore documentation on [Data Consistency](https://cloud.google.com/datastore/docs/concepts/structuring_for_strong_consistency).

## <a name="indexes"></a>Datastore Indexes

Every cloud datastore query requires an index. Yes, you read that correctly. Every single one. The 
indexes contain entity keys in a sequence specified by the index's properties and, optionally, 
the entity's ancestors.

There are two types of indexes, *built-in* and *composite*.

#### Built-in
By default, Cloud Datastore automatically predefines an index for each property of each entity kind. 
These single property indexes are suitable for simple types of queries. These indexes are free and
do not count against your index limit.

#### Composite
Composite index multiple property values per indexed entity. Composite indexes support complex 
queries and are defined in an index.yaml file.

Composite indexes are required for queries of the following form:

* queries with ancestor and inequality filters
* queries with one or more inequality filters on a property and one or more equality filters on other properties
* queries with a sort order on keys in descending order
* queries with multiple sort orders
* queries with one or more filters and one or more sort orders

*NOTE*: Inequality filters are LESS_THAN, LESS_THAN_OR_EQUAL, GREATER_THAN, GREATER_THAN_OR_EQUAL.

Google has excellent doc regarding datastore indexes [here](https://cloud.google.com/datastore/docs/concepts/indexes).

The datastore emulator generates composite indexes in an index.yaml file automatically. The file
can be found in /tmp/local_datastore/WEB-INF/index.yaml. If your localhost Rails app exercises every 
possible query the application will issue, using every combination of filter and sort order, the 
generated entries will represent your complete set of indexes.

One thing to note is that the datastore emulator caches indexes. As you add and modify application 
code you might find that the local datastore index.yaml contains indexes that are no longer needed. 
In this scenario try deleting the index.yaml and restarting the emulator. Navigate through your Rails
app and the index.yaml will be built from scratch.

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
 
## <a name="carrierwave"></a>CarrierWave File Uploads

Active Model Datastore has built in support for [CarrierWave](https://github.com/carrierwaveuploader/carrierwave) 
which is a simple and extremely flexible way to upload files from Rails applications. You can use 
different stores, including filesystem and cloud storage such as Google Cloud Storage or AWS.

Simply require `active_model/datastore/carrier_wave_uploader` and extend your model with the 
CarrierWaveUploader (after including ActiveModel::Datastore). Follow the CarrierWave 
[instructions](https://github.com/carrierwaveuploader/carrierwave#getting-started) for generating 
an uploader.

In this example it will be something like:

`rails generate uploader ProfileImage`

Define an attribute on the model for your file(s). You can then mount the uploaders using 
`mount_uploader` (single file) or `mount_uploaders` (array of files). Don't forget to add the new
attribute to `entity_properties` and whitelist the attribute in the controller if using strong 
parameters.

```ruby
require 'active_model/datastore/carrier_wave_uploader'

class User
  include ActiveModel::Datastore
  extend CarrierWaveUploader

  attr_accessor :email, :enabled, :name, :profile_image, :role
  
  mount_uploader :profile_image, ProfileImageUploader

  def entity_properties
    %w[email enabled name profile_image role]
  end
end
```

You will want to add something like this to your Rails form:

`<%= form.file_field :profile_image %>`

## <a name="track_changes"></a>Track Changes

TODO: document the change tracking implementation.

## <a name="nested"></a>Nested Forms

Adds support for nested attributes to ActiveModel. Heavily inspired by 
Rails ActiveRecord::NestedAttributes.

Nested attributes allow you to save attributes on associated records along with the parent.
It's used in conjunction with fields_for to build the nested form elements.

See Rails [ActionView::Helpers::FormHelper::fields_for](http://api.rubyonrails.org/classes/ActionView/Helpers/FormHelper.html#method-i-fields_for) for more info.

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
