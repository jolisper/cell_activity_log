# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cell_activity_log/version'

Gem::Specification.new do |spec|
  spec.name          = "cell_activity_log"
  spec.version       = CellActivityLog::VERSION
  spec.authors       = ["Jorge Luis Pérez"]
  spec.email         = ["jorge@gmail.com"]
  spec.description   = %q{Activity logger for celluloid actors}
  spec.summary       = %q{Activity logger for celluloid actors}
  spec.homepage      = "https://github.com/jolisper/cell_activity_log"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
