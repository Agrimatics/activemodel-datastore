### 0.6.0 / 2021-09-20
* defaulting the Google::Cloud.datastore network timeout to 15 sec and providing the env var DATASTORE_NETWORK_TIMEOUT as an override.

### 0.5.0 / 2020-08-17
* adding support Google::Cloud::Datastore 2.0.0 (rewritten low-level client, with improved performance and stability).

### 0.4.0 / 2019-08-23
* adding support for Rails 6

### 0.3.0 / 2018-04-17
* adding Travis CI configuration (rud)
* no longer override connection related environment variables if already defined(shao1555)
* adding support for passing query an array of select properties

### 0.2.5 / 2017-11-06
* adding support for setting indexed false on individual entity properties
* updating example Cloud Datastore Rails app to 5.1.4
* retry on exceptions are now specific to Google::Cloud::Error

### 0.2.4 / 2017-10-31
* non-Rails projects now source client authentication settings automatically (rjmooney)
* documentation improvements

### 0.2.3 / 2017-05-24
* adding CarrierWave file upload support
* updating example Cloud Datastore Rails app to 5.1
* adding image upload example to example Rails app

### 0.2.2 / 2017-04-27

* now store a hash of entity properties during entity to model conversion
* preparing for CarrierWave file upload support

### 0.2.1 / 2017-04-25

* adding support for boolean types to format_property_value

### 0.2.0 / 2017-04-19

* many documentation improvements
* adding support for creating entity groups through either a parent or parent_key_id
* example Rails 5 app

### 0.1.0 / 2017-03-27

Initial release.
