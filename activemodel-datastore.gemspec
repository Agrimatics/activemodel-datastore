# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_model/datastore/version'

Gem::Specification.new do |gem|
  gem.name          = 'activemodel-datastore'
  gem.version       = ActiveModel::Datastore::VERSION
  gem.authors       = ['Bryce McLean']
  gem.email         = ['mclean.bryce@gmail.com']

  gem.summary       = 'Cloud Datastore integration with Active Model'
  gem.description   = 'Makes the google-cloud-datastore gem compliant with active_model conventions and compatible with your Rails 5+ applications.'
  gem.homepage      = 'https://github.com/Agrimatics/activemodel-datastore'
  gem.license       = 'MIT'

  gem.metadata      = {
    "homepage_uri" => "https://github.com/Agrimatics/activemodel-datastore",
    "changelog_uri" => "https://github.com/Agrimatics/activemodel-datastore/blob/master/CHANGELOG.md",
    "source_code_uri" => "https://github.com/Agrimatics/activemodel-datastore/",
    "bug_tracker_uri" => "https://github.com/Agrimatics/activemodel-datastore/issues"
  }

  gem.required_ruby_version = '>= 2.2.2'

  gem.files         = Dir['CHANGELOG.md', 'README.md', 'LICENSE.txt', 'lib/**/*']
  gem.require_paths = ['lib']

  gem.add_runtime_dependency 'activemodel', '~> 5.0'
  gem.add_runtime_dependency 'activesupport', '~> 5.0'
  gem.add_runtime_dependency 'google-cloud-datastore', '~> 1.0'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'actionpack', '~> 5.0'
  gem.add_development_dependency 'factory_bot', '~> 4.8'
  gem.add_development_dependency 'faker', '~> 1.7', '>= 1.7.3'
  gem.add_development_dependency 'minitest', '~> 5.10'
  gem.add_development_dependency 'rubocop', '~> 0.48'
  gem.add_development_dependency 'carrierwave', '~> 1.1'
end
