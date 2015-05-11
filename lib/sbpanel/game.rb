#!/usr/bin/env ruby

require 'file-tail'
require 'action_view'
require 'time'
require 'date'
require 'socket'
require 'timeout'

module SBPanel
  class Game
    attr_accessor :log_path, :state_path, :address

    def self.load(log_path)
      state_path = File.join(File.dirname(log_path), ".sbpanel")

      state = {}
      if File.exists?(state_path)
        begin
          state = Marshal.load(File.read(state_path))
          puts "Loaded sbpanel state from #{state_path}"
        rescue Exception
          puts "Error loading sbpanel state, making new panel"
        end
      end

      panel = Game.new(state)

      panel.log_path = log_path
      panel.state_path = state_path
      panel.update_status!
      panel
    end

    def initialize(state)
      @address = "starbound.mispy.me"
      @port = 21025
      
      @status = state[:status] || :unknown
      @date = :unknown
      @last_status_change = state[:last_status_change] || Time.now # Persist last observed status change
      @last_launch = state[:last_launch] || Time.now
      @players = state[:players] || {} # Persist info for players we've seen
      @worlds = state[:worlds] || {} # Persist info for worlds we've seen
      @chat = state[:chat] || [] # Chat logs

      @version = 'unknown' # Server version
      @online_players = [] # Players we've seen connect
      @active_worlds = [] # Worlds we've seen activated
      @offline_players = @players.values.select { |pl| !@online_players.include?(pl) }

      @lasttime = nil
      @postinit = false
    end

    def save
      File.open(@state_path, 'w') do |f|
        f.write(Marshal.dump({
          players: @players,
          worlds: @worlds,
          status: @status,
          last_status_change: @last_status_change,
          chat: @chat
        }))
      end
    end

    def is_port_open?(ip, port)
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new(ip, port)
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          end
        end
      rescue Timeout::Error        
      end  

      return false
    end

    # Detect server status
    # Looks for processes which have log file open for writing
    def update_status!
      status = :online

      if !is_port_open?(@address, @port)
        status = :offline
      end

      if status != @status
        time = Time.now
        if status == :offline
          puts "Server is currently offline"
        else
          puts "Server is currently online"
        end

        @status = status
        if @status == :online
          @last_status_change = @last_launch
        else
          @last_status_change = time
        end
      end
    end

    def parse_line(line)
      events = {
        start: /^Start logging at: (\S+) (\S+)$/,
        version: /^\[(.+?)\] Info: Server Version '(.+?)'/,
        login: /^\[(.+?)\] Info: (?:UniverseServer: )?Client '(.+?)' <.+?> \(.+?\) connected$/,
        logout: /^\[(.+?)\] Info: (?:UniverseServer: )?Client '(.+?)' <.+?> \(.+?\) disconnected$/,
        world: /^\[(.+?)\] Info: (?:UniverseServer: )?Loading celestial world (\S+)/,
        unworld: /^\[(.+?)\] Info: (?:UniverseServer: )?Stopping world CelestialWorld:(\S+)/,
        chat: /^\[(.+?)\] Info: Chat: <(.+?)> (.+?)$/
      }      

      events.each do |name, regex|
        event = regex.match(line)
        next unless event

        time = nil
        if name != :start        
          raw = Time.parse(event[1])
          time = Time.mktime(@date.year, @date.month, @date.day, raw.hour, raw.min, raw.sec)

          # the timestamps have time but not date, which means we need to check if
          # we've wrapped around and hit another day
          while !@lasttime.nil? && time < @lasttime   
            @date += 1
            time = Time.mktime(@date.year, @date.month, @date.day, raw.hour, raw.min, raw.sec)
          end

          @lasttime = time
        end

        case name
        when :start
          @date = Date.parse(event[1])
          raw = Time.parse(event[2])
          @last_launch = Time.mktime(@date.year, @date.month, @date.day, raw.hour, raw.min, raw.sec)
          if @status == :online
            @last_status_change = @last_launch
          end
          @online_players = []
          @active_worlds = []
          @offline_players = @players.values.select { |pl| !@online_players.include?(pl) }
        when :version
          puts "Server version: #{event[2]}"
          @version = event[2]
        when :login
          name = event[2]

          player = @players[name] || {}
          player[:name] = name
          player[:last_connect] = time
          player[:last_seen] = time
          @players[name] = player

          @online_players.push(player) unless @online_players.find { |pl| pl[:name] == name }
          @offline_players.delete_if { |pl| pl[:name] == name }
          puts "#{name} connected at #{player[:last_connect]}"
        when :logout
          name = event[2]

          player = @players[name] || {}
          player[:name] = name
          player[:last_seen] = time
          @players[name] = player

          @online_players.delete_if { |pl| pl[:name] == name }
          @offline_players.push(player) unless @offline_players.find { |pl| pl[:name] == name }
          puts "#{name} disconnected at #{player[:last_seen]}"
        when :world
          coords = event[2]

          world = @worlds[coords] || {}
          world[:coords] = coords
          world[:last_load] = time
          @worlds[coords] ||= world

          @active_worlds.push(world) unless @active_worlds.find { |w| w[:coords] == coords }
          puts "Loaded world #{coords}"
        when :unworld
          coords = event[2]

          world = @worlds[coords] || {}
          world[:coords] = coords
          world[:last_unload] = time
          @worlds[coords] ||= world

          @active_worlds.delete_if { |w| w[:coords] == coords }
          puts "Unloaded world #{coords}"
        when :chat
          name = event[2]

          chat = {
            time: time,
            name: name,
            text: event[3]
          }

          break if chat[:text].start_with?("/")

          player = @players[name] || {}
          player[:name] = name
          player[:last_seen] = time
          @players[name] ||= player

          @online_players.push(player) unless @online_players.find { |pl| pl[:name] == name }

          # Hacky attempt to prevent chat desync
          if @postinit || @last_chat == @chat[-1]
            @chat.push(chat)
            puts "#{chat[:name]}: #{chat[:text]}"
          end
          @last_chat = chat
        end

        if @postinit
          # For post-initial-load events, check server
          # status and save state updates
          update_status!; save
        end

        break
      end
    end

    def read_logs
      File.read(@log_path).each_line do |line|
        parse_line(line)
      end

      @postinit = true
  
      loop do
        log = File.open(@log_path)
        log.extend(File::Tail)
        log.backward(0)

        begin
          log.tail do |line|
            parse_line(line)
          end
        rescue Exception => e
          p e
        end
      end

      log.close
    end
  end
end
