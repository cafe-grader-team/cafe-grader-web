$ ->
  $("#submission_problem_go").on 'click', (event) ->
    url = $("#submission_problem_id").val()
    if (url)
      window.location = url

