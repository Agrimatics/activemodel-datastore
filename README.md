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
- [Development and Test](#development)
- [Nested Forms](#nested)
- [Work In Progress](#wip)
 
## <a name="setup"></a>Setup
 
Generate your Rails app without ActiveRecord:
 
```bash
rails new my_app -O
```

To install, add this line to your `Gemfile` and run `bundle install`:
 
```ruby
gem 'activemodel-datastore'
```
  
Google Cloud requires a Project ID and Service Account Credentials to connect to the Datastore API.
 
*Follow the [activation instructions](https://cloud.google.com/datastore/docs/activate) to use the Google Cloud Datastore API.*

Set your project id in an `ENV` variable named `GCLOUD_PROJECT`.

To locate your project ID:

1. Go to the Cloud Platform Console.
2. From the projects list, select the name of your project.
3. On the left, click Dashboard. The project name and ID are displayed in the Dashboard.

When running on Google Cloud Platform environments the Service Account credentials will be discovered automatically. 
When running on other environments (such as AWS or Heroku), the Service Account credentials need to be 
specified in two additional `ENV` variables named `SERVICE_ACCOUNT_CLIENT_EMAIL` and `SERVICE_ACCOUNT_PRIVATE_KEY`.

```bash
SERVICE_ACCOUNT_PRIVATE_KEY = -----BEGIN PRIVATE KEY-----\nMIIFfb3...5dmFtABy\n-----END PRIVATE KEY-----\n
SERVICE_ACCOUNT_CLIENT_EMAIL = web-app@app-name.iam.gserviceaccount.com
```

On Heroku the `ENV` variables can be set under 'Settings' -> 'Config Variables'.
 
## <a name="model"></a>Model Example
 
Let's start by implementing the model:

```ruby
class User
  include ActiveModel::Datastore

  attr_accessor :email, :name, :enabled, :state

  before_validation :set_default_values
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

Using `attr_accessor` the attributes of the model are defined. Validations and Callbacks all work 
as you would expect. However, `entity_properties` is new. Data objects in Cloud Datastore
are known as entities. Entities are of a kind. An entity has one or more named properties, each
of which can have one or more values. Think of them like this:
* 'Kind' (which is your table)
* 'Entity' (which is the record from the table)
* 'Property' (which is the attribute of the record)

The `entity_properties` method defines an Array of the properties that belong to the entity in
cloud datastore. With this approach, Rails deals solely with ActiveModel objects. The objects are
converted to/from entities as needed during save/query operations.

We have also added the ability to set default property values and type cast the format of values
for entities.

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

Queries entities using the provided options. When a limit option is provided queries up to the limit 
and returns results with a cursor.
```ruby
users = User.all

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

Find entity by id - this can either be a specific id (1), a list of ids (1, 5, 6), or an array of ids ([5, 6, 10]). 
The parent key is optional.
```ruby
user = User.find(1)

parent = CloudDatastore.dataset.key('Parent', 12345)
user = User.find(1, parent: parent)

users = User.find(1, 2, 3)
```

Finds the first entity matching the specified condition.
```ruby
user = User.find_by(name: 'Joe')

user = User.find_by(name: 'Bryce', ancestor: parent)
```

## <a name="development"></a>Development and Test

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

    $ ./start-local-datastore.sh
    
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

## <a name="wip"></a>Work In Progress

TODO: document datastore eventual consistency and mitigation using ancestor queries and entity groups.

TODO: document indexes.

TODO: document using the datastore emulator to generate the index.yaml.

TODO: document the change tracking implementation.