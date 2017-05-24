# Releasing Active Model Datastore

1. After all pull requests have been merged open the GitHub compare view in your browser and review.

`open https://github.com/Agrimatics/activemodel-datastore/compare/v<prev_version>...master`

2. If you haven't already, switch to the master branch, ensure that you have no changes, and pull 
from origin.

3. Edit the gem's version.rb file, changing the value to the new version number.

4. Run `rubocop`. The code base must have no offenses.

5. Run the gem tests with `rake test`.

6. You need to `cd test/support/datastore_example_rails_app/` and run the example Rails app tests 
with `rails test`.

7. Update the CHANGELOG.md.

8. Commit and push to master.

9. Run the `rake release` command. This will package the gem, a tag for the version of the release 
in Github and push to Rubygems.



