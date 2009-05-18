# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{em-dns}
  s.version = "0.0.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Aman Gupta", "Stephan Maka"]
  s.date = %q{2009-05-19}
  s.description = %q{DNS::Resolv made ready for EventMachine}
  s.email = %q{astro@spaceboyz.net}
  s.files = [
    "Rakefile",
     "VERSION.yml",
     "lib/em/dns_cache.rb",
     "test/test_basic.rb"
  ]
  s.homepage = %q{http://github.com/astro/em-dns}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.3}
  s.summary = %q{Resolve domain names from EventMachine natively}
  s.test_files = [
    "test/test_basic.rb",
     "examples/lookup_many.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<eventmachine>, [">= 0"])
    else
      s.add_dependency(%q<eventmachine>, [">= 0"])
    end
  else
    s.add_dependency(%q<eventmachine>, [">= 0"])
  end
end
