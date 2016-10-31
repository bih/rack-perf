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

      # log the current time now before the request starts
      @starttime = Time.now

      # run the current request
      request = Rack::Request.new(env)
      @status, @headers, @body = stack.call(env)

      # log the end time of the request
      @endtime = Time.now

      # get all extra information that we need for logging
      # that request to Perf
      ip_addr = request.ip
      ip_addr = env["HTTP_X_FORWARDED_FOR"] if env["HTTP_X_FORWARDED_FOR"]
      normalized_uri = get_normalized_path(request)

      # send it up as long as we don't get nil, this helps
      # in cases when we intercept asset urls that don't
      # really matter
      if normalized_uri
        send_data(request.ip, request.request_method, request.url, normalized_uri, status, runtime)
      end

      # send back intended data
      [status, headers, body]
    end

    # this method sends up the single timing request up to Perf
    # TODO: queue this up in a batch
    private def send_data(ip_addr, request_method, request_url, normalized_uri, status_code, time_in_millis)
      uri = URI.parse("https://data.perf.sh")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new('/ingest')
      request.add_field('Content-Type', 'application/json')

      request.add_field('X-Perf-Public-API-Key', api_key)
      request.body = [{
        'ip_addr' => ip_addr,
        'request_method' => request_method,
        'request_url' => request_url,
        'normalized_uri' => normalized_uri,
        'status_code' => status_code,
        'time_in_millis' => time_in_millis
      }].to_json

      puts request.body if debug

      response = http.request(request)
      # TODO: handle the incoming response
    end

    # this gets us the matched normalized path so that we can aggregate
    # on it accordingly
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

    # the time comes in unix seconds, so we need to
    # convert it to milliseconds and round
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
