require "fileutils"

module TestQueue
  class Iterator
    attr_reader :stats, :sock

    def initialize(sock, suites, filter=nil)
      @done = false
      @stats = {}
      @procline = $0
      @sock = sock
      @suites = suites
      @filter = filter
      if @sock =~ /^(.+):(\d+)$/
        @tcp_address = $1
        @tcp_port = $2.to_i
      end
    end

    def each
      fail "already used this iterator. previous caller: #@done" if @done

      while true
        client = connect_to_master('POP')
        break if client.nil?
        r, w, e = IO.select([client], nil, [client], nil)
        break if !e.empty?

        if data = client.read(65536)
          client.close
          item = Marshal.load(data)
          break if item.nil? || item.empty?
          suite = @suites[item]

          $0 = "#{@procline} - #{suite.respond_to?(:description) ? suite.description : suite}"
          start = Time.now
          if @filter
            @filter.call(suite){ yield suite }
          else
            yield suite
          end
          @stats[suite.to_s] = Time.now - start
        else
          break
        end
      end
    rescue Errno::ENOENT, Errno::ECONNRESET, Errno::ECONNREFUSED
    ensure
      @done = caller.first
      FileUtils.mkdir_p("#{Dir.pwd}/.test-queue/stats")
      File.open("#{Dir.pwd}/.test-queue/stats/#{$$}", "wb") do |f|
        f.write Marshal.dump(@stats)
      end
    end

    def connect_to_master(cmd)
      sock =
        if @tcp_address
          puts "Connecting to master at tcp://#{@tcp_address}:#{@tcp_port}"
          TCPSocket.new(@tcp_address, @tcp_port)
        else
          puts "Connecting to master at sock: #{@sock}"
          UNIXSocket.new(@sock)
        end
      sock.puts(cmd)
      sock
    rescue Errno::EPIPE
      nil
    end

    include Enumerable

    def empty?
      false
    end
  end
end
