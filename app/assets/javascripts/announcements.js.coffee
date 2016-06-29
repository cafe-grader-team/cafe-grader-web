#js for announcement
$ ->
  $(document).ajaxError (event, jqxhr, settings, exception) ->
    if jqxhr.status
      alert 'We\'re sorry, but something went wrong (' + jqxhr.status + ')'
    return
