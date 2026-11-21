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

  attr_reader :rows, :ignored_line_nos

  def initialize(text)
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

  private

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
