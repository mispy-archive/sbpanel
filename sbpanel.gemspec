# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sbpanel/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jaiden Mispy"]
  gem.email         = ["^_^@mispy.me"]
  gem.description   = %q{Web status panel for Starbound servers}
  gem.summary       = %q{Web status panel for Starbound servers}
  gem.homepage      = "http://starbound.mispy.me"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "sbpanel"
  gem.require_paths = ["lib"]
  gem.version       = SBPanel::VERSION

  # Sinatra and associated webserver
  gem.add_runtime_dependency 'sinatra'
  gem.add_runtime_dependency 'webrick'

  # FileTail gem for reading logs
  gem.add_runtime_dependency 'file-tail'

  # For time display helpers from Rails
  gem.add_runtime_dependency 'actionpack'
end
