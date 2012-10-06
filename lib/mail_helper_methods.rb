module MailHelperMethods

  def send_mail(mail_to, mail_subject, mail_body)
    mail_from = GraderConfiguration['system.online_registration.from']
    smtp_server = GraderConfiguration['system.online_registration.smtp']

    if ['fake', 'debug'].include? smtp_server
      puts "-------------------------
To: #{mail_to}
From: #{mail_from}
Subject: #{mail_subject}
#{mail_body}
--------------------------
"
      return true
    end

    mail = Mail.new do
      from mail_from
      to mail_to
      subject mail_subject
      body mail_body
    end

    mail.delivery_settings = { :address => smtp_server }
    mail.deliver
  end

end

