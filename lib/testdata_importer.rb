require 'tmpdir'

class TestdataImporter

  attr :log_msg

  def import_from_file(problem_name, 
                       tempfile, 
                       time_limit, 
                       memory_limit)

    dirname = TestdataImporter.extract(problem_name, tempfile)
    return false if not dirname
    @log_msg = GraderScript.call_import_problem(problem_name,
                                                dirname,
                                                time_limit,
                                                memory_limit)
    return true
  end

  protected

  def self.long_ext(filename)
    i = filename.index('.')
    len = filename.length
    return filename.slice(i..len)
  end

  def self.extract(problem_name, tempfile)
    testdata_filename = TestdataImporter.save_testdata_file(problem_name,
                                                            tempfile)
    ext = TestdataImporter.long_ext(tempfile.original_filename)

    extract_dir = File.join(GraderScript.raw_dir, problem_name)
    begin
      Dir.mkdir extract_dir
    rescue Errno::EEXIST
    end

    if ext=='.tar.gz' or ext=='.tgz'
      cmd = "tar -zxvf #{testdata_filename} -C #{extract_dir}"
    elsif ext=='.tar'
      cmd = "tar -xvf #{testdata_filename} -C #{extract_dir}"
    elsif ext=='.zip'
      cmd = "unzip #{testdata_filename} -d #{extract_dir}"
    else
      return nil
    end

    system(cmd)

    files = Dir["#{extract_dir}/**/1*.in"]
    return nil if files.length==0

    return File.dirname(files[0])
  end

  def self.save_testdata_file(problem_name, tempfile)
    ext = TestdataImporter.long_ext(tempfile.original_filename)
    testdata_filename = File.join(Dir.tmpdir,"#{problem_name}#{ext}")

    return nil if tempfile==""
    
    if tempfile.instance_of?(Tempfile)
      tempfile.close
      FileUtils.move(tempfile.path,testdata_filename)
    else
      File.open(testdata_filename, "wb") do |f| 
        f.write(tempfile.read) 
      end
    end

    return testdata_filename
  end

end
