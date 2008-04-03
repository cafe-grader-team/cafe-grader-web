module TestHelper

  def read_textfile(fname,max_size=2048)
    begin
      File.open(fname).read(max_size)
    rescue
      nil
    end
  end

end
