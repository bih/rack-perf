module Rack
  class Perf
    require_relative "perf/version"

    attr_reader :starttime
    private :starttime

    attr_reader :endtime
    private :endtime

    attr_reader :label
    private :label

    def initialize(stack, label = "X-Perf-Timing")
      @stack = stack
      @label = label
    end

    def call(previous_state)
      @state = previous_state
      @starttime = Time.now

      @status, @headers, @body = stack.call(state)

      @endtime = Time.now

      logging.debug "got here"

      unless headers.has_key?(label)
        headers[label] = runtime
      end

      [status, headers, body]
    end

    private def runtime
      (endtime - starttime).to_s
    end

    private def stack
      @stack
    end

    private def state
      @state
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
