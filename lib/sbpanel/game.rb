#!/usr/bin/env ruby

require 'file-tail'
require 'action_view'

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
      panel.update_status
      panel
    end

    def initialize(state)
      @address = "starbound.mispy.me"
      @port = 21025
      
      @status = state[:status] || :unknown
      @last_status_change = state[:last_status_change] || Time.now # Persist last observed status change
      @players = state[:players] || {} # Persist info for players we've seen
      @worlds = state[:worlds] || {} # Persist info for worlds we've seen
      @chat = state[:chat] || [] # Chat logs

      @version = 'unknown' # Server version
      @online_players = [] # Players we've seen connect
      @active_worlds = [] # Worlds we've seen activated
      @offline_players = @players.values.select { |pl| !@online_players.include?(pl) }

      @timing = false # We read the log initially without timing
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

    # Detect server status
    # Looks for processes which have log file open for writing
    def update_status
      status = :offline
      fuser = `fuser -v #{@log_path} 2>&1`.split("\n")[2..-1]
      
      if fuser
        fuser.each do |line|
          if line.strip.split[2].include?('F')
            status = :online
          end
        end
      end

      if status != @status
        time = Time.now
        if status == :offline
          puts "Server is currently offline"
        else
          puts "Server is currently online"
        end

        @status = status
        @last_status_change = time
        reset!
      end
    end

    # Reset non-persistent state
    def reset!
      @last_status_change = Time.now if @timing
      @online_players = []
      @active_worlds = []
      @offline_players = @players.values.select { |pl| !@online_players.include?(pl) }
    end

    def parse_line(line, time)
      events = {
        version: /^Info: Server version '(.+?)'/,
        login: /^Info: Client '(.+?)' <.> \(.+?\) connected$/,
        logout: /^Info: Client '(.+?)' <.> \(.+?\) disconnected$/,
        world: /^Info: Loading world db for world (\S+)/,
        unworld: /^Info: Shutting down world (\S+)/,
        chat: /^Info:  <(.+?)> (.+?)$/
      }

      events.each do |name, regex|
        event = regex.match(line)
        next unless event

        case name
        when :version
          puts "Server version: #{event[1]}"
          @version = event[1]
          reset!
        when :login
          name = event[1]

          player = @players[name] || {}
          player[:name] = name
          player[:last_connect] = time if @timing
          player[:last_seen] = time if @timing
          @players[name] = player

          @online_players.push(player) unless @online_players.find { |pl| pl[:name] == name }
          @offline_players.delete_if { |pl| pl[:name] == name }
          puts "#{name} connected at #{player[:last_connect]}"
        when :logout
          name = event[1]

          player = @players[name] || {}
          player[:name] = name
          player[:last_seen] = time if @timing
          @players[name] = player

          @online_players.delete_if { |pl| pl[:name] == name }
          @offline_players.push(player) unless @offline_players.find { |pl| pl[:name] == name }
          puts "#{name} disconnected at #{player[:last_seen]}"
        when :world
          coords = event[1]

          world = @worlds[coords] || {}
          world[:coords] = coords
          world[:last_load] = time if @timing
          @worlds[coords] ||= world

          @active_worlds.push(world) unless @active_worlds.find { |w| w[:coords] == coords }
          puts "Loaded world #{coords}"
        when :unworld
          coords = event[1]

          world = @worlds[coords] || {}
          world[:coords] = coords
          world[:last_unload] = time if @timing
          @worlds[coords] ||= world

          @active_worlds.delete_if { |w| w[:coords] == coords }
          puts "Unloaded world #{coords}"
        when :chat
          name = event[1]

          chat = {
            name: name,
            text: event[2]
          }

          player = @players[name] || {}
          player[:name] = name
          player[:last_seen] = time if @timing
          @players[name] ||= player

          # Hacky attempt to prevent chat desync
          if @timing || @last_chat == @chat[-1]
            @chat.push(chat)
            puts "#{chat[:name]}: #{chat[:text]}"
          end
          @last_chat = chat
        end

        if @timing
          # For post-initial-load events, check server
          # status and save state updates
          update_status; save
        end
      end
    end

    def read_logs
      # Initial read without timing
      File.read(@log_path).each_line do |line|
        parse_line(line, nil)
      end

      @timing = true
      log = File.open(@log_path)
      log.extend(File::Tail)
      log.backward(0)
      log.tail do |line|
        parse_line(line, Time.now)
      end

      log.close
    end
  end
end
