require 'open3'

module IsolateRunner
  MetaFilename = 'meta.json'

  def setup_isolate(box_id, cg = false)
    @isolate_cmd = Rails.configuration.worker.isolate_path
    @box_id = box_id

    cmd = "#{@isolate_cmd} --init #{'--cg' if cg} -b #{@box_id}"
    judge_log "ISOLATE setup command: #{cmd}", Logger::DEBUG
    Open3.capture3(cmd)
  end

  # Run isolate,
  # time_limit, wall_limit are in second, fractional is allowed
  # mem_limit is in MB
  # time_limit is in sec
  # uid is only available when the command is ran as root
  def run_isolate(prog, input: {}, output: {}, time_limit: 1, wall_limit: time_limit + 0.5, mem_limit: 1024,
                  isolate_args: [], meta: MetaFilename, cg: false, uid: false)
    # mount directory for input /output
    dir_args = []
    output.each { |k, v| dir_args << ['-d', "#{k}=#{v}:rw"] } # these are mounted read/write
    input.each { |k, v| dir_args << ['-d', "#{k}=#{v}"] }     # these are mounted readonly

    limit_arg = "-t #{time_limit} -x #{wall_limit} -w #{wall_limit} #{cg ? '--cg-mem' : '-m'} #{mem_limit * 1024}"
    all_arg  = "#{limit_arg} #{dir_args.join ' '} #{isolate_args.join ' '}"

    # set uid that runs the isolate so that the file created by the isolate is owned by the current user
    # this is only possible when isolate is run as root
    all_arg += " --as-uid=${UID}" if uid == true

    cmd = "#{@isolate_cmd} #{'--cg' if cg} --run -b #{@box_id} #{"--meta=#{meta}" if meta} #{all_arg} -- #{prog}"
    judge_log("ISOLATE run command: #{Rainbow(cmd).color(JudgeBase::COLOR_ISOLATE_CMD)}", Logger::DEBUG)
    out, err, status = Open3.capture3(cmd)
    judge_log("ISOLATE run completed: status #{status}, stdout size = #{out.length}", Logger::DEBUG)

    return out, err, status, parse_meta(meta)
  end

  def cleanup_isolate(cg = false)
    cmd = "#{@isolate_cmd} --cleanup -b #{@box_id} #{'--cg' if cg}"
    judge_log "ISOLATE cleanup command: #{cmd}", Logger::DEBUG
    system(cmd)
  end

  # load the filename and parse it
  # return a hash
  def parse_meta(filename)
    result = Hash.new
    return result unless filename
    File.open(filename, 'r').each do |line|
      a, b = line.split(':')
      case a
      when 'exitcode'
        result[a] = b.to_i
      when 'status', 'message'
        result[a] = b.strip
      else
        result[a] = b.to_d
      end
    end
    return result
  end
end
