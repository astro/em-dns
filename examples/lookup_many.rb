#!/usr/bin/env ruby

require 'uri'
require 'eventmachine'
$: << File.dirname(__FILE__) + '/../lib'
require 'em/dns_resolver'

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

BATCH_SIZE = 30
EM.run {
  pending = 0
  EM.add_periodic_timer(1) do
    batch, hosts = hosts[0..(BATCH_SIZE-1)], hosts[BATCH_SIZE..-1]
    batch.each do |host|
      df = EM::DnsResolver.resolve(host)
      df.callback { |a|
        p host => a
        pending -= 1
        EM.stop if pending < 1 && hosts.empty?
      }
      df.errback { |*a|
        puts "Cannot resolve #{host}: #{a.inspect}"
        pending -= 1
        EM.stop if pending < 1 && hosts.empty?
      }
      pending += 1
      puts "#{pending} pending"
    end
    puts "Started all: #{pending} pending"
  end
}
