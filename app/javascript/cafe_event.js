//global initialization

$(document).on('change', '.btn-file :file', function() {
  var input, label, numFiles;
  input = $(this);
  numFiles = input.get(0).files ? input.get(0).files.length : 1;
  label = input.val().replace(/\\/g, '/').replace(/.*\//, '');
  input.trigger('fileselect', [numFiles, label]);
});

//make select2 focus on search box
//see https://stackoverflow.com/questions/25882999/set-focus-to-search-text-field-when-we-click-on-select-2-drop-down
$(document).on('select2:open', (e) => {
  const selectId = e.target.id
  $(".select2-search__field[aria-controls='select2-" + selectId + "-results']").each(function (
      key,
      value,
  ){
      value.focus();
  })
})

$('.btn-file :file').on('fileselect', function(event, numFiles, label) {
  var input, log;
  input = $(this).parents('.input-group').find(':text');
  log = numFiles > 1 ? numFiles + ' files selected' : label;
  if (input.length) {
    input.val(log);
  } else {
    if (log) {
      alert(log);
    }
  }
});

$('.ajax-toggle').on('click', function(event) {
  var target;
  target = $(event.target);
  target.removeClass('btn-default');
  target.removeClass('btn-success');
  target.addClass('btn-warning');
  target.text('...');
});


