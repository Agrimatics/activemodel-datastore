Active Model Datastore
===================================

Makes the [google-cloud-datastore](https://cloud.google.com/ruby/docs/reference/google-cloud-datastore/latest)
gem compliant with [active_model](https://github.com/rails/rails/tree/master/activemodel)
conventions and compatible with your Rails 5+ applications.

Why would you want to use Google's NoSQL
[Firestore in Datastore mode](https://cloud.google.com/datastore) with Rails?

Use it when you want a Rails app backed by a fully managed, massively scalable NoSQL database,
without provisioning database servers or manually sharding data. Datastore stores records as
entities with flexible properties, so your models do not require a fixed database schema. It
automatically handles scaling and replication, provides highly available and durable storage, and
supports indexed queries and ACID transactions.

[![Gem Version](https://badge.fury.io/rb/activemodel-datastore.svg)](https://badge.fury.io/rb/activemodel-datastore)
 
## Table of contents
 
- [Setup](#setup)
- [Model Example](#model)
- [Controller Example](#controller)
- [Retrieving Entities](#queries)
- [Datastore Consistency and Concurrency](#consistency)
- [Datastore Indexes](#indexes)
- [Firestore Emulator](#emulator)
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

Follow the [activation instructions](https://cloud.google.com/datastore/docs/activate) to create a
Firestore in Datastore mode database for the project.

The Google Cloud client libraries use Application Default Credentials (ADC). On Google Cloud,
credentials are discovered automatically from the service account attached to the application. Grant
that service account only the access it needs; `roles/datastore.user` provides read/write access to
Datastore data.

Set your project id in an `ENV` variable named `GCLOUD_PROJECT`.

To locate your project ID:

1. Go to the Cloud Platform Console.
2. From the projects list, select the name of your project.
3. On the left, click Dashboard. The project name and ID are displayed in the Dashboard.

For applications outside Google Cloud, configure ADC for the hosting environment. If a service account
key is required, the Ruby client supports `GOOGLE_APPLICATION_CREDENTIALS` with the path to its JSON
file. Active Model Datastore also supports the following environment variables for platforms where
the JSON must be stored directly in environment variables:

```bash
SERVICE_ACCOUNT_PRIVATE_KEY = -----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n
SERVICE_ACCOUNT_CLIENT_EMAIL = web-app@app-name.iam.gserviceaccount.com
```

On Heroku the environment variables can be set under **Settings > Config Vars**.

Active Model Datastore will then handle the authentication for you, and the datastore instance can 
be accessed with `CloudDatastore.dataset`.

Datastore retries use `Rails.logger` automatically when Rails is available, which preserves tagged
logging such as request IDs. Other applications fall back to standard output. To use another logger,
configure it during application initialization:

```ruby
ActiveModel::Datastore.logger = MyApplication.logger
```

Retry messages identify the Datastore operation, entity kind, failed-attempt elapsed time, exception,
and retry delay.

There is an example Puma config file [here](https://github.com/Agrimatics/activemodel-datastore/blob/main/test/support/datastore_example_rails_app/config/puma.rb).
 
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

Data objects in Datastore are known as entities. Entities are of a kind. An entity has one
or more named properties, each of which can have one or more values. Think of them like this:
* 'Kind' (which is your table and the name of your Rails model)
* 'Entity' (which is the record from the table)
* 'Property' (which is the attribute of the record)

The `entity_properties` method defines an Array of properties that belong to the entity in
Datastore. Define the attributes of your model using `attr_accessor`. With this approach, Rails
deals solely with ActiveModel objects. The objects are converted to/from entities automatically 
during save/query operations. You can still use virtual attributes on the model (such as the 
`:state` attribute above) by simply excluding it from `entity_properties`. In this example state 
is available to the model but won't be persisted with the entity in Datastore.

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

Each entity in Datastore has a key that uniquely identifies it. The key consists of the
following components:

* the kind of the entity, which is User in these examples
* an identifier for the individual entity, which can be either a a key name string or an integer numeric ID
* an optional ancestor path locating the entity within the Datastore hierarchy

#### [all(options = {})](http://www.rubydoc.info/gems/activemodel-datastore/ActiveModel%2FDatastore%2FClassMethods:all)
Queries entities using the provided options. When a limit option is provided queries up to the limit 
and returns results with a cursor.
```ruby
users = User.all(options = {})

parent_key = CloudDatastore.dataset.key('Parent', 12345)
users = User.all(ancestor: parent_key)

users = User.all(ancestor: parent_key, where: ['name', '=', 'Bryce'])

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
# @option options [Array] :distinct_on Group results by a list of properties.
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

Google documents how [Datastore queries](https://cloud.google.com/datastore/docs/concepts/queries)
work, including their [restrictions](https://cloud.google.com/datastore/docs/concepts/queries#restrictions_on_queries).

## <a name="consistency"></a>Datastore Consistency and Concurrency

Firestore in Datastore mode is strongly consistent by default. Queries and key lookups reflect
completed writes, including queries that do not use an ancestor. The legacy Cloud Datastore behavior
where a newly created entity might not immediately appear in a global query does not apply.

Datastore supports three concurrency modes that determine how concurrent transactions interact:

- `PESSIMISTIC` uses reader/writer locks and is the default for new databases.
- `OPTIMISTIC` allows concurrent transactions, but only the first conflicting transaction to commit
  succeeds.
- `OPTIMISTIC_WITH_ENTITY_GROUPS` preserves legacy Cloud Datastore entity-group transaction
  semantics. Transactions are limited to 25 entity groups, writes to an entity group are limited to
  one per second, and queries within transactions must be ancestor queries.

Use the following command to inspect a database's concurrency mode:

```bash
gcloud firestore databases describe --project=PROJECT_ID --database=DATABASE_ID
```

Entity groups are hierarchies formed by a root entity and its children. They are useful for modeling
related entities and are required by the transactional restrictions of
`OPTIMISTIC_WITH_ENTITY_GROUPS`. To create an entity group, specify an ancestor path as part of the
child entity's key.

Before using the `save` method, assign the `parent_key_id` attribute an ID. Let's say that 12345 
represents the ID of the company that the users belong to. The key of the user entity will now 
look like this:

`@key=#<Google::Cloud::Datastore::Key @kind="User", @id=1, @parent=#<Google::Cloud::Datastore::Key @kind="ParentUser", @id=12345>>`

All of the User entities will now belong to an entity group named ParentUser and can be queried by the
Company ID. When we query for the users we will provide User.parent_key(12345) as the ancestor option.
The entity group relationship cannot be changed after creating the entity because an entity's key
cannot be modified after it has been saved.

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

See the Datastore documentation for details about
[transactions, isolation, and concurrency modes](https://cloud.google.com/datastore/docs/concepts/transactions#concurrency_modes).

## <a name="indexes"></a>Datastore Indexes

Every Datastore query computes its results using one or more indexes. The
indexes contain entity keys in a sequence specified by the index's properties and, optionally, 
the entity's ancestors.

There are two types of indexes, *built-in* and *composite*.

#### Built-in
By default, Datastore automatically predefines an index for each property of each entity kind.
These single property indexes are suitable for simple types of queries. These indexes are free and
do not count against your index limit.

#### Composite
Composite indexes include multiple property values per indexed entity. Composite indexes support
complex queries and are defined in an `index.yaml` file.

Composite indexes are required for queries of the following form:

* queries with ancestor and inequality filters
* queries with one or more inequality filters on a property and one or more equality filters on other properties
* queries with a sort order on keys in descending order
* queries with multiple sort orders
* queries with one or more filters and one or more sort orders

*NOTE*: Inequality filters are LESS_THAN, LESS_THAN_OR_EQUAL, GREATER_THAN, GREATER_THAN_OR_EQUAL.

See Google's [Datastore index documentation](https://cloud.google.com/datastore/docs/concepts/indexes)
for more information.

## <a name="emulator"></a>Firestore Emulator

Install the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) and the Firestore emulator:

```bash
gcloud components install cloud-firestore-emulator
```

The emulator requires Java 21 or later. Add the emulator executable to your shell's `PATH` because
the test helpers invoke it directly:

```bash
export PATH="$HOME/google-cloud-sdk/platform/cloud-firestore-emulator:$PATH"
```

The Firestore emulator runs in memory by default, so there is no datastore directory to create.
Start it in Datastore mode on the development port with:

```bash
cloud_firestore_emulator start --database-mode=datastore-mode --port=8180
```

Set `DATASTORE_EMULATOR_HOST=localhost:8180` so the Ruby client connects to the emulator. The gem sets
this automatically for Rails development and uses port 8181 for Rails tests.

By default, the emulator does not enforce composite indexes. To validate an index configuration, add
`--require-indexes --index-file=./index.yaml` when starting it. See Google's
[Firestore in Datastore mode emulator documentation](https://cloud.google.com/datastore/docs/emulator)
for more information.

## <a name="rails"></a>Example Rails App

There is an example Rails 8.1 app in the test directory [here](https://github.com/Agrimatics/activemodel-datastore/tree/main/test/support/datastore_example_rails_app).

Start the Firestore emulator in Datastore mode in one terminal:

```bash
cloud_firestore_emulator start --database-mode=datastore-mode --port=8180
```

Then start the example application in another terminal:

```bash
bundle install
rails server
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

Alternatively, `:reject_if` also accepts a symbol naming a method:

```ruby
class Recipe
  def ingredients_attributes=(attributes)
    assign_nested_attributes(:ingredients, attributes, reject_if: :reject_recipes)
  end

  def reject_recipes(attributes)
    attributes['name'].blank?
  end
end
```

Within the parent model `valid?` will validate the parent and associated children and
`nested_models` will return the child objects. If the nested form submitted params contained
a truthy `_destroy` key, the appropriate nested models will have `marked_for_destruction` set
to `true`.

## <a name="gotchas"></a>Datastore Gotchas
#### Ordering of query results is undefined when no sort order is specified.
When a query does not specify a sort order, the results are returned in the order they are retrieved. 
As the Datastore implementation evolves (or if a project's indexes change), this order may change.
Therefore, if your application requires its query results in a particular order, be sure to specify 
that sort order explicitly in the query.
