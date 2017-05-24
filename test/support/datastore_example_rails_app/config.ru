# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'

use Rack::Static, urls: %w[/carrierwave-cache /uploads], root: 'tmp'

run Rails.application
