# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/


$ ->
  $("#live_submit").on "click", (event) ->
    h = $("#editor_text")
    e = ace.edit("editor")
    h.val(e.getValue())

  $("#language_id").on "change", (event) ->
    text = $("#language_id option:selected").text()
    mode = 'ace/mode/c_cpp'
    switch text
      when 'Pascal' then mode = 'ace/mode/pascal'
      when 'C++','C' then mode = 'ace/mode/c_cpp'
      when 'Ruby' then mode = 'ace/mode/ruby'
      when 'Python' then mode = 'ace/mode/python'
      when 'Java' then mode = 'ace/mode/java'
    editor = ace.edit('editor')
    editor.getSession().setMode(mode)

  e = ace.edit("editor")
  e.setValue($("#text_haha").val())
  e.gotoLine(1)
  $("#language_id").trigger('change')




  return
