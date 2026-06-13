module TurboStreamActionsHelper
  # this allows turbo_stream.bootbox('xxx') to be used
  # in controllers and views
  def bootbox(message)
     turbo_stream_action_tag :bootbox, message: message
  end

end

Turbo::Streams::TagBuilder.prepend(TurboStreamActionsHelper)
