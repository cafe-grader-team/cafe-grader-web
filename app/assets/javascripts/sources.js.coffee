# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://jashkenas.github.com/coffee-script/


$ ->
  $("#live_submit").on "click", (event) ->
    h = $("#editor_text")
    e = ace.edit("editor")
    h.val(e.getValue())
