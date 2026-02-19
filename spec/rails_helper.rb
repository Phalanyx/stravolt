require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # Auto-prepare the test database so `bundle exec rspec` always works without
  # needing a manual `db:test:prepare` or `db:test:migrate` beforehand.
  config.before(:suite) do
    begin
      ActiveRecord::Migration.maintain_test_schema!
    rescue ActiveRecord::PendingMigrationError
      # New migrations exist — run them and clear AR's schema cache.
      ActiveRecord::Tasks::DatabaseTasks.migrate
      ActiveRecord::Base.clear_cache!
    rescue ActiveRecord::StatementInvalid
      # Schema hasn't been loaded at all — load it now.
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb")
    end
  end
end
