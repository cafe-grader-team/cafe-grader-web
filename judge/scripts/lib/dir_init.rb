require 'ftools'

# DirInit::Manager handles directory initialization and clean-up when
# there are many concurrent processes that wants to modify the
# directory in the same way.
#
# An example usage is when each process wants to copy some temporary
# files to the directory and delete these files after finishing its
# job.  Problems may occur when the first process delete the files
# while the second process is still using the files.
#
# This library maintain a reference counter on the processes using the
# directory.  It locks the dir to manage critical section when
# updating the reference counter.

module DirInit

  class Manager
  
    def initialize(dir_name, usage_filename='.usage_counter')
      @dir_name = dir_name
      @usage_filename = usage_filename
    end

    # Check if someone has initialized the dir.  If not, call block.

    def setup    # :yields: block
      dir = File.new(@dir_name)
      dir.flock(File::LOCK_EX)
      begin
        counter_filename = get_counter_filename
        if File.exist? counter_filename
          # someone is here
          f = File.new(counter_filename,"r+")
          counter = f.read.to_i
          f.seek(0)
          f.write("#{counter+1}\n")
          f.close
        else
          # i'm the first, create the counter file
          counter = 0
          f = File.new(counter_filename,"w")
          f.write("1\n")
          f.close
        end
        
        # if no one is here
        if counter == 0
          if block_given?
            yield
          end
        end
        
      rescue
        raise
        
      ensure
        # make sure it unlock the directory
        dir.flock(File::LOCK_UN)
      end
    end
    
    # Check if I am the last one using the dir.  If true, call block.

    def teardown
      dir = File.new(@dir_name)
      dir.flock(File::LOCK_EX)
      begin
        counter_filename = get_counter_filename
        if File.exist? counter_filename
          # someone is here
          f = File.new(counter_filename,"r+")
          counter = f.read.to_i
          f.seek(0)
          f.write("#{counter-1}\n")
          f.close
          
          if counter == 1
            # i'm the last one
            
            File.delete(counter_filename)
            if block_given?
              yield
            end
          end
        else
          # This is BAD
          raise "Error: reference count missing"
        end

      rescue
        raise

      ensure
        # make sure it unlock the directory
        dir.flock(File::LOCK_UN)
      end
    end
    
    protected

    def get_counter_filename
      return File.join(@dir_name,@usage_filename)
    end

  end
end
