class LogWrite
  def initialize(logfile="", num=2, size=1000000)
    @logfile = logfile
    @num = num
    @size = size
    if(@logfile == "" || @logfile == nil)
      @log = STDOUT
    else
      @log = open(@logfile, "a")
      logfile_rename()
    end

    @log.puts "***** Logging start at #{nowtime} pid=#{$$} *****"
  end

  def nowtime
    return Time.now.strftime("%Y/%m/%d %H:%M:%S")
  end

  def logfile_rename()
    @log.close
    if(File.exist?(@logfile) == true)
      if(File.size(@logfile) > @size)
        @num.step(1,-1){|i|
          oldlog = @logfile + ".#{i-1}"
          newlog = @logfile + ".#{i}"
          if(File.exist?(oldlog) == false)
            next
          end
          File.rename(oldlog,newlog)
        }
        log_bkp = @logfile + ".0"
        File.rename(@logfile,log_bkp)
      end
    end
    @log = open(@logfile, "a")
  end

  def write(str)
    if(@logfile != "" && @logfile != nil)
      logfile_rename()
    end
    @log.puts "#{nowtime()} : #{str}"
    @log.flush
  end

  def exit
    @log.close
  end
end
