# Server-side markdown rendering for the markdown-editor Stimulus controller's
# Preview pane (app/javascript/controllers/markdown_editor_controller.js).
class MarkdownController < ApplicationController
  before_action :check_valid_login
  before_action :group_editor_authorization

  # POST /markdown/preview  (param: text)  -> HTML fragment
  #
  # Renders through ApplicationHelper#safe_markdown: the same Redcarpet stack
  # as the rest of the app, with tables/autolink/strikethrough on (rubrics use
  # tables) and raw HTML filtered — the text is the caller's own draft echoed
  # back, but a pasted PDF extraction could still carry stray tags. Editors
  # only: every form that mounts the editor is at least editor-gated.
  def preview
    render html: helpers.safe_markdown(params[:text].to_s), layout: false
  end
end
