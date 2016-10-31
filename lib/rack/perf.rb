module Rack
  class Perf
    require_relative "perf/version"

    attr_reader :starttime
    private :starttime

    attr_reader :endtime
    private :endtime

    attr_reader :api_key
    private :api_key

    attr_reader :debug
    private :debug

    def initialize(stack, api_key, debug = false)
      @stack = stack
      @api_key = api_key
      @debug = debug
    end

    def call(env)
      @env = env
      @starttime = Time.now

      request = Rack::Request.new(env)
      @status, @headers, @body = stack.call(env)

      @endtime = Time.now

      ip_addr = request.ip
      ip_addr = env["HTTP_X_FORWARDED_FOR"] if env["HTTP_X_FORWARDED_FOR"]

      normalized_uri = get_normalized_path(request)

      if normalized_uri
        send_data(request.ip, request.request_method, request.url, normalized_uri, status, runtime)
      end
      
      [status, headers, body]
    end

    private def send_data(ip_addr, request_method, request_url, normalized_uri, status_code, time_in_millis)
      uri = URI.parse("https://data.perf.sh")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new('/ingest')
      request.add_field('Content-Type', 'application/json')
      request.add_field('X-Perf-Public-API-Key', api_key)
      request.body = {
        'ip_addr' => ip_addr,
        'request_method' => request_method,
        'request_url' => request_url,
        'normalized_uri' => normalized_uri,
        'status_code' => status_code,
        'time_in_millis' => time_in_millis
      }.to_json

      puts request.body if debug

      response = http.request(request)
    end

    private def get_normalized_path(request)
      path = request.path

      begin
        route = Rails.application.routes.recognize_path path, method: request.request_method
        params = {}
        route.each{ |param, value|
          if not ["controller", "action"].include?(param.to_s)
            params[param.to_s] = value
          end
        }

        normalized_path = []
        path.split(/\//).each { |path_part|
          params.each { |param, path_value|
            if path_part == path_value
              path_part = ":" + param.to_s
            end

            if params["format"] && path_part == path_value + "." + params["format"]
              path_part = ":" + param.to_s
            end
          }

          normalized_path.push(path_part)
        }

        return normalized_path.join("/")
      rescue ActionController::RoutingError
        return nil
      end
    end

    private def runtime
      ((endtime - starttime) * 1000).round
    end

    private def stack
      @stack
    end

    private def env
      @env
    end

    private def headers
      @headers
    end

    private def status
      @status
    end

    private def body
      @body
    end
  end
end
