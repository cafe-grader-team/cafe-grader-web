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

require 'rubygems'
require 'uri'

class Visitor

  attr_accessor :talkative

  class << self
    attr_accessor :commands
    attr_accessor :base_url
    attr_accessor :cookies_stored
  end

  def get_cookie_fname
    "#{@base_dir}/cookies.#{@id}"
  end

  def get_output_fname
    "#{@base_dir}/output.#{@id}"
  end

  def id
    @id
  end

  def initialize(id=0, base_dir='.')
    # initialize nil class variable
    self.class.base_url = "" if (self.class.base_url) == nil
    self.class.cookies_stored = false if self.class.cookies_stored == nil

    @id = id
    @base_dir = base_dir
    @cookies_fname = get_cookie_fname
    @output_fname = get_output_fname
    @statistics = Array.new
    @talkative = false

    @stopped = false
  end

  def cleanup
    trial = 0
    while FileTest.exists?(@cookies_fname)
      File.delete(@cookies_fname) 
      if FileTest.exists?(@cookies_fname)
        # wait until system returns
        puts "STILL HERE"
        sleep 1
        trial += 1
        break if trial>10
      end
    end 
    
    while FileTest.exists?(@output_fname)
      File.delete(@output_fname)
      if FileTest.exists?(@output_fname)
        # wait until system returns
        sleep 1
        trial += 1
        break if trial>10
      end
    end 
  end

  def self.site_url(url)
    self.base_url = url
  end

  def self.stores_cookies
    self.cookies_stored = true
  end

  def self.preprocess_param_hash(params)
    return {} if params==nil
    plist = {}
    params.each do |key,val|
      if key.is_a? Symbol
        key_s = key.to_s
      else
        key_s = key
      end
      plist[key_s] = val
    end
    plist
  end

  def self.get(url,params=nil)
    self.commands = [] if self.commands==nil
    self.commands << { 
      :command => :get, 
      :url => url, 
      :params => Visitor.preprocess_param_hash(params) }
  end

  def self.post(url,params=nil,options=nil)
    self.commands = [] if self.commands==nil
    self.commands << { :command => :post,
      :url => url, 
      :params => Visitor.preprocess_param_hash(params), 
      :options => options }
  end

  def substitute_id(st)
    return st if !(st.is_a? String)
    st.gsub(/(()|(\$))\$\{id\}/) do |s|
      if s=="${id}"
        @id.to_s
      else
        "${id}"
      end
    end
  end

  def encode_params(params)
    enc = ""
    if params!=nil and params.length!=0
      params.each do |key,val|
        if enc != ""
          enc += '&'
        end
        val = substitute_id(val)
        enc += URI.escape(key) + '=' + URI.escape(val.to_s)
      end
    end
    enc
  end

  def get(url,params)
    #build url

    #puts "----------------------cookies-----------"
    #system("cat #{@cookies_fname}")
    #puts "----------------------cookies-----------"

    full_url = "#{self.class.base_url}#{url}"
    if params!=nil and params.length!=0
      full_url += '?' + encode_params(params)
    end
    
    cmd = "curl -k -b #{@cookies_fname} -D #{@cookies_fname} #{full_url} " +
      " -s -L -o #{@output_fname}"
    #puts ">>>>>>>>>>>>>>>>>> " + cmd
    system(cmd)
    #system("cat #{@output_fname}")
  end

  def post(url,params,options)
    #puts "----------------------cookies-----------"
    #system("cat #{@cookies_fname}")
    #puts "----------------------cookies-----------"

    full_url = "#{self.class.base_url}#{url}"
    params_str = ""
    if options!=nil and options[:multipart]==true
      params.each do |key,val|
        if val.is_a? Hash
          case val[:type]
          when :file
            dval = substitute_id(val[:data])
            params_str += " -F \"#{key}=@#{dval.to_s}\""
          end
        else
          val = substitute_id(val)
          params_str += " -F \"#{key}=#{URI.escape(val.to_s)}\""
        end
      end
    else
      params_str += "-d \"#{encode_params(params)}\""
    end

    #puts params_str

    cmd = "curl -L -k -b #{@cookies_fname} -D #{@cookies_fname} " +
      " #{params_str} #{full_url} -s -o #{@output_fname}"
    #puts ">>>>>>>>>>>>>>>>>>>>>>>>>>> POST: " + cmd
    system(cmd)
    #system("cat #{@output_fname}")
  end

  def stop!
    @stopped = true
  end

  def run(times=nil, options={})
    times = 1 if times == :once

    @stopped = false
    while times!=0
      self.class.commands.each do |cmd|
        puts "#{@id}: #{cmd[:command]} #{cmd[:url]}" if @talkative

        start_time = Time.new

        if !options[:dry_run]
          case cmd[:command]
          when :get
            get cmd[:url], cmd[:params]
          when :post
            post cmd[:url], cmd[:params], cmd[:options]
          end
        end

        finish_time = Time.new

        break if @stopped

        @statistics << {
          :url => "#{cmd[:command]}:#{cmd[:url]}",
          :time => finish_time - start_time }
      end

      times -= 1 if times.is_a? Integer    #otherwise, run forever

      break if @stopped
    end
  end

  def show_raw_stat
    @statistics.each do |stat|
      puts "#{stat[:url]} => #{stat[:time]}"
    end
  end

  def statistics
    num_requested = @statistics.length
    totaltime = 0.0
    @statistics.each { |stat| totaltime += stat[:time] }

    if num_requested>0
      average_request_time = totaltime / num_requested
    else
      average_request_time = 0
    end

    sq_sum = 0.0
    @statistics.each do |stat| 
      sq_sum += (stat[:time]-average_request_time) ** 2
    end
    if num_requested>1
      sd = Math.sqrt(sq_sum/(num_requested-1))
    else
      sd = 0
    end

    return {
      :num_requested => num_requested,
      :avg_request_time => average_request_time,
      :std_dev => sd
    }
  end
end

def visitor(cname,&blk)
  c = Class.new(Visitor)
  begin
    Object.const_set(cname,c)
  rescue NameError
    puts <<ERROR
Error on type #{cname}.
Type name should be capitalized and follow Ruby constant naming rule.
ERROR
    exit(0)
  end
  c.instance_eval(&blk)
end
