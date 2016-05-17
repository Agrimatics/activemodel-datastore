# Puma can fork multiple OS processes within each instance to allow Rails to support multiple
# concurrent requests (Cluster Mode). In Puma terminology these are referred to as worker processes.
# Worker processes are isolated from one another at the OS level, therefore not needing to be thread
# safe. Rule of thumb is to set the number of workers equal to the number of CPU cores.

workers Integer(ENV['WEB_CONCURRENCY'] || 2)

# On MRI, there is a Global Interpreter Lock (GIL) that ensures only one thread can be run at any
# time. IO operations such as database calls, interacting with the file system, or making external
# http calls will not lock the GIL. Most Rails applications heavily use IO, so adding additional
# threads will allow Puma to process multiple threads.

threads_count = Integer(ENV['MAX_THREADS'] || 5)
threads threads_count, threads_count

# When you use preload_app, your new code goes all in the master process, and is then copied in
# the workers (meaning it's only compatible with cluster mode). General rule is to use preload_app
# when your workers die often and need fast starts. If you don't have many workers, you probably
# should not use preload_app.

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

on_restart do
  CloudDatastore.reset_dataset
end

on_worker_boot do
  CloudDatastore.reset_dataset
end
