module Rack
  class Perf
    require_relative "perf/version"
    require 'unirest'

    HIDDEN_READABLE_FIELDS = [
      :starttime, :endtime, :api_key,
      :debug, :stack, :env
    ]

    attr_reader *HIDDEN_READABLE_FIELDS
    private     *HIDDEN_READABLE_FIELDS

    def initialize(stack, api_key, debug = false)
      @stack   = stack
      @api_key = api_key
      @debug   = debug
    end

    def call(env)
      @env = env

      # log the current time now before the request starts
      @starttime = Time.now

      # run the current request
      request = Rack::Request.new(env)
      status, headers, body = stack.call(env)

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

    private

    # this method sends up the single timing request up to Perf
    # TODO: queue this up in a batch
    def send_data(ip_addr, request_method, request_url, normalized_uri, status_code, time_in_millis)
      head = {
        "Content-Type"          => "application/json",
        "X-Perf-Public-API-Key" => api_key
      }

      params = {
        'ip_addr'        => ip_addr,
        'request_method' => request_method,
        'request_url'    => request_url,
        'normalized_uri' => normalized_uri,
        'status_code'    => status_code,
        'time_in_millis' => time_in_millis
      }

      Unirest.post(
        "https://data.perf.sh/ingest",
        headers: head,
        parameters: [params].to_json { |response|
          # TODO: handle the incoming response
        })
    end

    # this gets us the matched normalized path so that we can aggregate
    # on it accordingly
    def get_normalized_path(request)
      path = request.path

      begin
        route = Rails.application.routes.recognize_path(path, method: request.request_method)
        params = {}

        route.each do |param, value|
          unless ["controller", "action"].include?(param.to_s)
            params[param.to_s] = value
          end
        end

        normalized_path = []

        path.split(/\//).each do |path_part|
          params.each do |param, path_value|
            if path_part == path_value
              path_part = ":%s" % param.to_s
            end

            format = params["format"].to_s

            if format && path_part == ("%s.%s" % [path_value, format])
              path_part = ":%s" % param.to_s
            end
          end

          normalized_path.push(path_part)
        end

        return normalized_path.join("/")
      rescue ActionController::RoutingError
        return nil
      end
    end

    # the time comes in unix seconds, so we need to
    # convert it to milliseconds and round
    def runtime
      ((endtime - starttime) * 1000).round
    end
  end
end
