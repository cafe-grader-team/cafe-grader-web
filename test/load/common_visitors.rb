if !defined? VISITOR_OPTION_LIST
  VISITOR_OPTION_LIST = {}
end

visitor "FirstPageViewer", VISITOR_OPTION_LIST do
  stores_cookies
  get "/"
end
