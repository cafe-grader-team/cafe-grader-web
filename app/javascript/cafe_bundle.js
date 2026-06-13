// this combines several custom export into one big files
// it also runs all event listener setup (in cafe_event.js)
// this should be imported by 
//   import * as cafe from 'cafe_bundle'

export * from 'cafe'
export * from 'cafe_datatable'
export * from 'cafe_turbo'


// setup the event listener
import 'cafe_event'
