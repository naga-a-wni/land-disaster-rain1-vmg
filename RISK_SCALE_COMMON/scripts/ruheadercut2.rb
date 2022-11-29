#!/usr/local/bin/ruby

require 'wlib'

def get_body()
  if ARGV.size < 1
    print "Usage:#{__FILE__} <input> [outpur]\n"
    return
  end
  # RUファイルのボディのみコピー
  srcpath = ARGV[0]
  if !File.exist?(srcpath)
    print "RU flie not found\n"
    return
  end
  ifp = open(srcpath)
  buf = ifp.read(1024)
  ihd = WniHeader.new
  ihd.read(buf)
  p ihd.header_size
  ifp.seek(ihd.header_size)
  contents = ifp.read
  destpath = srcpath + ".body"
  if ARGV.size > 1
    destpath = ARGV[1]
  end
  dest = open(destpath,"wb")
  if !dest.flock( File::LOCK_EX )
    log.write("File [#{destpath}] lock failed.")
  end
  dest.write(contents.strip)
  dest.flock( File::LOCK_UN )
  dest.close
end
get_body()
