//main entry point for sprocket
// following lines are very important, it loads several javascript files BEFORE import map
//= re quire jquery3
//= re quire popper
//= re quire bootstrap-sprockets
//= re quire moment
//= re quire moment/th
//= re quire ace-rails-ap
//= re quire ace/mode-c_cpp
//= re quire ace/mode-python
//= re quire ace/mode-ruby
//= re quire ace/mode-pascal
//= re quire ace/mode-javascript
//= re quire ace/mode-java
//= re quire ace/theme-merbivore
 
// -- AGAIN -- this javascript is loaded first, before any import_map
// because it is loaded via javascript_include_tag (which is sprocket)

//TODO: should move this one into another .js that is loaded via sprocket

// window.jquery = jQuery
function sleep(ms) {
  return (new Promise(resolve => setTimeout(resolve, ms))).then( () => {} );
}
