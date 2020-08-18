# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers a minimum and maximum.
# On MRI, there is a Global Interpreter Lock (GIL) that ensures only one
# thread can be run at any time. IO operations such as database calls,
# interacting with the file system, or making external http calls will not
# lock the GIL. Most Rails applications heavily use IO, so adding additional
# threads will allow Puma to process multiple threads.
#
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

rackup      DefaultRackup
port        ENV.fetch('PORT', 3000)
environment ENV.fetch('RAILS_ENV', 'development')

if ENV.fetch('WEB_CONCURRENCY', 0).to_i > 1
  # Puma can fork multiple OS processes within each instance to allow Rails
  # to support multiple concurrent requests (Cluster Mode). In Puma terminology
  # these are referred to as worker processes. Worker processes are isolated from
  # one another at the OS level, therefore not needing to be thread safe. Rule of
  # thumb is to set the number of workers equal to the number of CPU cores.
  #
  workers ENV.fetch('WEB_CONCURRENCY').to_i

  # Use the `preload_app!` method when specifying a `workers` number.
  # This directive tells Puma to first boot the application and load code
  # before forking the application. This takes advantage of Copy On Write
  # process behavior so workers use less memory. When you use preload_app,
  # your new code goes all in the master process, and is then copied to
  # the workers (meaning preload_app is only compatible with cluster mode).
  # If you use this option you need to make sure to reconnect any threads in
  # the `on_worker_boot` block.
  #
  preload_app!

  # Code to run in the master immediately before the master starts workers. As the master process
  # boots the rails application (and executes the initializers) before forking workers, it's
  # recommended to close any connections that were automatically established in the master to
  # prevent connection leakage.
  #
  before_fork do
    CloudDatastore.reset_dataset
  end

  # The code in the `on_worker_boot` will be called if you are using
  # clustered mode by specifying a number of `workers`. After each worker
  # process is booted this block will be run, if you are using `preload_app!`
  # option you will want to use this block to reconnect to any threads
  # or connections that may have been created at application boot, Ruby
  # cannot share connections between processes. Code in the block is run before
  # it starts serving requests. This is called every time a worker is to be started.
  #
  on_worker_boot do
    CloudDatastore.dataset
  end
end

# Code to run before doing a restart. This code should close log files, database connections, etc
# so that their file descriptors don't leak into the restarted process.
#
on_restart do
  CloudDatastore.reset_dataset
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
