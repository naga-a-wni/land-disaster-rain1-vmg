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

# $asm_point_list[contxt][asmid]['LCLID'] = 値
#                               ['LNAME'] = 値
# contxtが保存ファイル名。スプールデータはasmidがキー
$asm_point_list = {}

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
  sp = XML_SimpleParse.new(xmlfile)
  parsedata = {}
  sp.each_block('point'){|r|
    contxt = r['CONTXT']
    if $config["CONTXT"].index(contxt) == nil
      next
    end
    asmid = r['ASM_ID']
    $asm_point_list[contxt][asmid] = {}
    $asm_point_list[contxt][asmid]['LCLID'] = r['LCLID']
    $asm_point_list[contxt][asmid]['LNAME'] = r['LNAME']
  }
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
  $config["CONTXT"].each{|contxt|
    $asm_point_list[contxt] = {}
  }
  $log =  LogWrite.new(logfile)
  parsedata = parse_xml(ARGV[0])
  $asm_point_list.each_pair{|contxt,parsedata|
    fname = "%s%s.pst" % [$config["spool_dir"],contxt]
    dbdata = PStore.new(fname)
    dbdata.transaction() do
      dbdata['root'] = parsedata
    end
  }
  $log.write("***** proc end normally *****")
rescue => e
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
