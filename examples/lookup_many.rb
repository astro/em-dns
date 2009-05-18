#!/usr/bin/env ruby

require 'uri'
require 'eventmachine'
$: << File.dirname(__FILE__) + '/../lib'
require 'em/dns_cache'

if ARGV.size == 0
  puts "Usage: #{$0} <url-files>"
  exit
end


hosts = []
ARGV.each do |fn|
  IO::readlines(fn).each do |line|
      line.chomp!
      line.split(/\s+/).each do |url|
        uri = URI::parse(url)
        hosts << uri.host
    end
  end
end
puts "Will resolve #{hosts.size} hosts"

EM::DnsCache.add_nameservers_from_file
EM::DnsCache.verbose

EM.run {
  pending = 0
  hosts.each do |host|
    df = EM::DnsCache.resolve(host)
    df.callback { |*a|
      if a.size == 1
        if a.kind_of?(Array)
          # Good!
        else
          p host => a[0]
        end
      else
        p host => {:args => a}
      end
      pending -= 1
      EM.stop if pending < 1
    }
    df.errback { |*a|
      puts "Cannot resolve #{host}: #{a.inspect}"
      pending -= 1
      EM.stop if pending < 1
    }
    pending += 1
    puts "#{pending} pending"
  end
  puts "Started all: #{pending} pending"
}
