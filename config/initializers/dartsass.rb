Rails.application.config.dartsass.builds = {
  "application.sass.scss" => "application.css"
}

Rails.application.config.dartsass.build_options << "--load-path=vendor"
