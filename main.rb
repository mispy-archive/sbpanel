#!/usr/bin/env ruby

require 'sinatra'
require 'file-tail'
require 'action_view'

set :port, 8000
set :bind, "0.0.0.0"

class StarboundPanel
  def initialize(log_path)
    @log_path = log_path

    @address = "starbound.mispy.me"
    @port = 21025

    @status = :unknown # Whether we're offline/online
    @status_change_time = Time.now # When we last went offline/online
    @version = 'unknown' # Server version
    @online_players = [] # Players and how long they've been online
    @offline_players = [] # Players and how long they've been gone
    @active_worlds = [] # Worlds and how long they've been active

    update_status!
  end

  # Detect server status
  # Looks for processes which have log file open for writing
  def update_status!
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
      @status_change_time = time
    end
  end

  def parse_line!(line, time)
    time = Time.now

    version_event = line.match(/^Info: Server version '(.+?)'/)
    login_event = line.match(/^Info: Client '(.+?)' <.> \(.+?\) connected$/)
    logout_event = line.match(/^Info: Client '(.+?)' <.> \(.+?\) disconnected$/)
    world_event = line.match(/^Info: Loading world db for world (.+?)$/)
    unworld_event = line.match(/^Info: Shutting down world (.+?)$/)

    if version_event
      puts "Server version: #{version_event[1]}"
      @version = version_event[1]
      update_status!

    elsif login_event
      puts "#{login_event[1]} connected at #{time}"
      @offline_players.delete_if { |pl| pl[:name] == login_event[1] }

      @online_players.push({
        name: login_event[1],
        connected_at: time
      })

    elsif logout_event
      puts "#{logout_event[1]} disconnected at #{time}"
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

  def read_logs!
    @log = File.open(@log_path)
    @log.extend(File::Tail)

    @log.tail do |line|
      parse_line!(line)
    end
  end
end

panel = StarboundPanel.new(ARGV[0])

Thread.new do
  begin
    panel.read_logs!
  rescue Exception => e
    puts e.message
    puts e.backtrace.join("\n")
  end
end

helpers ActionView::Helpers::DateHelper

get '/' do
  panel.update_status!
  panel.instance_variables.each do |var|
    instance_variable_set var, panel.instance_variable_get(var)
  end
  erb :index
end
