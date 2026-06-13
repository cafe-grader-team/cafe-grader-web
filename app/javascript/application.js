// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails



// import Turbo and Stimulus Controller
// Disable Turbo by default
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
Turbo.session.drive = false


// these setup our library
// even we import setup_select2 and setup_bootstrap BEFORE setup_jquery
// everything still work fine because in setup_bootstrap and setup_select2,
// we explicitly import setup_jquery as well, so, the browser knows that they
// must load the setup_jquery first
import "setup_select2"
import "setup_bootstrap"
import "setup_jquery"


// TempusDominus
import "tempus-dominus-js" //this import as tempusDominus
// since this import does not set the window directly, I have to do it
window.tempusDominus = tempusDominus

//too lazy to use the tempusDominus namespace, just use TempusDominus directly
window.TempusDominus = tempusDominus.TempusDominus


// running rails ujs
// this should be phased out??? and replace by turbo / stimulus
import Rails from 'rails-ujs';
Rails.start()


//Import cafe-grader global functions into *cafe* object
import * as cafe from 'cafe_bundle'
window.cafe = cafe



// this bootbox is non-minified version and is edited by dae
// since that version does not support importmap, I have to add 'root = root || window'
import 'bootbox'
import moment from 'moment'
window.moment = moment

// -- IMPORTANT --
// I use highligh.js CommonJS build (not the ES-Build!!!)
// So I have to modify it by adding "export default hljs"
// 
// THIS HAVE TO BE DONE EVERY TIME I REDOWNLOAD THE highlighjs
import hljs from 'highlight'
window.hljs = hljs
