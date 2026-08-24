# Releasing Active Model Datastore

1. After all pull requests have been merged open the GitHub compare view in your browser and review.

`open https://github.com/Agrimatics/activemodel-datastore/compare/v<prev_version>...main`

2. If you haven't already, switch to the main branch, ensure that you have no changes, and pull 
from origin.

3. Edit the gem's version.rb file, changing the value to the new version number.

4. Run `bundle exec rubocop`. The code base must have no offenses.

5. Run the gem tests with `bundle exec rake test`.

6. Change to `test/support/datastore_example_rails_app/` and run the example Rails app tests with
`bundle exec rails test`.

7. Update the CHANGELOG.md.

8. Commit and push to main.

9. Run the `rake release` command. This will package the gem, a tag for the version of the release 
in Github and push to Rubygems.
