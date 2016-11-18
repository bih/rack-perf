module Rack
  class Perf
    require_relative "perf/version"
    require "unirest"

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
      performance_tracker = PerformanceTracker.new
      performance_tracker.start

      # run the current request
      request = Rack::Request.new(env)
      status, headers, body = stack.call(env)

      # log the end time of the request
      performance_tracker.end

      # normalize url
      normalized_path = NormalizePath.new(request)

      # send it up as long as we don't get nil, this helps
      # in cases when we intercept asset urls that don't
      # really matter
      if normalized_path.path?
        send_data                = SendDataToPerf.new
        send_data.api_key        = @api_key
        send_data.ip_addr        = DetermineIPAddress.new(request).ip_address
        send_data.request_method = request.request_method
        send_data.request_url    = request.url
        send_data.normalized_uri = normalized_path.path
        send_data.status_code    = status
        send_data.time_in_millis = performance_tracker.time
        send_data.perform!
      end

      # send back intended data
      [status, headers, body]
    end

    private

    class NormalizePath < Struct.new(:request)
      def path?
        path != nil
      end

      def path
        normalize_path
      rescue ActionController::RoutingError
        nil
      end

      private

      def route
        Rails.application.routes.recognize_path(request.path, method: request.request_method)
      end

      def params
        params = {}

        route
          .select { |param, value| ["controller", "action"].include?(param.to_s) }
          .each   { |param, value| params[param.to_s] = value }
      end

      def normalize_path
        path_split = request.path.split(/\//)
        format     = params["format"].to_s

        normalized_path = path_split.map do |path_part|
          params.each do |param, path_value|
            part_equals_value = path_part == path_value
            part_equals_value_with_format = format && path_part == ("%s.%s" % [path_value, format])

            if part_equals_value || part_equals_value_with_format
              path_part = ":%s" % param.to_s
            end
          end

          path_part
        end

        normalized_path.join("/")
      end
    end

    class DetermineIPAddress < Struct.new(:request)
      def ip_address
        forwarded_ip ? forwarded_ip : default_ip
      end

      private

      def default_ip
        request.ip
      end

      def forwarded_ip
        env["HTTP_X_FORWARDED_FOR"]
      end
    end

    class PerformanceTracker
      def start
        start_time = Time.now
      end

      def end
        end_time = Time.now
      end

      def time
        ((end_time - start_time) * 1000).round
      end

      private

      attr_accessor :start_time, :end_time
    end

    # this method sends up the single timing request up to Perf
    # TODO: queue this up in a batch
    class SendDataToPerf < Struct.new(:api_key, :ip_addr, :request_method, :request_url, :normalized_uri, :status_code, :time_in_millis)
      DESTINATION_URL = "https://data.perf.sh/ingest"

      def perform!
        Unirest.post(DESTINATION_URL, headers: headers, parameters: params_json)
      end

      private

      def headers
        { "Content-Type"          => "application/json",
          "X-Perf-Public-API-Key" => api_key }
      end

      def params
        { "ip_addr"        => ip_addr,
          "request_method" => request_method,
          "request_url"    => request_url,
          "normalized_uri" => normalized_uri,
          "status_code"    => status_code,
          "time_in_millis" => time_in_millis }
      end

      def params_json
        [params].to_json do
          # TODO: handle the incoming response
        end
      end
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

  end
end
