require 'tmpdir'

class TestdataImporter
  
  attr :log_msg

  def initialize(problem)
    @problem = problem
  end

  def import_from_file(tempfile, 
                       time_limit, 
                       memory_limit,
                       import_to_db=false)

    dirname = extract(tempfile)
    return false if not dirname
    if not import_to_db
      @log_msg = GraderScript.call_import_problem(@problem.name,
                                                  dirname,
                                                  time_limit,
                                                  memory_limit)
    else
      # Import test data to test pairs.

      @problem.test_pairs.clear
      if import_test_pairs(dirname)
        test_pair_count = TestPair.count :conditions => "problem_id = #{@problem.id}"
        @log_msg = "Importing test pair successful. (#{test_pair_count} test pairs imported)"
      else
        @log_msg = "Importing test pair failed. (0 test pairs imported)"
      end
    end

    @log_msg << import_problem_description(dirname)
    @log_msg << import_problem_pdf(dirname)

    return true
  end

  protected

  def self.long_ext(filename)
    i = filename.index('.')
    len = filename.length
    return filename.slice(i..len)
  end

  def extract(tempfile)
    testdata_filename = save_testdata_file(tempfile)
    ext = TestdataImporter.long_ext(tempfile.original_filename)

    extract_dir = File.join(GraderScript.raw_dir, @problem.name)
    begin
      Dir.mkdir extract_dir
    rescue Errno::EEXIST
    end

    if ext=='.tar.gz' or ext=='.tgz'
      cmd = "tar -zxvf #{testdata_filename} -C #{extract_dir}"
    elsif ext=='.tar'
      cmd = "tar -xvf #{testdata_filename} -C #{extract_dir}"
    elsif ext=='.zip'
      cmd = "unzip -o #{testdata_filename} -d #{extract_dir}"
    else
      return nil
    end

    system(cmd)

    files = Dir["#{extract_dir}/**/*1*.in"]
    return nil if files.length==0

    File.delete(testdata_filename)

    return File.dirname(files[0])
  end

  def save_testdata_file(tempfile)
    ext = TestdataImporter.long_ext(tempfile.original_filename)
    testdata_filename = File.join(Dir.tmpdir,"#{@problem.name}#{ext}")

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

  def import_test_pairs(dirname)
    test_num = 1
    while FileTest.exists? "#{dirname}/#{test_num}.in"
      in_filename = "#{dirname}/#{test_num}.in"
      sol_filename = "#{dirname}/#{test_num}.sol"

      break if not FileTest.exists? sol_filename

      test_pair = TestPair.new(:input => open(in_filename).read,
                               :solution => open(sol_filename).read,
                               :problem => @problem)
      break if not test_pair.save

      test_num += 1
    end
    return test_num > 1
  end

  def import_problem_description(dirname)
    html_files = Dir["#{dirname}/*.html"]
    markdown_files = Dir["#{dirname}/*.md"] + Dir["#{dirname}/*.markdown"]
    if (html_files.length != 0) or (markdown_files.length != 0)
      description = @problem.description || Description.new

      if html_files.length != 0
        filename = html_files[0]
        description.markdowned = false
      else
        filename = markdown_files[0]
        description.markdowned = true
      end

      description.body = open(filename).read
      description.save
      @problem.description = description
      @problem.save
      return "\nProblem description imported from #{filename}."
    else
      return ''
    end
  end

  def import_problem_pdf(dirname)
    pdf_files = Dir["#{dirname}/*.pdf"]
    if pdf_files.length != 0
      filename = pdf_files[0]
      out_filename = "#{Problem.download_file_basedir}/#{@problem.name}.pdf"
      File.rename(filename, out_filename)
      @problem.description_filename = "#{@problem.name}.pdf"
      @problem.save
      return "\nProblem pdf imported from #{filename}."
    end
  end

end
