# Pin npm packages by running ./bin/importmap

# entry point
pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/mixins", under: "mixins"

# datatable
# I have to fix vfs_font.js for this to work
pin "datatables", to: "datatables/datatables.min.js"
pin "vfs-fonts", to: "datatables/vfs_fonts.js"
pin "pdfmake", to: 'datatables/pdfmake.min.js'

# select2
pin "select2", to: "select2.min.js" # @4.1.0

pin "chart", to: 'chart.umd.js' # @4.4.0 from https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.js
pin "tempus-dominus-js", to: "tempus-dominus/tempus-dominus.js"

# hotwire
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true

# rails usj (should be removed soon)
pin "rails-ujs", to: 'rails-ujs.esm.js'
pin "bootbox", to: 'bootbox.js' # @6.0.0
pin "jquery", preload: true # @3.7.1



# this bootstrap is wgetted from "https://ga.jspm.io/npm:bootstrap@5.3.6/dist/js/bootstrap.esm.js"
# we need the esm version
pin "bootstrap", to: "bootstrap.esm.js"
pin "@popperjs/core", to: "@popperjs-core-esm.js" # @2.11.8

# my local js
pin "cafe_bundle", to: "cafe_bundle.js"
pin "cafe", to: "cafe.js"
pin "cafe_event", to: "cafe_event.js"
pin "cafe_datatable", to: 'cafe_datatable.js'
pin "cafe_turbo", to: "cafe_turbo.js"
pin "setup_jquery"
pin "setup_bootstrap"
pin "setup_select2"
pin "moment" # @2.30.1
pin "ace-builds" # @1.42.0

# --- ace editor pin ---
# pin_all_from does not work so I have to pin each individual files that is required by ace editor
# however, we also have to import all of these as well, see setup_ace
ace_mode = %w[ c_cpp pascal ruby python java rust golang php haskell sql xml ]
ace_theme =%w[ merbivore merbivore_soft dracula ]

ace_mode.each { |mod| pin "ace-mode-#{mod}", to: "ace-noconflict/mode-#{mod}.js" }
ace_theme.each { |theme| pin "ace-theme-#{theme}", to: "ace-noconflict/theme-#{theme}.js" }

pin "highlight", to: 'highlight/highlight.js', preload: true
