#!/usr/bin/env ruby
require 'open3'

sql = <<-SQL
  %SQL_CMD%
SQL
table_name_translation = %w(%TRANSLATE_TABLE%)
testcase_id = ARGV[1]

#do the table name translation
table_name_translation.each { |from| sql.gsub!(from,from+'_'+testcase_id.to_s) }

cmd = '/usr/bin/psql postgres://user:pass@127.0.0.1/dbname'

out,err,status = Open3.capture3(cmd, stdin_data: sql)
puts out

