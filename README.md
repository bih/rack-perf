# Rack::Perf

This Rack middleware will time and record status codes from your controllers. It will then send up this timing data
to Perf's logging infrastructure where metrics and alerts are generated.

## Installation

* Add this line to your application's Gemfile:

    ```ruby
    gem 'rack-perf'
    ```

* And then execute:
    
    ```bash
    bundle
    ```

* In your application.rb file, add the middleware in your application class

    ```ruby
    module Example
      class Application < Rails::Application
        # ADD THIS LINE INTO THE APPROPRIATE MODULE
        config.middleware.use Rack::Perf, api_key="PERF_API_KEY"
      end
    end
    ```
