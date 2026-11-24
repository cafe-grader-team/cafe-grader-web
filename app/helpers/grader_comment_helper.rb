# Renders Submission#grader_comment — the per-testcase verdict string
# ("PP-T", "P[PPPP][PP-]", …; one letter per testcase in
# Dataset#testcases.display_order, see CLAUDE.md "Submission") — as a strip
# of colour-coded tiles, one per testcase, with each `[...]` group drawn as a
# box. Anything that is not a well-formed verdict string (free text such as
# "No testcase", checker messages like "[uses 80 parrots]", grader-error
# prose, nested or unbalanced brackets) falls back to the plain monospace
# rendering the list has always used, width-capped so it cannot widen the
# column either.
module GraderCommentHelper
  # letter → Evaluation result name. Derived from the model's own table so
  # there is one source of truth: Evaluation::RESULT_CODE is indexed by the
  # enum value ("?" → waiting, "P" → correct, "-" → wrong, …).
  VERDICT_RESULTS = Evaluation::RESULT_CODE.each_with_index.to_h { |code, i| [code, Evaluation.results.key(i)] }.freeze
  VERDICT_LETTERS = Regexp.escape(VERDICT_RESULTS.keys.join).freeze
  # Flat, balanced, non-empty groups only. Nesting and empty groups never
  # occur in practice (0 of 24k grouped comments in the 2026-08 prod dump).
  VERDICT_STRING_RE = /\A(?:[#{VERDICT_LETTERS}]+|\[[#{VERDICT_LETTERS}]+\])+\z/
  VERDICT_TOKEN_RE  = /\[([#{VERDICT_LETTERS}]+)\]|([#{VERDICT_LETTERS}]+)/

  GROUP_HINT = "Tests in a box are scored together — the box earns the lowest score inside it.".freeze

  # style: nil follows the viewer's preference (User#verdict_display via
  # Current.user); :tiles / :plain force one rendering (used by the profile
  # page samples). A plain-by-preference verdict keeps the pre-4.5 markup:
  # uncapped .grader-comment.text-break, unlike the width-capped free-text
  # fallback above.
  def grader_comment_strip(comment, style: nil)
    comment = comment.to_s
    return grader_comment_plain(comment) unless comment.match?(VERDICT_STRING_RE)

    style ||= Current.user&.verdict_plain? ? :plain : :tiles
    return grader_comment_plain(comment, capped: false) if style == :plain

    total   = comment.delete("[]").length
    groups  = comment.count("[")
    index   = 0
    group_i = 0
    parts = comment.scan(VERDICT_TOKEN_RE).map do |grouped, loose|
      run = grouped || loose
      tiles = run.each_char.map do |code|
        index += 1
        content_tag(:span, code, class: "verdict-tile verdict-#{VERDICT_RESULTS[code]}",
                                 title: "Test #{index} of #{total}: #{verdict_word(code)}")
      end
      if grouped
        group_i += 1
        content_tag(:span, safe_join(tiles), class: "verdict-group",
                    title: "Group #{group_i} of #{groups}: #{run.count('P')}/#{run.length} passed. #{GROUP_HINT}")
      else
        content_tag(:span, safe_join(tiles), class: "verdict-run")
      end
    end
    content_tag(:span, safe_join(parts), class: "verdict-strip", data: { comment: comment })
  end

  # Human word for a verdict letter, from the same locale keys the Evaluation
  # Details modal uses (activerecord.attributes.evaluation.results.*).
  def verdict_word(code)
    result = VERDICT_RESULTS.fetch(code)
    t(result, scope: "activerecord.attributes.evaluation.results", default: result.to_s.humanize)
  end

  # Letter map + group hint for the client-side twin (app/javascript/verdict_strip.js),
  # used where DataTables renders cells from JSON (report/submission). Keeps the
  # letter → result/word table in one place. Safe to interpolate into a <script>.
  def verdict_strip_config_json
    codes = VERDICT_RESULTS.to_h { |code, result| [code, { result: result, word: verdict_word(code) }] }
    ERB::Util.json_escape({ codes: codes, group_hint: GROUP_HINT, plain: !!Current.user&.verdict_plain? }.to_json).html_safe
  end

  def grader_comment_plain(comment, capped: true)
    classes = capped ? "grader-comment grader-comment-capped" : "grader-comment text-break"
    content_tag(:span, " [#{comment}]", class: classes)
  end
end
