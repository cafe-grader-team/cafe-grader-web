class SizeFilterHandler < Mongrel::HttpHandler

  def initialize(options = {})
    @max_size = options[:max_size] || -1
    @redirect_url = options[:redirect_url]
    @request_notify = true
  end
  
  def request_begins(params)
    @request_too_large = false
    
    # Only operate on POST requests
    return unless params[Mongrel::Const::REQUEST_METHOD] == 'POST'
    
    if params[Mongrel::Const::CONTENT_LENGTH]!=nil
      req_size = params[Mongrel::Const::CONTENT_LENGTH].to_i
      if @max_size!=-1 and req_size > @max_size
        @request_too_large = true
      end
    else
      @request_too_large = true
    end
  end

  def process(request, response)
    if @request_too_large
      if @redirect_url != nil
        response.socket.write(Mongrel::Const::REDIRECT % @redirect_url)
      else
        response.socket.write(Mongrel::Const::STATUS_FORMAT % [403, "Forbidden"])
      end
      response.finished()
    end
  end
end

uri "/", :handler => SizeFilterHandler.new(:max_size => 200_000,
                                           :redirect_url => "/main/list"), 
         :in_front => true
