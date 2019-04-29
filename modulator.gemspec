
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "version"

Gem::Specification.new do |spec|
  spec.name          = "modulator"
  spec.version       = Modulator::VERSION
  spec.authors       = ["Damir Roso"]
  spec.email         = ["damir.roso@webteh.us"]

  spec.summary       = %q{Publish ruby methods as aws lambdas}
  spec.description   = %q{Publish ruby methods as aws lambdas}
  spec.homepage      = "https://github.com/damir/modulator"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/damir/modulator"
    # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rack-test", "~> 1.1"

  # stack builder
  # custom source is not supported by bundler, it is added to gemfile
  # spec.add_dependency "humidifier", github: 'damir/humidifier'
  spec.add_dependency "aws-sdk-s3"
  spec.add_dependency "aws-sdk-cloudformation"
  spec.add_dependency "rubyzip"

  # local gateway
  spec.add_dependency "puma"
  spec.add_dependency "roda"
  spec.add_dependency "rerun"
end
