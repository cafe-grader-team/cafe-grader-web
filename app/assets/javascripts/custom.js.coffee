$(document).on 'change', '.btn-file :file', ->
  input = $(this)
  numFiles = if input.get(0).files then input.get(0).files.length else 1
  label = input.val().replace(/\\/g, '/').replace(/.*\//, '')
  input.trigger 'fileselect', [
    numFiles
    label
  ]
  return


# document ready

$ ->
  $(".select2").select2()
  #$(".bootstrap-switch").bootstrapSwitch()
  $(".bootstrap-toggle").bootstrapToggle()
  $('.btn-file :file').on 'fileselect', (event, numFiles, label) ->
    input = $(this).parents('.input-group').find(':text')
    log = if numFiles > 1 then numFiles + ' files selected' else label
    if input.length
      input.val log
    else
      if log
        alert log
    return
  return
