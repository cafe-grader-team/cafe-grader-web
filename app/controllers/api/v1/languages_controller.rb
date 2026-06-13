class Api::V1::LanguagesController < Api::V1::BaseController
  # GET /api/v1/languages
  def index
    languages = Language.all.order(:name)
    render json: languages.map { |l|
      { id: l.id, name: l.name, pretty_name: l.pretty_name, ext: l.ext }
    }
  end
end
