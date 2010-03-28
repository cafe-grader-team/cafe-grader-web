module MailHelperMethods

  def send_mail(to, subject, body)
    mail = TMail::Mail.new
    mail.to = to
    mail.from = Configuration['system.online_registration.from']
    mail.subject = subject
    mail.body = body

    smtp_server = Configuration['system.online_registration.smtp']

    if ['fake', 'debug'].include? smtp_server
      puts "-------------------------
To: #{mail.to}
From: #{mail.from}
Subject: #{mail.subject}
#{mail.body}
--------------------------
"
      return true
    end

    begin
      Net::SMTP.start(smtp_server) do |smtp|
        smtp.send_message(mail.to_s, mail.from, mail.to)
      end
      result = true
    rescue
      result = false
    end

    result
  end

end

