# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rack/perf/version'

Gem::Specification.new do |spec|
  spec.name          = "rack-perf"
  spec.version       = Rack::Perf::VERSION
  spec.authors       = ["Steven Lu"]
  spec.email         = ["steve@perf.sh"]

  spec.summary       = %q{Perf middleware}
  spec.description   = %q{Rack middleware that records endpoint timing and status codes to Perf}
  spec.homepage      = "https://github.com/perflabs/rack-perf"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "unirest", "~> 1.1.2"
  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
end
