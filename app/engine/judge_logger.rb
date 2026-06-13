class JudgeLogger
  @@logger_filename = Rails.root.join 'log', 'judge.log'
  def self.logger
    @@logger ||= Logger.new(@@logger_filename)
    if @@logger_filename.exist? == false
      @@logger = Logger.new(@@logger_filename)
    end
    return @@logger
  end
end
