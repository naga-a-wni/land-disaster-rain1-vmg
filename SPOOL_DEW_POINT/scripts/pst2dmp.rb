#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'

$config = nil

def main()
  if ARGV.size != 1
    puts "Usage: #{__FILE__} <config>"
    exit
  end
  print "start=%s\n" % Time.now.to_s
  $config = YAML.load_file(ARGV[0])
  spool_fname = $config["spool_path"] + $config["spool_avg"]
  dump_fname = File::basename(spool_fname,".pst")
  dump_fname = $config["spool_path"] + dump_fname + ".dmp"
  print "%s\n" % dump_fname
  # 露点温度スプールデータ読み出し
  dewtmp_avg = nil
  dbdata = PStore.new(spool_fname)
  dbdata.transaction() do
    if(dbdata['root'] != nil)
      dewtmp_avg = dbdata['root']
    end
  end
  # dumpに変換
  File.open(dump_fname, "w"){|f|
    f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
    Marshal.dump(dewtmp_avg, f)
    f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
  }
  print "end=%s\n" % Time.now.to_s
end
main()
