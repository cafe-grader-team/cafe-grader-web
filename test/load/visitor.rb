require 'rubygems'
require 'curb'

class Visitor

  attr_accessor :talkative

  class << self
    attr_accessor :commands
    attr_accessor :base_url
    attr_accessor :cookies_stored
  end

  def initialize(id=0)
    # initialize nil class variable
    puts self.class.base_url
    self.class.base_url = "" if (self.class.base_url) == nil
    self.class.cookies_stored = false if self.class.cookies_stored == nil

    @id = id
    @curl = Curl::Easy.new
    @curl.enable_cookies = self.class.cookies_stored
    @curl.cookiejar = "mycookies"
    @statistics = Array.new
    @talkative = false
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

  def get(url,params)
    #build url
    full_url = "#{self.class.base_url}#{url}"
    if params!=nil and params.length!=0
      full_url += '?'
      params.each do |key,val|
        if full_url.slice(-1..-1)!='?'
          full_url += '&'
        end
        full_url += @curl.escape(key) + '=' + @curl.escape(val)
      end
    end
    @curl.url = full_url
    @curl.http_get
  end

  def post(url,params,options)
    @curl.url = "#{self.class.base_url}#{url}"
    if options!=nil and options[:multipart]==true
      @curl.multipart_form_post = true
    end
    #build post fields
    fields = []
    params.each do |key,val|
      if val.is_a? Hash
        case val[:type]
        when :file
          fields << Curl::PostField.file(key,val[:data])
        end
      else
        fields << Curl::PostField.content(key,val.to_s)
      end
    end
    @curl.http_post *fields
  end

  def run(option=nil)

    if (option==nil) or (option==:once)
      times = 1
    elsif (option==:forever)
      times = -1
    else
      times = option
    end

    while times!=0
      self.class.commands.each do |cmd|
        puts "#{@id}: #{cmd[:command]} #{cmd[:url]}" if @talkative

        start_time = Time.new

        case cmd[:command]
        when :get
          get cmd[:url], cmd[:params]
        when :post
          post cmd[:url], cmd[:params], cmd[:options]
        end

        finish_time = Time.new

        @statistics << {
          :url => "#{cmd[:command]}:#{cmd[:url]}",
          :time => finish_time - start_time }
      end

      if times!=-1  # infinity times
        times -= 1
      end
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

