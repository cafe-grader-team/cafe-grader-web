#js for announcement
$ ->
  $('.ajax-toggle').on 'click', (event) ->
    console.log event.target.id
    target = $(event.target)
    target.removeClass 'btn-default'
    target.removeClass 'btn-success'
    target.addClass 'btn-warning'
    target.text '...'
    return

  $(document).ajaxError (event, jqxhr, settings, exception) ->
    if jqxhr.status
      alert 'We\'re sorry, but something went wrong (' + jqxhr.status + ')'
    return
