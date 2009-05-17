begin
  require 'jeweler'
rescue LoadError
  raise "Jeweler, or one of its dependencies, is not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

Jeweler::Tasks.new do |s|
  s.name = "em-dns"
  s.summary = "Resolve domain names from EventMachine natively"
  s.email = "astro@spaceboyz.net"
  s.homepage = "http://github.com/astro/em-dns"
  s.description = "DNS::Resolv made ready for EventMachine"
  s.authors = ["Aman Gupta", "Stephan Maka"]
  s.files =  FileList["[A-Z]*", "{lib,test}/**/*"]
  s.add_dependency 'eventmachine'
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.test_files = FileList["test/test*.rb"]
end
