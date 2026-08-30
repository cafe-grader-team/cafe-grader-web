class Problem < ApplicationRecord
  include Auditable
  audited only: %i[name full_name full_score available live_dataset_id
                   view_testcase view_submission allow_hint
                   permitted_lang submission_filename task_type compilation_type
                   viva_daily_limit viva_prompt viva_soft_cap viva_hard_cap],
          redact: %i[viva_prompt]

  # -- fields --
  # how the submission should be compiled
  enum :compilation_type, { self_contained: 0,
                            with_managers:  1,
                            viva_exam:      2 }
  enum :task_type, { batch: 0 }

  # belongs_to :description

  # -- association --
  has_and_belongs_to_many :contests, uniq: true

  # has_and_belongs_to_many :groups
  has_many :groups_problems, class_name: 'GroupProblem', dependent: :destroy
  has_many :groups, through: :groups_problems

  has_many :contests_problems, class_name: 'ContestProblem', dependent: :destroy
  has_many :contests, through: :contests_problems

  has_many :problems_tags, class_name: 'ProblemTag', dependent: :destroy
  has_many :tags, through: :problems_tags
  has_many :public_tags, -> { where(public: true) }, class_name: 'Tag', through: :problems_tags, source: :tag

  has_many :test_pairs, dependent: :delete_all

  # testcase is all the testcases
  has_many :testcases, dependent: :destroy

  has_many :submissions, dependent: :destroy
  has_one :problem_stat, dependent: :destroy

  has_many :comments, as: :commentable, dependent: :destroy

  # This allows you to get all comment reveals for comments belonging to this problem
  has_many :comment_reveals, through: :comments

  has_many :datasets, dependent: :destroy
  belongs_to :live_dataset, class_name: 'Dataset', optional: true

  # -- validations --
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_format_of :name,
    with: /\A[a-zA-Z\d\-\_\[\]()]+\z/,
    message: 'contains invalid characters. Only letters, numbers, <code>( )</code>, <code>[ ]</code>, <code>-</code> and <code>_</code> are allowed.'.html_safe

  validates_presence_of :full_name

  # viva_soft_cap / viva_hard_cap are NOT NULL columns with defaults (10/15);
  # unconditional so a blanked form field surfaces as a form error instead of
  # an ActiveRecord::NotNullViolation 500, and 0 can't force-finish a viva on
  # its very first answer (VivaSessionsController#answer hard-caps on this).
  validates :viva_soft_cap, :viva_hard_cap, numericality: {only_integer: true, greater_than: 0}

  # Context-based viva policy (2026-07-21 design, Phase A): nil falls back to
  # GraderConfiguration['viva.practice_daily_start_limit']; 0 is meaningful
  # (contest-only) and must remain a valid, distinct value from nil/blank —
  # never coerce it away with a presence-style validation.
  validates :viva_daily_limit, numericality: {only_integer: true, greater_than_or_equal_to: 0, allow_nil: true}


  # -- callback --
  # Blank and nil must collapse to one canonical value (nil) — otherwise every
  # form save of a non-viva problem (which still submits the hidden viva_prompt
  # field as "") churns viva_prompt nil -> "" and writes a redundant [redacted]
  # audit row on every save.
  before_validation { self.viva_prompt = viva_prompt.presence }

  after_save :generate_and_attach_pdf_statement_later, if: :should_generate_pdf?

  # -- scope --
  scope :available, -> { where(available: true) }

  # These group_xxx scopes ALWAYS take groups into account
  # REGARDLESS of the group mode configuration
  # It also NEGLECT admin privileges, i.e., you won't get any special treatment if you are an admin
  #
  # Please use User.problems_for_action if you want config and admin to be taken into account

  # return problems that is enabled and is in an enabled group that has the given user
  # this does not check whether the user is enabled
  #
  # please use User#problems_for_action when we want to consider everything
  scope :group_submittable_by_user, ->(user_id) {
    joins(groups_problems: {group: :groups_users})
      .where(available: true)                   # available problems only
      .where('groups.enabled': true)            # groups is enabled
      .where('groups_users.user_id': user_id)   # user is in the group
      .where('groups_users.enabled': true)      # user in the group is enabled
      .where('groups_problems.enabled': true)   # problem is enabled
      .distinct(:id)                            # get distinct
  }

  # EDITOR = group-scoped content curator. An editor sees EVERY problem in a
  # group they edit, regardless of Problem#available, Group#enabled, or
  # GroupProblem#enabled — the group-scoped analogue of an admin's Problem.all,
  # minus user management. This lets an editor manage a finished (archived) or
  # not-yet-available (draft) problem in their own group; the old scope required
  # available: true, which silently locked editors out of their own drafts.
  # GroupUser#enabled is NOT ignored: a disabled membership row is not an
  # editor at all (intended design, 2026-08-22) — matching the group-level
  # Group.editable_by_user, which always required an enabled row.
  scope :group_editable_by_user, ->(user_id) {
    joins(groups_problems: {group: :groups_users})
      .where('groups_users.user_id': user_id)   # user is in the group
      .where('groups_users.enabled': true)      # ...with an enabled membership
      .where('groups_users.role': 'editor')     # ...as an editor
      .distinct
  }

  # REPORTER = read-only on LIVE content: available problems in an enabled group.
  # The report set is the editor set (curators see everything, incl. archived /
  # unavailable) UNIONed with the reporter-gated set, so "editor >= reporter"
  # holds everywhere. GroupProblem#enabled is intentionally ignored for both (a
  # problem disabled within a group is a student-only hide; staff still report).
  # GroupUser#enabled is NOT ignored: a reporter is "a member with extra sight",
  # so a disabled membership row revokes the reporter's sight the same way it
  # revokes a member's (intended design, 2026-08-22).
  scope :group_reportable_by_user, ->(user_id) {
    reporter_gated = Problem.joins(groups_problems: {group: :groups_users})
      .where(available: true)                   # available problems only
      .where('groups.enabled': true)            # groups is enabled
      .where('groups_users.user_id': user_id)   # user is in the group
      .where('groups_users.enabled': true)      # ...with an enabled membership
      .where('groups_users.role': 'reporter')   # ...as a reporter
    Problem.where(id: Problem.group_editable_by_user(user_id))
           .or(Problem.where(id: reporter_gated))
  }

  # These contest_xxx scope ALWAYS take contest into account
  # REGARDLESS of the contest mode configuration
  # It also NEGLECT admin privileges, i.e., you won't get any special treatment if you are an admin
  #
  # Please use User.problems_for_action if you want config and admin to be taken into account
  #
  # This returns all Problem that is submittable by the user in a contest
  scope :contests_problems_for_user, ->(user_id) {
    now = Time.zone.now
    joins(contests_problems: {contest: :contests_users})
      .where(available: true)                   # available problems only
      .where('contests.enabled': true)          # contests is enabled
      .where('contests_users.user_id': user_id) # user is in the contest
      .where('contests_users.enabled': true)    # user in the contest is enabled
      .where('contests_problems.enabled': true) # problem is enabled
      .where('ADDTIME(contests.start,-contests_users.start_offset_second) <= ?', now)
      .where('ADDTIME(contests.stop,contests_users.extra_time_second) >= ?', now)
      .group('problems.id')
  }

  # return all problem that the user has "editing" rights in a contest
  #   if the user is an editor of the contest, they can always see the problems
  #   even if the contest is not "enabled"
  scope :contests_editable_problems_for_user, ->(user_id) {
    joins(contests_problems: {contest: :contests_users})
      .where(available: true)                   # available problems only
      .where('contests.enabled': true)          # contests is enabled
      .where('contests_users.user_id': user_id) # user is in the contest
      .where('contests_users.enabled': true)    # user in the contest is enabled
      .where('contests_users.role': 'editor')   # user must have 'editor' role
      .distinct('problems.id')
  }

  scope :default_order, -> {
    if GraderConfiguration.contest_mode?
      order('MIN(contests_problems.number)')
    else
      order(date_added: :desc).order(:name)
    end
  }

  DEFAULT_TIME_LIMIT = 1
  DEFAULT_MEMORY_LIMIT = 32

  # attachment here are the public one,
  # if the user has the right to submit, the user can see the attachments (and statement)
  has_one_attached :statement
  has_one_attached :generated_statement # statement generated from the description
  has_one_attached :attachment  # this is public files seen by contestant

  has_and_belongs_to_many :grounding_materials

  def set_default_value
  end

  # Shared examiner persona layer (design D6). Ordered by name so multi-tag
  # concatenation is deterministic.
  def viva_conduct_tags
    tags.where(kind: :viva_conduct).order(:name)
  end

  # Required-section markers the per-problem examiner briefing
  # (problems.viva_prompt) must contain.
  VIVA_PROMPT_REQUIRED_SECTIONS = {
    /^#+\s*Rubric\b/im => "a section starting with '# Rubric' (or ##/###)"
  }.freeze

  # Whether the problem's statement PDF (or external description URL) is
  # appropriate to show to students. False for viva problems — the PDF is
  # the interviewer's brief, not student-facing material, and revealing
  # it would defeat the interview. Instructors / admins bypass this via
  # User#can_view_problem_pdf?, which short-circuits on edit/report
  # access before consulting this method.
  def pdf_visible_to_student?
    !viva_exam?
  end

  # Returns an array of human-readable error strings if the problem isn't
  # set up correctly to run a viva — empty array means good to go. Called
  # from VivaSessionsController#start before any LLM work happens, so the
  # student gets a clear flash message instead of the viva starting in a
  # half-configured state.
  def viva_setup_errors
    return [] unless viva_exam?
    errors = []

    prompt = viva_prompt.to_s
    if prompt.strip.blank?
      errors << "Problem has a blank examiner briefing (viva_prompt)"
    else
      VIVA_PROMPT_REQUIRED_SECTIONS.each do |pattern, label|
        errors << "examiner briefing is missing #{label}" unless prompt =~ pattern
      end
    end

    errors
  end

  def viva_setup_valid?
    viva_setup_errors.empty?
  end

  def can_view_testcase
    GraderConfiguration.show_testcase && self.view_testcase
  end

  def get_jschart_history
    start = 4.month.ago.beginning_of_day
    start_date = start.to_date
    count = Submission.regular.where(problem: self).where('submitted_at >= ?', start).group('DATE(submitted_at)').count
    i = 0
    label = []
    value = []
    while start_date + i < Time.zone.now.to_date
      if (start_date+i).day == 1
        # label << (start_date+i).strftime("%d %b %Y")
        # label << (start_date+i).strftime("%d")
      else
        # label << ' '
        # label << (start_date+i).strftime("%d")
      end
      label << (start_date+i).strftime("%d-%b")
      value << (count[start_date+i] || 0)
      i+=1
    end
    return {labels: label,
            datasets: [label: 'sub', data: value, backgroundColor: 'rgba(54, 162, 235, 0.2)', borderColor: 'rgb(75, 192, 192)']}
  end

  def get_next_dataset_name(base = 'Dataset')
    num = 1
    name = base + " #{num}"
    while datasets.where(name: name).count > 0
      num += 1
      name = base + " #{num}"
    end
    return name
  end


  def self.download_file_basedir
    return "#{Rails.root}/data/tasks"
  end

  def get_submission_stat
    result = Hash.new
    # total number of submission
    result[:total_sub] = Submission.regular.where(problem_id: self.id).count
    result[:attempted_user] = Submission.regular.where(problem_id: self.id).group(:user_id)
    result[:pass] = Submission.regular.where(problem_id: self.id).where("points >= ?", 100).count
    return result
  end

  def long_name
    "[#{name}] #{full_name}"
  end

  # ------------------------
  # -- HINT section begin --
  # ------------------------
  def hints
    comments.where(kind: :hint)
  end

  # indicate weather this problem has a helper (hints, comments)
  def helpers?
    hints.any?
  end

  # return a records of all comment with the reveal status
  # to get all hints, we can use comment_with_reveal_status(user,kind: 'hint')
  def comments_with_reveal_status(user, kind: nil)
    query = comments
    query = query.where(kind: kind) if kind.present?
    query.select('comments.*', "EXISTS(SELECT 1 FROM comment_reveals WHERE user_id = #{user.id} AND comment_id = comments.id) AS is_acquired")
  end

  # this method is used both in acquiring and viewing
  def comment_reveal_prerequisite_satisfied?(comment, user)
    case comment.kind
    when 'hint'
      # user want to reveal a hint

      # check if the problem allow hint
      return false unless self.allow_hint?

      # check if the user has the right to the problem
      return false unless user.problems_for_action(:submit).where(id: self).any?

      # if the current mode is a contest, also check the contest
      if GraderConfiguration.contest_mode?
        # TODO: this is WRONG, need to check actual active time
        return false unless self.contests.enabled.where(allow_hint: true).any?
      end

      # pass all checks
      return true
    else
      false
    end
  end

  def helpers_cost(user,contest)
    Comment.cost_summary_for(user,contest)
  end

  # return the enabled comments of the specified *kind* that are revealed by *user*
  def revealed_comments_for_user(user, kind)
    commens.joins(:comment_reveals).where(enabled: true, comment_reveals: {user: user, kind: kind})
  end
  # ----------------------
  # -- HINT section end --
  # ----------------------

  # ids_string is something like ['1','3','7']
  # which correspond to the submitted value from  select2 multiple selection
  def set_permitted_lang_from_ids_string(ids_string)
    lang_names = ids_string.reject(&:empty?).map { |x| Language.find(x.to_i).name }.join(' ')
    self.permitted_lang = lang_names
  end

  # return ids array of permitted lang
  # if permitted_lang is blank, show nil
  def get_permitted_lang_as_ids(when_blank: Language.order(:id).ids)
    return when_blank if self.permitted_lang.blank?
    return Language.where(name: self.permitted_lang.split(' ').uniq).order(:id).ids
  end

  # this function return a content generated for "all_tests.cfg"
  # from the legacy code (Aj. Pong's)
  # This is definitely not complete but it works in general cases
  def build_legacy_config_file
    default = {
      time_limit: 1.0,
      mem_limit: 512,
      score: 10
    }

    result = ["problem do"]
    result << "  num_tests #{testcases.count}"
    result << "  full_score #{testcases.count}"
    result << "  time_limit_each #{default[:time_limit]}"
    result << "  mem_limit_each #{default[:mem_limit]}"
    result << "  score_each #{default[:score]}"
    result << ""

    testcases.order(:num).each do |tc|
      result << "  run #{tc.num} do"
      result << "    tests #{tc.num}"
      result << "    scores #{tc.score}"
      result << "  end"
      result << ""
    end

    result << "end\n"
    return result.join "\n"
  end

  def self.check_name(replace: false, with: '')
    Problem.find_each do |problem|
      unless problem.valid?
        puts "Problem #{problem.id}: [#{problem.name}] is invalid"
      end
    end
  end


  # TODO: change to language specific
  def exec_filename(language)
    case language.name
    when 'cpp'
      'a.out'
    when 'python'
      'cafe_code.py'
    when 'java', 'digital'
      # for java, the compilation create a shell script that runs the file
      'run.sh'
    else
      'submission'
    end
  end

  # export the problem into the given dir (default: judge dump dir)
  def export(all_datasets: false, base_dir: Rails.root.join('../judge/dump'), zip: true)
    pe = ProblemExporter.new
    pe.export_problem_to_dir(self, base_dir: base_dir, zip: zip, all_datasets: all_datasets)
  end

  def regenerate_pdf_statement!
    ProblemPdfGenerator.new(self).call
  end

  # -- private section --
  # The group to pre-pick when deep-linking from this problem's stat page into
  # the Best Score report (ProblemsHelper#problem_score_report_path), chosen
  # among the groups this problem is live in that `user` may report on:
  #
  #   1. a live (non-archived) group whose members have submitted it — the
  #      current section of a running course; most submissions, then newest;
  #   2. otherwise the group whose members submitted it the most, archived
  #      included — the cohort an old exam problem was actually used in
  #      (yearly sections get archived, but that is where the data lives);
  #   3. otherwise the newest live group (nobody has submitted yet).
  #
  # Returns nil when there is no candidate at all.
  def report_group_for(user)
    candidates = user.groups_for_action(:report)
                     .where(id: groups.where(groups_problems: { enabled: true }).select(:id))
                     .to_a
    return nil if candidates.empty?

    sub_counts = Submission.regular.where(problem_id: id)
                           .joins(user: :groups_users)
                           .where(groups_users: { group_id: candidates.map(&:id), enabled: true })
                           .group('groups_users.group_id').count
    candidates.max_by do |g|
      subs = sub_counts.fetch(g.id, 0)
      tier = if g.enabled && subs > 0 then 2 elsif subs > 0 then 1 else 0 end
      [tier, subs, g.enabled ? 1 : 0, g.id]
    end
  end

  private

  def should_generate_pdf?
    return false if viva_exam?   # D5: the description IS the scenario; no side-PDF for vivas

    (new_record? || saved_change_to_attribute?(:description)) && description.present?
  end

  def generate_and_attach_pdf_statement_later
    # Pass the entire object to the job, not just the ID.
    # This avoids another database query in the job if the object is simple.
    # For very large objects, passing the ID is better: perform(self.id).
    CreateProblemPdfJob.perform_later(self)
  end
end
