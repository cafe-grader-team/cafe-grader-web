#
# This file is part of a web load testing tool (currently having no name) 
# Copyright (C) 2008 Jittat Fakcharoenphol
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.
#

require 'visitor_curl_cli'

TEMP_DIR = './tmp'

def show_usage
  puts <<USAGE
using: ruby runner.rb <visitor_file> [<type> <number>] [<type> <number>] ... [options]
  * visitor_file : your visitor definition file, (with or without .rb)
  * type, number : the type and the number of visitors of that type
  * options      : any of the following
                     -t <sec>   specify how long (in seconds)
                     -d         dry-run: run, but make no real http requests
USAGE
end

def initialize_temp_dir
  if !FileTest.exists? TEMP_DIR
    Dir.mkdir TEMP_DIR
  end
end

def runner(visitor_lists, load_time=60, options={})
  visitors = []
  vcount = 0

  visitor_lists.each do |cname, num|
    begin
      c = Kernel.const_get(cname)

      num.times do
        visitors[vcount] = c.new(vcount+1, TEMP_DIR)
        visitors[vcount].talkative = true
        vcount += 1
      end
    rescue NameError
      puts "Can't find class #{cname}"
      show_usage
      exit(0)
    end
  end

  puts "Having #{vcount} visitors"

  vthread = []

  all_start_time = Time.new

  # start all visitors
  vcount.times do |i|
    vthread[i] = Thread.new do
      visitors[i].run(:forever,options)
    end
  end

  # wait for load_time seconds
  sleep load_time

  visitors.each do |visitor| visitor.stop! end

  all_finish_time = Time.new

  begin
    # wait for all threads to stop
    vcount.times do |i|
      #puts "Waiting for thread #{i}, #{vthread[i].alive?}"
      vthread[i].join 
    end

  rescue Interrupt
    # kill all remaining threads
    vcount.times do |i|
      vthread[i].kill if vthread[i].alive?
    end
  end

  # clean up
  visitors.each do |visitor| 
    #puts "Clean up: #{visitor.id}"
    visitor.cleanup 
  end

  #all_finish_time = Time.new

  total_req = 0

  vcount.times do |i|
    stat = visitors[i].statistics
#    puts "TYPE: #{visitors[i].class}"
#    puts "Total requested = #{stat[:num_requested]}"
#    puts "Average = #{stat[:avg_request_time]}"
#    puts "S.D. = #{stat[:std_dev]}"
    total_req += stat[:num_requested]
  end

  elapsed_time = all_finish_time - all_start_time

  puts
  puts "Total time = #{elapsed_time} sec."
  puts "Total requests = #{total_req}"
  puts "Trans. per sec = #{total_req/elapsed_time}"
end

###########################
# MAIN
###########################

if ARGV.length==0
  show_usage
  exit(0)
end

visitor_file = ARGV.shift
require visitor_file

load_time = 60
dry_run = false

#build visitor list
visitor_list = {}
while ARGV.length>0
  key = ARGV.shift

  case key
  when '-d'
    dry_run = true
  when '-t'
    num = ARGV.shift.to_i
    load_time = num
  else
    num = ARGV.shift.to_i
    visitor_list[key] = num
  end
end

initialize_temp_dir
runner visitor_list, load_time, {:dry_run => dry_run}

