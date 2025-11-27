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

$rd_table_winter = nil
$zone_data = nil
# $asm_point_list[asmid]['要素名'] = 値
$asm_point_list = nil

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config>
  Available options:
    -v --verbose                : verbose mode.
    -d --debug                  : debug
    -l LOG --log LOG            : logfile
EOF
  exit
end

def parse_xml(xmlfile)
  sp = XML_SimpleParse.new(xmlfile)
  parsedata = []
  sp.each_block('point'){|r|
    parsedata.push(r['LCLID'])
  }
  return parsedata
end

# savedata[zoneid]['LCLID'] = 値
#                 ['LNAME'] = 値
#                 ['E'] = 値
def get_link_obsid(route_e_points)
  savedata = {}
  $zone_data.each_pair{|zid,zdata|
    asm_id_daihyo = zdata["ASM_ID_daihyo"]
    if zid  =~ /^51/
      adata = $asm_point_list[asm_id_daihyo]
      if adata == nil
        $log.write("zoneid=%s ASM_ID_daihyo=%s not exist in FCASJP.xml" % [zid,asm_id_daihyo])
        savedata[zid] = {}
        savedata[zid]["LCLID"] = 0
        savedata[zid]["E"] = 0
      else
        adata["E"] = 0
        if route_e_points.index(adata['LCLID']) != nil
          adata["E"] = 1
        end
        savedata[zid] = adata
      end
    end
  }
  return savedata
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
  usage() if(ARGV.size < 1)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
  # FCASJPのスプールを読む
  dbdata = PStore.new($config["spool_dir"] + $config["fcasjp_honsi_spool"])
  dbdata.transaction() do
    $asm_point_list = dbdata['root']
  end
  if $asm_point_list == nil || $asm_point_list.size < 1
    $log.write("%s data not spooled." % [$config["fcasjp_honsi_spool"]])
    exit
  end
  # 寒候期テーブルのスプールを読む
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_winter_spool"])
  dbdata.transaction() do
    $rd_table_winter = dbdata['root']
  end
  if $rd_table_winter == nil || $rd_table_winter.size < 1
    $log.write("%s data not spooled." % [$config["rd_table_winter_spool"]])
    exit
  end
  $zone_data = $rd_table_winter["zone_elements"]
  # Eルート地点情報
  route_e_points = parse_xml($config["honsi_route_e_point_table"])
  if route_e_points.size < 1
    $log.write("%s not exist." % [$config["honsi_route_e_point_table"]])
  end
  # 紐づけ
  savedata = get_link_obsid(route_e_points)
  # 保存
  dbdata = PStore.new($config["spool_dir"] + $config["honsi_winter_obsid_spool"])
  dbdata.transaction() do
    dbdata['root'] = savedata
  end
  $log.write("***** proc end normally *****")
rescue => e
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
