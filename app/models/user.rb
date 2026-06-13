require 'digest/sha1'
require 'net/pop'
require 'net/https'
require 'net/http'
require 'json'

class User < ApplicationRecord
  has_and_belongs_to_many :roles

  # has_and_belongs_to_many :groups
  has_many :groups_users, class_name: 'GroupUser'
  has_many :groups, through: :groups_users

  has_many :test_requests, -> { order(submitted_at: :desc) }

  has_many :messages, -> { order(created_at: :desc) },
           class_name: "Message",
           foreign_key: "sender_id"

  has_many :replied_messages, -> { order(created_at: :desc) },
           class_name: "Message",
           foreign_key: "receiver_id"

  has_many :logins

  has_many :submissions

  has_one :contest_stat, class_name: "UserContestStat", dependent: :destroy

  belongs_to :site, optional: true
  belongs_to :country, optional: true

  belongs_to :default_language, class_name: 'Language', foreign_key: 'default_language_id', optional: true

  # contest
  has_many :contests_users, class_name: 'ContestUser'
  has_many :contests, through: :contests_users

  # comments
  has_many :comment_reveals
  has_many :revealed_comments, through: :comment_reveals, source: :comment

  scope :activated_users, -> { where activated: true }

  validates_presence_of :login
  validates_uniqueness_of :login
  validates_format_of :login, with: /\A[\_A-Za-z0-9]+\z/
  validates_length_of :login, within: 3..30

  validates_presence_of :full_name
  validates_length_of :full_name, minimum: 1

  validates_presence_of :password, if: :password_required?
  validates_length_of :password, within: 4..50, if: :password_required?
  validates_confirmation_of :password, if: :password_required?

  validates_format_of :email,
                      with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i,
                      if: :email_validation?
  validate :uniqueness_of_email_from_activated_users,
           if: :email_validation?
  validate :enough_time_interval_between_same_email_registrations,
           if: :email_validation?

  # these are for ytopc
  # disable for now
  # validates_presence_of :province

  attr_accessor :password

  before_save :encrypt_new_password
  before_save :assign_default_site
  before_save :assign_default_contest

  # ---- problem for the users for specific action ------
  # Determines which problems a user is authorized to perform the specified action on.
  #
  # This should be the MAIN authorization filter for problem-related action and
  # should be used to scope problem lookups from the user's perspective.
  #
  # It considers following logics
  # * User's special global role of admin (admins always have right)
  # * The mode of the grader
  #   * the Group Mode and user's role and the enable property in the group
  #   * the Contest Mode and the user's role and the enable property in the contest
  # * The global enable property of the user
  #
  # In short, PLEASE USE this function when we need authorization of a user
  #
  # The respect_admin, when true, will cause this function to return all problems for an admin
  # The only place that respect_admin: false should be used is in the main page where the admin
  # is treated as a normal user
  #
  # valid action are :submit, :report, or :edit
  def problems_for_action(action, respect_admin: true)
    return Problem.all if admin? && respect_admin
    return Problem.none unless enabled?

    action = action.to_sym

    if GraderConfiguration.multicontests?
      # legacy mode, have not been implemented yet
      return Problem.contests_problems_for_user(self.id).none
    elsif GraderConfiguration.contest_mode?
      if [:edit, :report].include? action
        return Problem.contests_editable_problems_for_user(self.id)
      else
        return Problem.contests_problems_for_user(self.id)
      end
    else
      # normal mode
      if GraderConfiguration.use_problem_group?
        if action == :edit
          return Problem.group_editable_by_user(self.id)
        elsif action == :report
          return Problem.group_reportable_by_user(self.id)
        elsif action == :submit
          return Problem.group_submittable_by_user(self.id)
        else
          raise ArgumentError.new('action must be one of :edit, :report, :submit')
        end
      else
        if action == :submit
          return Problem.available
        else
          return Problem.none
        end
      end
    end
  end

  # ---- groups for the users for specific action ------
  # * This includes logic of User.role where admin always has right to any group
  # * This also includes logics of mode of the grader (normal, contest, analysis)
  # * This also consider whether the user is enabled ---
  # * This DOES NOT respect group_mode, it always performed as the group mode is enabled
  #
  # valid action is either :submit, :report, :edit
  def groups_for_action(action)
    return Group.all if admin?
    return Group.none unless enabled?

    action = action.to_sym

    # normal mode
    if action == :edit
      return Group.editable_by_user(self.id)
    elsif action == :report
      return Group.reportable_by_user(self.id)
    elsif action == :submit
      return Group.submittable_by_user(self.id)
    else
      raise ArgumentError.new('action must be one of :edit, :report, :submit')
    end
  end

  # ---- groups for the users for specific action ------
  # * This includes logic of User.role where admin always has right to any group
  # * This also includes logics of mode of the grader (normal, contest, analysis)
  # * This also consider whether the user is enabled ---
  # * This DOES NOT respect group_mode, it always performed as the group mode is enabled
  #
  # valid action is either :submit, :edit
  def contests_for_action(action)
    return Contest.all if admin?
    return Contest.none unless enabled?
    action = action.to_sym

    # normal mode
    if action == :edit
      return Contest.editable_by_user(self.id)
    elsif action == :submit
      return Contest.submittable_by_user(self.id)
    else
      raise ArgumentError.new('action must be one of :edit, :submit')
    end
  end

  def reportable_users
    return User.all if admin?
    User.joins(:groups).where(groups: {id: groups_for_action(:report)}).distinct
  end

  # ---- announcement for users for specific action -----
  # valid action is either :view, :edit
  def announcement_for_action(action)
    return Announcement.all if admin?
    return Announcement.none unless enabled?
    action = action.to_sym

    if action == :view
      return Announcement.viewable_by_user(self)
    elsif action == :edit
      return Announcement.editable_by_user(self)
    else
      raise ArgumentError.new('action must be one of :edit, :submit')
    end
  end

  # return contests of this user that is both enabled and the current time
  # is during the contest
  def active_contests
    if GraderConfiguration.contest_mode?
      return contests.where(enabled: true).where('start <= ? and stop >= ?', Time.zone.now, Time.zone.now)
    else
      return Contest.none
    end
  end

  # return datetime range of active contests
  def active_contests_range
    start = Date.new(9999, 1, 1).to_time
    stop = Date.new(1, 1, 1).to_time
    active_contests.each do |contest|
      start = [start, contest.start].min
      stop = [stop, contest.stop].max
    end
    return start..stop
  end

  def self.authenticate(login, password)
    user = find_by_login(login)
    if user
      return user if user.authenticated?(password)
    end
  end

  def authenticated?(password)
    if self.activated
      hashed_password == User.encrypt(password, self.salt)
    else
      false
    end
  end

  def login_with_name
    "[#{login}] #{full_name}"
  end

  def admin?
    @is_admin = has_role?('admin') if @is_admin.nil?
    return @is_admin
  end

  def has_role?(role)
    self.roles.where(name: [role, 'admin']).any?
  end

  def email_for_editing
    if self.email==nil
      "(unknown)"
    elsif self.email==''
      "(blank)"
    else
      self.email
    end
  end

  def email_for_editing=(e)
    self.email=e
  end

  def alias_for_editing
    if self.alias==nil
      "(unknown)"
    elsif self.alias==''
      "(blank)"
    else
      self.alias
    end
  end

  def alias_for_editing=(e)
    self.alias=e
  end

  def activation_key
    if self.hashed_password==nil
      encrypt_new_password
    end
    Digest::SHA1.hexdigest(self.hashed_password)[0..7]
  end

  def verify_activation_key(key)
    key == activation_key
  end

  def self.random_password(length = 5)
    chars = 'abcdefghjkmnopqrstuvwxyz'
    password = ''
    length.times { password << chars[rand(chars.length - 1)] }
    password
  end


  # Contest information

  def self.find_users_with_no_contest
    users = User.all
    return users.find_all { |u| u.contests.length == 0 }
  end

  # ---------------------
  # ---- contest --------
  # ---------------------

  # original contest
  def contest_time_left
    if GraderConfiguration.contest_mode?
      return nil if site==nil
      return site.time_left
    elsif GraderConfiguration.indv_contest_mode?
      time_limit = GraderConfiguration.contest_time_limit
      if time_limit == nil
        return nil
      end
      if contest_stat==nil or contest_stat.started_at==nil
        return (Time.now.gmtime + time_limit) - Time.now.gmtime
      else
        finish_time = contest_stat.started_at + time_limit
        current_time = Time.now.gmtime
        if current_time > finish_time
          return 0
        else
          return finish_time - current_time
        end
      end
    else
      return nil
    end
  end


  def contest_finished?
    if GraderConfiguration.contest_mode?
      return false if site==nil
      return site.finished?
    elsif GraderConfiguration.indv_contest_mode?
      return false if self.contest_stat==nil
      return contest_time_left == 0
    else
      return false
    end
  end

  def contest_started?
    if GraderConfiguration.indv_contest_mode?
      stat = self.contest_stat
      return ((stat != nil) and (stat.started_at != nil))
    elsif GraderConfiguration.contest_mode?
      return true if site==nil
      return site.started
    else
      return true
    end
  end

  def update_start_time
    stat = self.contest_stat
    if stat.nil? or stat.started_at.nil?
      stat ||= UserContestStat.new(user: self)
      stat.started_at = Time.now.gmtime
      stat.save
    end
  end

  def problem_in_user_contests?(problem)
    problem_contests = problem.contests.all

    if problem_contests.length == 0   # this is public contest
      return true
    end

    contests.each do |contest|
      if problem_contests.find { |c| c.id == contest.id }
        return true
      end
    end
    return false
  end


  def solve_all_available_problems?
    problems_for_action(:submit).each do |p|
      u = self
      sub = Submission.find_last_by_user_and_problem(u.id, p.id)
      return false if !p || !sub || sub.points < 100
    end
    return true
  end

  def last_submission_by_problem(problem)
    submissions.where(problem: problem).order(:submitted_at).last
  end

  #
  # -- permission methods ---
  #

  # check if the user has the right to view that problem
  # this also consider group based problem policy
  def can_view_problem?(problem)
    # admin always has right
    return true if admin?

    # if a user is a reporter or an editor, they can access disabled problem, which is not allowed in problems_for_action(:submit)
    # we need both :report and :submit action because :report is not the super set of :submit
    # For example, a user can be a reporter (or an editor) for some group while being a normal user on some group
    return true if problems_for_action(:report).where(id: problem.id).any?

    # the final step is for submit
    return problems_for_action(:submit).where(id: problem.id).any?
  end

  def can_report_problem?(problem)
    # admin always has right
    return true if admin?

    return problems_for_action(:report).where(id: problem.id).any?
  end

  def can_edit_problem?(problem)
    # admin always has right
    return true if admin?
    return problems_for_action(:edit).where(id: problem).any?
  end

  # Whether the user can download the problem's statement PDF / external
  # URL. Mirrors can_view_problem? except that students don't see the
  # PDF for problem modes where it shouldn't be revealed (viva, today —
  # see Problem#pdf_visible_to_student?). Instructors and reporters
  # always see the brief; they need it to manage and grade.
  #
  # This is the SECURITY-BOUNDARY predicate — call it in controllers
  # that serve the PDF (ProblemsController#download_by_type, the API
  # file endpoint). Views that already iterate over problems the user
  # can submit to should NOT call this — it would N+1 — and should
  # just read problem.pdf_visible_to_student? directly.
  def can_view_problem_pdf?(problem)
    return true if admin?
    return true if can_edit_problem?(problem) || can_report_problem?(problem)
    return false unless can_view_problem?(problem)
    problem.pdf_visible_to_student?
  end

  def can_view_submission?(submission)
    # admin always has right
    return true if admin?

    # For group mode, reporters can always view the submission of the problem
    return true if problems_for_action(:report).include? submission.problem

    # At this step, we knows that the user does not have special privileges to the problem

    # problem available is required
    return false unless problems_for_action(:submit).include? submission.problem

    # a user can view their own submissions
    return true if submission.user == self

    # check global disable
    return false unless GraderConfiguration["right.user_view_submission"]

    # finally, the view_submission of the problem must be true
    return submission.problem.view_submission
  end

  def can_view_testcase?(problem)
    # admin always has right
    return true if admin?

    return can_view_problem?(problem) && GraderConfiguration["right.view_testcase"]
  end

  def can_edit_announcement(announcement)
    # admin always has right
    return true if admin?

    # if the announcement is not group specific or is in a group t
    return true if Announcement.editable_by_user(self).where(id: announcement).any?

    return false
  end


  #
  # -- end permission methods --
  #


  def self.clear_last_login
    User.update_all(last_ip: nil)
  end

  def get_jschart_user_sub_history
    start = 4.month.ago.beginning_of_day
    start_date = start.to_date
    count = Submission.where(user: self).where('submitted_at >= ?', start).group('DATE(submitted_at)').count
    i = 0
    label = []
    value = []
    while start_date + i < Time.zone.now.to_date
      label << (start_date+i).strftime("%d-%b")
      value << (count[start_date+i] || 0)
      i+=1
    end
    return {labels: label, datasets: [label: 'sub', data: value, backgroundColor: 'rgba(54, 162, 235, 0.2)', borderColor: 'rgb(75, 192, 192)']}
  end

  def get_jschart_user_contest_history(contest)
    cu = contest.contests_users.where(user: self).take
    start = contest.start - cu.start_offset_second.second
    stop = [Time.zone.now, contest.stop + cu.extra_time_second.second].min

    # divide into 120 step
    step = (stop - start) / 120

    # adjust
    step = [60, step].max
    step = (step / 60).to_i * 60

    submitted_at = contest.user_submissions(self).order(:submitted_at).pluck :submitted_at


    now = start
    i = 0
    label = []
    value = []
    while now < stop
      count = 0
      while i < submitted_at.count && submitted_at[i] < now + step.second
        count += 1
        i += 1
        puts "got #{submitted_at[i]} for #{now.strftime("%H:%M")}"
      end
      label << now.strftime("%H:%M")  # hours / minute
      value << count

      now += step.second
    end
    return {labels: label, datasets: [ {label: 'sub', data: value, backgroundColor: 'rgba(255, 99, 132,0.8)', borderColor: 'rgb(255, 99, 132)'}]}
  end

  # create multiple user, one per lines of input
  # This one is used in the import of Users in the bulk manage user page
  def self.create_from_list(lines)
    error_logins = []
    first_error = nil
    created_user_ids = []
    updated_user_ids = []

    lines.split("\n").each do |line|
      # split with large limit, this will cause consecutive ',' to be result in a blank
      items = line.chomp.split(',', 1000)
      if items.length>=2
        login = items[0]
        full_name = items[1]
        remark =''
        user_alias = ''

        added_random_password = false
        added_password = false

        # given password?
        if items.length >= 3
          if items[2].chomp(" ").length > 0
            password = items[2].chomp(" ")
            added_password = true
          end
        else
          password = random_password
          added_random_password=true
        end

        # given alias?
        if items.length>= 4 and items[3].chomp(" ").length > 0
          user_alias = items[3].chomp(" ")
        else
          user_alias = login
        end

        # given remark?
        has_remark = false
        if items.length>=5
          remark = items[4].strip
          has_remark = true
        end

        user = User.find_by_login(login)
        created = false
        if user
          user.full_name = full_name
          user.remark = remark if has_remark
          user.password = password if added_password || added_random_password
        else
          # create a random password if none are given
          password = random_password unless password
          user = User.new({login: login,
                           full_name: full_name,
                           password: password,
                           password_confirmation: password,
                           alias: user_alias,
                           remark: remark})
          created = true
        end
        user.activated = true

        if user.save
          if created
            created_user_ids << user.id
          else
            updated_user_ids << user.id
          end
        else
          error_logins << "'#{login}'"
          first_error = user.errors.full_messages.to_sentence unless first_error
        end
      end
    end

    return {error_logins: error_logins, first_error: first_error,
            created_users: User.where(id: created_user_ids), updated_users: User.where(id: updated_user_ids)}
  end

  protected
    def encrypt_new_password
      return if password.blank?
      self.salt = (10+rand(90)).to_s
      self.hashed_password = User.encrypt(self.password, self.salt)
    end

    def assign_default_site
      # have to catch error when migrating (because self.site is not available).
      begin
        if self.site==nil
          self.site = Site.find_by_name('default')
          if self.site==nil
            self.site = Site.find(1)  # when 'default has be renamed'
          end
        end
      rescue
      end
    end

    def assign_default_contest
      # have to catch error when migrating (because self.site is not available).
      begin
        if self.contests.length == 0
          default_contest = Contest.find_by_name(GraderConfiguration['contest.default_contest_name'])
          if default_contest
            self.contests = [default_contest]
          end
        end
      rescue
      end
    end

    def password_required?
      self.hashed_password.blank? || !self.password.blank?
    end

    def self.encrypt(string, salt)
      Digest::SHA1.hexdigest(salt + string)
    end

    def uniqueness_of_email_from_activated_users
      user = User.activated_users.find_by_email(self.email)
      if user and (user.login != self.login)
        self.errors.add(:base, "Email has already been taken")
      end
    end

    def enough_time_interval_between_same_email_registrations
      return if !self.new_record?
      return if self.activated
      open_user = User.find_by_email(self.email,
                                     order: 'created_at DESC')
      if open_user and open_user.created_at and
          (open_user.created_at > Time.now.gmtime - 5.minutes)
        self.errors.add(:base, "There are already unactivated registrations with this e-mail address (please wait for 5 minutes)")
      end
    end

    def email_validation?
      begin
        return VALIDATE_USER_EMAILS
      rescue
        return false
      end
    end
end
