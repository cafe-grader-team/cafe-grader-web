module AnnouncementsHelper
  # An announcement body longer than this (as plain text) gets a clamped
  # preview with a "Read More" modal.
  ANNOUNCEMENT_PREVIEW_LIMIT = 150

  # Decide whether the body preview should clamp and offer "Read More".
  # Plain-text length is only the heuristic — the preview itself renders the
  # markdown unmodified and clamps visually with CSS (see _body_preview).
  def announcement_preview_clipped?(announcement)
    text = CGI.unescapeHTML(strip_tags(markdown(announcement.body)))
    text.length > ANNOUNCEMENT_PREVIEW_LIMIT
  end
end
