#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require 'optparse'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'simplexml'
require 'logwrite.rb'

$config = nil
$log = nil
$verbose = false
$debug = false

$asm_point_list = []

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <input> <config>
  Available options:
    -v --verbose                : verbose mode.
    -d --debug                  : debug
    -l LOG --log LOG            : logfile
EOF
  exit
end

def parse_xml(xmlfile)
  maxalt = -9999
  maxaid = ""
  sp = XML_SimpleParse.new(xmlfile)
  parsedata = {}
  sp.each_block('point'){|r|
    asmid = r['ASM_ID']
    parsedata[asmid] = {}
    parsedata[asmid]['LATD'] = r['LATD'].to_f
    parsedata[asmid]['LOND'] = r['LOND'].to_f
    alt = r['ALT'].to_f
    parsedata[asmid]['ALT'] = alt
    if maxalt < parsedata[asmid]['ALT']
      maxalt = parsedata[asmid]['ALT']
      maxaid = asmid
    end
  }
  $log.write("%s=%s" % [maxaid,maxalt])
  return parsedata
end

begin
  opt = OptionParser.new
  logfile = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
    opt.on('-l LOG', '--log LOG'){|v| logfile = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 2)
  $config = YAML.load_file(ARGV[1])
  $log =  LogWrite.new(logfile)
  parsedata = parse_xml(ARGV[0])
  dbdata = PStore.new($config["spool_dir"] + $config["fcasjp_altitude_spool"])
  dbdata.transaction() do
    if parsedata != nil
      # xmlを解析
      dbdata['root'] = parsedata
    end
  end
  $log.write("***** proc end normally *****")
rescue => e
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
