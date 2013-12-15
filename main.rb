#!/usr/bin/env ruby

require 'sinatra'

set :port, 8000
set :bind, "0.0.0.0"

Thread.abort_on_exception = true

STATE_PATH = File.join(ENV['HOME'], ".sbpanel.json")

class StarboundPanel
  def initialize(log_path)
    @log_path = log_path
    @log = File.open(@log_path)

    @status = :offline # Whether we're offline/online
    @status_change_time = Time.now # When we last went offline/online
    @version = 'unknown' # Server version
    @port = 'unknown' # Port bound
    @online_players = [] # Players and how long they've been online
    @offline_players = [] # Players and how long they've been gone
    @active_worlds = [] # Worlds and how long they've been active

    update_status!
  end

  # Detect server status
  # Looks for processes which have log file open for writing
  def update_status!
    status = :offline
    `fuser -v #{@log_path} 2>&1`.split("\n")[2..-1].each do |line|
      if line.strip.split[2].include?('F')
        status = :online
      end
    end

    if status != @status
      time = Time.now
      if status == :offline
        puts "Server shutting down"
      else
        puts "Server starting up"
      end

      @status = status
      @status_change_time = time
    end
  end

  def read_logs
    @log.tail do |line|
      update_status!

      time = Time.now

      version_event = line.match(/^Info: Server version '(.+?)'/)
      bind_event = line.match(/^Info: TcpServer listening on: [^:]+:(\d+)/)
      login_event = line.match(/^Info: Client <.> <User: (.+?)> connected$/)
      logout_event = line.match(/^Info: Client <.> <User: (.+?)> disconnected$/)
      world_event = line.match(/^Info: Loading world db for world (.+?)$/)
      unworld_event = line.match(/^Shutting down world (.+?)$/)

      if version_event
        puts "Server version: #{version_event[1]}"
        @version = version_event[1]

      elsif bind_event
        puts "Bound to TCP port: #{bind_event[1]}"
        @port = bind_event[1]

      elsif login_event
        puts "#{login_event[1]} logged in at #{time}"
        @offline_players.delete_if { |pl| pl[:name] == login_event[1] }

        @online_players.push({
          name: login_event[1],
          connected_at: time
        })
      elsif logout_event
        puts "#{logout_event[1]} logged out at #{time}"
        @online_players.delete_if { |pl| pl[:name] == logout_event[1] }

        @offline_players.push({
          name: logout_event[1],
          last_seen: time
        })
      elsif world_event
        puts "Loaded world #{world_event[1]}"
        @active_worlds.push({
          coords: world_event[1],
          loaded_at: time
        })
      elsif unworld_event
        puts "Unloaded world #{unworld_event[1]}"
        @active_worlds.delete_if { |w| w[:coords] == unworld_event[1] }
      end
    end
  end
end

panel = StarboundPanel.new(ARGV[0])
Thread.new { panel.read_logs }

get '/' do
  panel.update_status!
  erb :index, scope: panel
end
