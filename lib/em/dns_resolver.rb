require 'eventmachine'
require 'resolv'

module EventMachine
  module DnsResolver
    ##
    # Global interface
    ##

    def self.resolve(hostname)
      Request.new(socket, hostname)
    end

    def self.socket
      unless defined?(@socket)
        @socket = DnsSocket.open
      end
      @socket
    end

    def self.nameserver=(ns)
      @nameserver = ns
    end
    def self.nameserver
      unless defined?(@nameserver)
        IO::readlines('/etc/resolv.conf').each do |line|
          if line =~ /^nameserver (.+)$/
            @nameserver = $1.split(/\s+/).first
          end
        end
      end
      @nameserver
    end

    ##
    # Socket stuff
    ##

    class RequestIdAlreadyUsed < RuntimeError
    end

    class DnsSocket < EM::Connection
      def self.open
        EM::open_datagram_socket('0.0.0.0', 0, self)
      end
      def post_init
        @requests = {}
        EM.add_periodic_timer(1, &method(:tick))
      end
      # Periodically called each second to fire request retries
      def tick
        @requests.each do |id,req|
          req.tick
        end
      end
      def register_request(id, req)
        if @requests.has_key?(id)
          raise RequestIdAlreadyUsed
        else
          @requests[id] = req
        end
      end
      def send_packet(pkt)
        send_datagram(pkt, nameserver, 53)
      end
      def nameserver=(ns)
        @nameserver = ns
      end
      def nameserver
        @nameserver ||= DnsResolver.nameserver
      end
      # Decodes the packet, looks for the request and passes the
      # response over to the requester
      def receive_data(data)
        msg = nil
        begin
          msg = Resolv::DNS::Message.decode data
        rescue
        else
          req = @requests[msg.id]
          if req
            @requests.delete(msg.id)
            req.receive_answer(msg)
          end
        end
      end
    end

    ##
    # Request
    ##

    class Request
      include Deferrable
      attr_accessor :retry_interval
      attr_accessor :max_tries
      def initialize(socket, hostname)
        @socket = socket
        @hostname = hostname
        @tries = 0
        @last_send = Time.at(0)
        @retry_interval = 3
        @max_tries = 5
        make_id
        make_packet
        EM.next_tick { tick }
      end
      def tick
        # Break early if nothing to do
        return if @last_send + @retry_interval > Time.now

        if @tries < @max_tries
          send
        else
          fail 'retries exceeded'
        end
      end
      # Called by DnsSocket#receive_data
      def receive_answer(msg)
        addrs = []
        msg.each_answer do |name,ttl,data|
          if data.kind_of?(Resolv::DNS::Resource::IN::A) ||
              data.kind_of?(Resolv::DNS::Resource::IN::AAAA)
            addrs << data.address.to_s
          end
        end
        if addrs.empty?
          fail "rcode=#{msg.rcode}"
        else
          succeed addrs
        end
      end
      private
      def send
        @socket.send_packet(@pkt.encode)
        @tries += 1
        @last_send = Time.now
      end
      def make_id
        begin
          @id = rand(65535)
          @socket.register_request(@id, self)
        rescue RequestIdAlreadyUsed
          retry
        end
      end
      def make_packet
        msg = Resolv::DNS::Message.new
        msg.id = @id
        msg.rd = 1
        msg.add_question @hostname, Resolv::DNS::Resource::IN::A
        @pkt = msg
      end
    end
  end
end
