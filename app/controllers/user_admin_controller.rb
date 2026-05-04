class UserAdminController < ApplicationController
  before_action :admin_authorization

  # Stimulus controller connection
  before_action :page_stimulus_controller, only: %w[admin index]
  before_action :set_user, only: %w[ clear_last_ip toggle_enable toggle_activate
                                     edit update stat stat_contest ]

  def index
    @user_count = User.count
    @users = User.all
    @hidden_columns = ['hashed_password', 'salt', 'created_at', 'updated_at']
    @contests = Contest.enabled
    @user = User.new
  end

  def index_query
    render json: { data: User.all }
  end

  def active
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.activated = true
    if @user.save
      flash[:notice] = 'User was successfully created.'
      redirect_to action: 'index'
    else
      render action: 'new'
    end
  end

  def user_action
    @user = User.find(params[:user_id])
    @toast = {title: "User #{@user.full_name} (#{@user.login})"}

    case params[:command]
    when 'clear_ip'
      @user.update(last_ip: nil)
      @toast[:body] = "Session lock is reset"
    when 'toggle'
      @user.update(enabled: !@user.enabled)
      @toast[:body] = "User enabled set to #{@user.enabled}"
    else
      @toast[:body] = "Unknown command"
    end
    render 'turbo_toast'
  end

  #
  # --- member function
  #
  def clear_last_ip
    @user.update(last_ip: nil)
    redirect_to action: 'index', page: params[:page]
  end

  def toggle_activate
    @user.update(activated:  !@user.activated?)
    respond_to do |format|
      format.js { render partial: 'toggle_button',
                  locals: {button_id: "#toggle_activate_user_#{@user.id}", button_on: @user.activated? } }
    end
  end

  def toggle_enable
    @user.update(enabled:  !@user.enabled?)
    respond_to do |format|
      format.js { render partial: 'toggle_button',
                  locals: {button_id: "#toggle_enable_user_#{@user.id}", button_on: @user.enabled? } }
    end
  end

  def stat
    @submission = Submission.joins(:problem).includes(:problem).includes(:language).where(user_id: params[:id])

    build_stat

    @chart_dataset = @user.get_jschart_user_sub_history.to_json.html_safe
  end

  def stat_contest
    @contest = Contest.find(params[:contest_id])
    @submission = @contest.user_submissions(@user)

    build_stat

    @chart_dataset = @user.get_jschart_user_contest_history(@contest).to_json.html_safe

    render 'stat'
  end


  def create_from_list
    lines = params[:user_list]


    res = User.create_from_list(lines)
    error_logins = res[:error_logins]
    error_msg = res[:first_error]
    created_users = res[:created_users]
    updated_users = res[:updated_users]

    # add to group
    if params[:add_to_group] == '1'
      group = Group.find_by(id: params[:group_id])&.add_users_skip_existing(created_users)
      group = Group.find_by(id: params[:group_id])&.add_users_skip_existing(updated_users)
    end

    # show flash
    ok_text = ''
    ok_text += "#{created_users.count} user(s) were created successfully. " if created_users.count > 0
    ok_text += "#{updated_users.count} user(s) were updated successfully." if updated_users.count > 0
    flash[:success] = ok_text unless ok_text.blank?
    if error_logins.size > 0
      flash[:error] = "Following user(s) failed to be created: " + error_logins.join(', ') + ". The errors of the first failed one are: " + error_msg
    end
    redirect_to action: 'index'
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to edit_user_admin_path(@user), notice: 'User was successfully updated.'
    else
      render action: 'edit'
    end
  end

  def destroy
    User.find(params[:id]).destroy
    redirect_to action: 'index'
  end

  # GET — renders the import form / result page. The form posts to
  # do_import. (Currently no view in the codebase actually contains the
  # upload form; only the result template exists. Added form would belong
  # in app/views/user_admin/import.html.haml above the result section.)
  def import
  end

  # POST — process an uploaded YAML file; render the import result.
  def do_import
    if params[:file].blank?
      flash[:notice] = 'Error: no file uploaded'
      redirect_to action: 'import' and return
    end
    import_from_file(params[:file])
    render :import
  end

  # contest management

  def contests
    @contest, @users = find_contest_and_user_from_contest_id(params[:id])
    @contests = Contest.enabled
  end

  def assign_from_list
    contest_id = params[:users_contest_id]
    org_contest, users = find_contest_and_user_from_contest_id(contest_id)
    contest = Contest.find(params[:new_contest][:id])
    if !contest
      flash[:notice] = 'Error: no contest'
      redirect_to action: 'contests', id: contest_id
    end

    note = []
    users.each do |u|
      u.contests = [contest]
      note << u.login
    end
    flash[:notice] = 'User(s) ' + note.join(', ') +
      " were successfully reassigned to #{contest.title}."
    redirect_to action: 'contests', id: contest.id
  end

  def add_to_contest
    user = User.find(params[:id])
    contest = Contest.find(params[:contest_id])
    if user and contest
      user.contests << contest
    end
    redirect_to action: 'index'
  end

  def remove_from_contest
    user = User.find(params[:id])
    contest = Contest.find(params[:contest_id])
    if user and contest
      user.contests.delete(contest)
    end
    redirect_to action: 'index'
  end

  def contest_management
  end

  def manage_contest
    contest = Contest.find(params[:contest][:id])
    if !contest
      flash[:notice] = 'You did not choose the contest.'
      redirect_to action: 'contest_management' and return
    end

    operation = params[:operation]

    if not ['add', 'remove', 'assign'].include? operation
      flash[:notice] = 'You did not choose the operation to perform.'
      redirect_to action: 'contest_management' and return
    end

    lines = params[:login_list]
    if !lines or lines.blank?
      flash[:notice] = 'You entered an empty list.'
      redirect_to action: 'contest_management' and return
    end

    note = []
    users = []
    lines.split("\n").each do |line|
      user = User.find_by_login(line.chomp)
      if user
        if operation=='add'
          if ! user.contests.include? contest
            user.contests << contest
          end
        elsif operation=='remove'
          user.contests.delete(contest)
        else
          user.contests = [contest]
        end

        if params[:reset_timer]
          user.contest_stat.forced_logout = true
          user.contest_stat.reset_timer_and_save
        end

        if params[:notification_emails]
          send_contest_update_notification_email(user, contest)
        end

        note << user.login
        users << user
      end
    end

    if params[:reset_timer]
      logout_users(users)
    end

    flash[:notice] = 'User(s) ' + note.join(', ') +
      ' were successfully modified.  '
    redirect_to action: 'contest_management'
  end

  # admin management

  def admin
    @admins = Role.find_by(name: 'admin')&.users || User.none
    @tas = Role.find_by(name: 'ta')&.users || User.none
  end

  def admin_query
    render json: {data: Role.find_by(name: 'admin')&.users || User.none}
  end

  def ta_query
    render json: {data: Role.find_by(name: 'ta')&.users || User.none}
  end

  # TURBO_STREAM
  def modify_role
    @toast = {title: "Modify role"}

    user = User.find(params[:id])
    role = Role.find_by_name(params[:role])
    unless user && role
      @toast[:body] = 'Unknown user or role'
      @toast[:type] = :alert
      render 'turbo_toast' and return
    end
    if params[:command] == 'grant'
      # grant role
      if user.roles.where(name: role.name).any?
        @toast[:body] = "User '#{user.login}' already has the role '#{role.name}'"
        @toast[:type] = :alert
      else
        user.roles << role
        @toast[:body] = "User '#{user.login}' has been granted the role '#{role.name}'"
      end
    else
      # revoke role
      if user.login == 'root' && role.name == 'admin'
        @toast[:body] = 'You cannot revoke administrator permission from root.'
        @toast[:type] = :alert
        render 'turbo_toast' and return
      end
      if user == @current_user && role.name == 'admin'
        @toast[:body] = 'You cannot revoke your own administrator role'
        @toast[:type] = :alert
        render 'turbo_toast' and return
      end
      user.roles.delete(role)
      @toast[:body] ="The role '#{role.name}' has been revoked from User '#{user.login}'"
    end
    render 'turbo_toast'
  end

  # mass mailing

  def mass_mailing
  end

  def bulk_mail
    lines = params[:login_list]
    if !lines or lines.blank?
      flash[:notice] = 'You entered an empty list.'
      redirect_to action: 'mass_mailing' and return
    end

    mail_subject = params[:subject]
    if !mail_subject or mail_subject.blank?
      flash[:notice] = 'You entered an empty mail subject.'
      redirect_to action: 'mass_mailing' and return
    end

    mail_body = params[:email_body]
    if !mail_body or mail_body.blank?
      flash[:notice] = 'You entered an empty mail body.'
      redirect_to action: 'mass_mailing' and return
    end

    note = []
    users = []
    lines.split("\n").each do |line|
      user = User.find_by_login(line.chomp)
      if user
        MailSender.send_mail(user.email, mail_subject, mail_body)
        note << user.login
      end
    end

    flash[:notice] = 'User(s) ' + note.join(', ') +
      ' were successfully modified.  '
    redirect_to action: 'mass_mailing'
  end

  # bulk manage
  def bulk_manage
    begin
      if params[:filter_group]
        @users = Group.find_by(id: params[:filter_group_id]).users
      else
        @users = User.all
      end
      @users = @users.where('(login REGEXP ?) OR (remark REGEXP ?)', params[:regex], params[:regex]) unless params[:regex].blank?
      @users.count if @users # test the sql
    rescue Exception
      flash[:error] = 'Regular Expression is malformed'
      @users = nil
    end

    if params[:commit]
      @action = {}
      @action[:set_enable] = params[:enabled]
      @action[:enabled] = params[:enable] == "1"
      @action[:gen_password] = params[:gen_password]
      @action[:add_group] = params[:add_group]
      @action[:group_name] = params[:group_name]
    end

    if params[:commit] == "Perform"
      if @action[:set_enable]
        @users.update_all(enabled: @action[:enabled])
      end
      if @action[:gen_password]
        @users.each do |u|
          password = random_password
          u.password = password
          u.password_confirmation = password
          u.save
        end
      end
      if @action[:add_group] and @action[:group_name]
        @group = Group.find(@action[:group_name])
        ok = []
        failed = []
        @users.each do |user|
          begin
            @group.users << user
            ok << user.login
          rescue => e
            failed << user.login
          end
        end
        flash[:success] = "The following users are added to the 'group #{@group.name}': " + ok.join(', ') if ok.count > 0
        flash[:alert] = "The following users are already in the 'group #{@group.name}': " + failed.join(', ') if failed.count > 0
      end
    end
  end

  protected

  def random_password(length = 5)
    chars = 'abcdefghijkmnopqrstuvwxyz23456789'
    newpass = ""
    length.times { newpass << chars[rand(chars.size-1)] }
    return newpass
  end

  def import_from_file(f)
    data_hash = YAML.load(f)
    @import_log = ""

    country_data = data_hash[:countries]
    site_data = data_hash[:sites]
    user_data = data_hash[:users]

    # import country
    countries = {}
    country_data.each_pair do |id, country|
      c = Country.find_by_name(country[:name])
      if c!=nil
        countries[id] = c
        @import_log << "Found #{country[:name]}\n"
      else
        countries[id] = Country.new(name: country[:name])
        countries[id].save
        @import_log << "Created #{country[:name]}\n"
      end
    end

    # import sites
    sites = {}
    site_data.each_pair do |id, site|
      s = Site.find_by_name(site[:name])
      if s!=nil
        @import_log << "Found #{site[:name]}\n"
      else
        s = Site.new(name: site[:name])
        @import_log << "Created #{site[:name]}\n"
      end
      s.password = site[:password]
      s.country = countries[site[:country_id]]
      s.save
      sites[id] = s
    end

    # import users
    user_data.each_pair do |id, user|
      u = User.find_by_login(user[:login])
      if u!=nil
        @import_log << "Found #{user[:login]}\n"
      else
        u = User.new(login: user[:login])
        @import_log << "Created #{user[:login]}\n"
      end
      u.full_name = user[:name]
      u.password = user[:password]
      u.country = countries[user[:country_id]]
      u.site = sites[user[:site_id]]
      u.activated = true
      u.email = "empty-#{u.login}@none.com"
      if not u.save
        @import_log << "Errors\n"
        u.errors.each { |attr, msg|  @import_log << "#{attr} - #{msg}\n" }
      end
    end
  end

  def logout_users(users)
    users.each do |user|
      contest_stat = user.contest_stat(true)
      if contest_stat and !contest_stat.forced_logout
        contest_stat.forced_logout = true
        contest_stat.save
      end
    end
  end

  def send_contest_update_notification_email(user, contest)
    contest_title_name = GraderConfiguration['ui.site_title']
    contest_name = contest.name
    mail_subject = t('contest.notification.email_subject', {
                       contest_title_name: contest_title_name,
                       contest_name: contest_name })
    mail_body = t('contest.notification.email_body', {
                    full_name: user.full_name,
                    contest_title_name: contest_title_name,
                    contest_name: contest.name
                  })

    logger.info mail_body
    MailSender.send_mail(user.email, mail_subject, mail_body)
  end

  def find_contest_and_user_from_contest_id(id)
    if id!='none'
      @contest = Contest.find(id)
    else
      @contest = nil
    end
    if @contest
      @users = @contest.users
    else
      @users = User.find_users_with_no_contest
    end
    return [@contest, @users]
  end


  private
    def user_params
      params.require(:user).permit(:login, :password, :password_confirmation, :email, :alias, :full_name, :remark, :enabled, group_ids: [])
    end

    def set_user
      @user = User.find(params[:id])
    end

    # for action stat and user_stat
    def build_stat
      # when @contest is null, `chargeable_for` will ignore contest filtering
      if @contest
        range = (@contest.start)..(@contest.stop)
        comment_count = Comment.chargeable_for(@user, range).group(:kind).count
      else
        comment_count = Comment.chargeable_for(@user).group(:kind).count
      end

      # count solve / attempted
      max_score = @submission.group(:problem_id).pluck('problem_id, max(points) as max_point')
      @summary = {count: max_score.count,
                  solve: max_score.select { |x| x[1] == 100 }.count,
                  hint: comment_count["hint"],
                  llm_assist: comment_count["llm_assist"]}
    end
end
