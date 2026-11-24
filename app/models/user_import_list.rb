# Parses the text pasted into the bulk "import users" page, one user per line:
#   login,full name[,password[,alias[,remark]]]
# Used by User.create_from_list so that Create and any no-save preview read
# the text in exactly the same way.
class UserImportList
  # password_mode:
  #   :given  - third field non-empty (password holds it)
  #   :keep   - third field present but empty (password nil)
  #   :random - only two fields (password nil)
  # remark is nil when there is no fifth field ("don't touch").
  Row = Data.define(:line_no, :login, :full_name, :password, :password_mode, :user_alias, :remark)

  # What an import would do, without doing it. Every list holds logins as typed
  # in that login's last row; not_covered is nil without an outside login;
  # has_tabs is true when the text has a tab character (a paste from Excel).
  Check = Data.define(:row_count, :new_password, :random_password, :keep_password,
                      :new_accounts, :duplicates, :name_changes, :remark_changes,
                      :ignored_line_nos, :not_covered, :has_tabs)

  attr_reader :rows, :ignored_line_nos

  def initialize(text)
    @has_tabs = text.to_s.include?("\t")
    @rows = []
    @ignored_line_nos = []
    text.to_s.split("\n").each_with_index do |line, i|
      line_no = i + 1
      # large limit: consecutive ',' result in a blank item
      items = line.chomp.split(',', 1000)
      if items.length >= 2
        @rows << build_row(line_no, items)
      elsif line.strip.length > 0
        @ignored_line_nos << line_no
      end
    end
  end

  # No-save preview. Logins are keyed case-insensitively (MySQL compares them
  # that way). Rows of one login combine the way Create applies them in order:
  # the password changes if any row gives or randomizes it (the last such row
  # decides which), the remark is the last non-nil one, the name the last row's.
  def check(now: Time.zone.now)
    by_key = rows.group_by { |r| r.login.downcase }
    last = by_key.transform_values { |rs| combine(rs) }
    duplicates = by_key.select { |_, rs| rs.size > 1 }.values.map { |rs| rs.last.login }
    existing = User.where(login: last.values.map(&:login)).index_by { |u| u.login.downcase }

    new_password, random_password, keep_password = [], [], []
    new_accounts, name_changes, remark_changes = [], [], []
    last.each do |key, row|
      user = existing[key]
      if user.nil?
        new_accounts << row.login
        next
      end
      case row.password_mode
      when :given then new_password << row.login
      when :random then random_password << row.login
      else keep_password << row.login
      end
      name_changes << row.login if row.full_name != user.full_name
      remark_changes << row.login if !row.remark.nil? && row.remark != user.remark.to_s
    end

    Check.new(has_tabs: @has_tabs, row_count: rows.size, new_password:, random_password:, keep_password:,
              new_accounts:, duplicates:, name_changes:, remark_changes:,
              ignored_line_nos: ignored_line_nos.dup,
              not_covered: not_covered_logins(last, existing, now))
  end

  private

  # One row standing for all rows of a login: the last row, with the password
  # mode and the remark Create would end up with.
  def combine(rs)
    changing = rs.reverse.find { |r| r.password_mode != :keep }
    remark = rs.reverse.find { |r| !r.remark.nil? }&.remark
    rs.last.with(password_mode: changing ? changing.password_mode : :keep, remark: remark)
  end

  def not_covered_logins(last, existing, now)
    return nil unless User.outside_login_available?
    getting_new = last.select { |key, row| existing[key].nil? || row.password_mode != :keep }
    ids = getting_new.keys.filter_map { |k| existing[k]&.id }
    covered = ContestUser.blocking_outside_login(now).where(user_id: ids).distinct.pluck(:user_id)
    getting_new.reject { |key, _| existing[key] && covered.include?(existing[key].id) }.values.map(&:login)
  end

  def build_row(line_no, items)
    password = nil
    mode = :random
    if items.length >= 3
      given = items[2].chomp(" ")
      if given.length > 0
        password = given
        mode = :given
      else
        mode = :keep
      end
    end

    login = items[0]
    user_alias = login
    user_alias = items[3].chomp(" ") if items.length >= 4 && items[3].chomp(" ").length > 0

    remark = items.length >= 5 ? items[4].strip : nil

    Row.new(line_no: line_no, login: login, full_name: items[1], password: password,
            password_mode: mode, user_alias: user_alias, remark: remark)
  end
end
