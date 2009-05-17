# $Id: dns_cache.rb 5040 2007-10-05 17:31:04Z francis $
#
#

require 'rubygems'
require 'eventmachine'
require 'resolv'


module EventMachine
module DnsCache

	class Cache
		def initialize
			@hash = {}
		end
		def add domain, value, expiration
			ex = ((expiration < 0) ? :none : (Time.now + expiration))
			@hash[domain] = [ex, value]
		end
		def retrieve domain
			if @hash.has_key?(domain)
				d = @hash[domain]
				if d.first != :none and d.first < Time.now
					@hash.delete(domain)
					nil
				else
					d.last
				end
			end
		end
	end

	@a_cache = Cache.new
	@mx_cache = Cache.new
	@nameservers = []
	@message_ix = 0

	def self.add_nameserver ns
		@nameservers << ns unless @nameservers.include?(ns)
	end

	def self.verbose v=true
		@verbose = v
	end


	def self.add_cache_entry cache_type, domain, value, expiration
		cache = if cache_type == :mx
			@mx_cache
		elsif cache_type == :a
			@a_cache
		else
			raise "bad cache type"
		end

		v = EM::DefaultDeferrable.new
		v.succeed( value.dup.freeze )
		cache.add domain, v, expiration
	end

	# Needs to be DRYed up with resolve_mx.
	#
	def self.resolve domain
		if d = @a_cache.retrieve(domain)
			d
		else
=begin
			d = @a_cache[domain]
			if d.first < Time.now
				STDOUT.puts "Expiring stale cache entry for #{domain}" if @verbose
				@a_cache.delete domain
				resolve domain
			else
				STDOUT.puts "Fulfilled #{domain} from cache" if @verbose
				d.last
			end
		else
=end
			STDOUT.puts "Fulfilling #{domain} from network" if @verbose
			d = EM::DefaultDeferrable.new
			d.timeout(5)
			@a_cache.add domain, d, 300 # Hard-code a 5 minute expiration
			#@a_cache[domain] = [Time.now+120, d] # Hard code a 120-second expiration.

			lazy_initialize
			m = Resolv::DNS::Message.new
			m.rd = 1
			m.add_question domain, Resolv::DNS::Resource::IN::A
			m = m.encode
			@nameservers.each {|ns|
				@message_ix = (@message_ix + 1) % 60000
				Request.new d, @message_ix
				msg = m.dup
				msg[0,2] = [@message_ix].pack("n")
				@u.send_datagram msg, ns, 53
			}

			d.callback {|resp|
				r = []
				resp.each_answer {|name,ttl,data|
					r << data.address.to_s if data.kind_of?(Resolv::DNS::Resource::IN::A)
				}

				# Freeze the array since we'll be keeping it in cache and passing it
				# around to multiple users. And alternative would have been to dup it.
				r.freeze
				d.succeed r
			}


			d
		end
	end


	# Needs to be DRYed up with resolve.
	#
	def self.resolve_mx domain
		if d = @mx_cache.retrieve(domain)
			d
		else
=begin
		if @mx_cache.has_key?(domain)
			d = @mx_cache[domain]
			if d.first < Time.now
				STDOUT.puts "Expiring stale cache entry for #{domain}" if @verbose
				@mx_cache.delete domain
				resolve_mx domain
			else
				STDOUT.puts "Fulfilled #{domain} from cache" if @verbose
				d.last
			end
		else
=end
			STDOUT.puts "Fulfilling #{domain} from network" if @verbose
			d = EM::DefaultDeferrable.new
			d.timeout(5)
			#@mx_cache[domain] = [Time.now+120, d] # Hard code a 120-second expiration.
			@mx_cache.add domain, d, 300 # Hard-code a 5 minute expiration

			mx_query = MxQuery.new d

			lazy_initialize
			m = Resolv::DNS::Message.new
			m.rd = 1
			m.add_question domain, Resolv::DNS::Resource::IN::MX
			m = m.encode
			@nameservers.each {|ns|
				@message_ix = (@message_ix + 1) % 60000
				Request.new mx_query, @message_ix
				msg = m.dup
				msg[0,2] = [@message_ix].pack("n")
				@u.send_datagram msg, ns, 53
			}



			d
		end

	end


	def self.lazy_initialize
		# Will throw an exception if EM is not running.
		# We wire a signaller into the socket handler to tell us when that socket
		# goes away. (Which can happen, among other things, if the reactor
		# stops and restarts.)
		#
		raise "EventMachine reactor not running" unless EM.reactor_running?

		unless @u
			us = proc {@u = nil}
			@u = EM::open_datagram_socket( "0.0.0.0", 0, Socket ) {|c|
				c.unbind_signaller = us
			}
		end

	end


	def self.parse_local_mx_records txt
		domain = nil
		addrs = []

		add_it = proc {
			a = addrs.sort {|m,n| m.last <=> n.last}.map {|y| y.first}
			add_cache_entry :mx, domain, a, -1
		}

		txt = StringIO.new( txt ) if txt.is_a?(String)
		txt.each_line {|ln|
			if ln =~ /\A\s*([\d\w\.\-\_]+)\s+(\d+)\s*\Z/
				if domain
					addrs << [$1.dup, $2.dup.to_i]
				end
			elsif ln =~ /\A\s*([^\s\:]+)\s*\:\s*\Z/
				add_it.call if domain
				domain = $1.dup
				addrs.clear
			end
		}

		add_it.call if domain
	end


	class MxQuery
		include EM::Deferrable

		def initialize rslt
			@result = rslt # Deferrable
			@n_a_lookups = 0

			self.callback {|resp|
				addrs = {}
				resp.each_additional {|name,ttl,data|
					addrs.has_key?(name) ? (addrs[name] << data.address.to_s) : (addrs[name] = [data.address.to_s])
				}

				@addresses = resp.answer.
				sort {|a,b| a[2].preference <=> b[2].preference}.
				map {|name,ttl,data|
					ex = data.exchange
					addrs[ex] or EM::DnsCache.resolve(ex.to_s)
				}

				@addresses.each_with_index {|a,ix|
					if a.respond_to?(:set_deferred_status)
						@n_a_lookups += 1
						a.callback {|r|
							@addresses[ix] = r
							@n_a_lookups -= 1
							succeed_result if @n_a_lookups == 0
						}
					end
				}

				succeed_result if @n_a_lookups == 0
			}
		end

		def succeed_result
			# Questionable whether we should uniq if it perturbs the sort order.
			# Also freeze it so some user can't wipe it out on us.
			@result.succeed @addresses.flatten.uniq.freeze
		end

	end

	class Request
		include EM::Deferrable

		@@outstanding = {}

		def self.post response
			if r = @@outstanding.delete(response.id)
				r.succeed response
			end
		end

		def initialize rslt, m_id
			@result = rslt
			@msgid = m_id
			raise "request-queue overflow" if @@outstanding.has_key?(@msgid)
			@@outstanding[@msgid] = self

			self.timeout(10)
			self.errback { @@outstanding.delete(@msgid) }
			self.callback {|resp| @result.succeed resp }
		end
	end

	class Socket < EM::Connection
		attr_accessor :unbind_signaller

		def receive_data dg
			m = nil
			begin
				m = Resolv::DNS::Message.decode dg
			rescue
			end
			Request.post(m) if m
		end

		def unbind
			@unbind_signaller.call if @unbind_signaller
		end
	end

end
end

