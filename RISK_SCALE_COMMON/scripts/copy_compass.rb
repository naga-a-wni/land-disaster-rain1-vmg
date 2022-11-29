#!/usr/local/bin/ruby

require 'pstore'
require 'yaml'

def cmd_copy(sorc,dest)
  cmd1 = "cp %s %s" % [sorc,dest]
  p cmd1
  rc = system(cmd1)
  if rc == false
    print "command failed\n"
  end
end

if ARGV.size < 3
  print "Usage:copy_compass.rb <input> <config> <rain|wind>\n"
  exit
end
$config = YAML.load_file(ARGV[1])
if ARGV[2] == "wind"
  dbdata = PStore.new($config["spool_compass_wind"])
  dbdata.transaction() do
    savedata = dbdata['root']
    cmd_copy(ARGV[0],$config["raw_compass_wind"])
  end
else
  dbdata = PStore.new($config["spool_compass_rain"])
  dbdata.transaction() do
    savedata = dbdata['root']
    cmd_copy(ARGV[0],$config["raw_compass_rain"])
  end
end
print "***** proc end normally *****\n"
