# Timeout
# Is the time taken from when a request first enters rack to when its response is sent back. When
# the application takes longer than the time specified below to process a request, the request's
# status is logged as timed_out and Rack::Timeout::RequestTimeoutException or
# Rack::Timeout::RequestTimeoutError is raised on the application thread.
Rack::Timeout::Logger.disable
