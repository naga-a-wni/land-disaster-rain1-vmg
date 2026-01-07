#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'optparse'
require 'yaml'
require 'pstore'

require 'wlib'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite.rb'

$config = nil
$log = nil
$debug = false
$verbose = false

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config> <inputru>
  Available options:
    -v, --verbose : verbose mode.
    -d, --debug   : debug mode
    -l LOG --log LOG            : logfile
EOF
  exit
end

#
# input : JB本四 観測情報入力
#
# format         =
# OBSERVATION_TIME:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
# DEL_FLAG:INT8,
# point_count:INT32,
# point_data:{point_count}[
#   OBS_TIME:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
#   LCLID:STR,
#   ZONE:STR,
#   LNAME:STR,
#   WX:INT16,
#   RDCND:INT16,
#   OPRTN:INT16,
#   TEMP_1hour_Mean:INT16,
#   SNWFLL_1hour_Total:INT32,
#   SNWFLL_6hour_Total:INT32,
#   SNWDPT:INT32,
#   WNDDIR_1hour_Mean:INT16,
#   WNDSPD_1hour_Mean:INT32,
#   PRCRIN_1hour_Total:INT32,
#   SILTMP_1hour_Mean:INT16,
#   BRGTMP_1hour_Mean:INT16,
#   TNLTMP_1hour_Mean:INT16,
#   HVIS:STR,
#   HVIS_Num:STR,
#   RSLT:STR,
#   SLV:INT16
# ]
#
def read_ru(ru_file)
  gens = GenRw.open(ru_file)
  ref = gens.get_value_ref
  ru_data = {}
  ru_data["new"] = {}
  ru_data["del"] = {}
  point_count = ref["point_count"]
  for i in 0...point_count
    obs_time = ref["point_data"][i]["OBS_TIME"].get_value_time - 9 * 3600
    zone_id = ref["point_data"][i]["ZONE"]
    $log.write("%s %s\n" % [zone_id,obs_time.to_s])
    if zone_id !~ /^51/
      next
    end
    if ref["DEL_FLAG"] != 0
      $log.write("DEL_FLAG=%s\n" % [ref["DEL_FLAG"]])
      if ru_data["del"][obs_time] == nil
        ru_data["del"][obs_time] = []
      end
      ru_data["del"][obs_time].push(zone_id)
      next
    end
    if ru_data["new"][obs_time] == nil
      ru_data["new"][obs_time] = {}
    end
    if ru_data["new"][obs_time][zone_id] == nil
      ru_data["new"][obs_time][zone_id] = {}
    end
    ru_data["new"][obs_time][zone_id]["RDCND"] = ref["point_data"][i]["RDCND"]
    ru_data["new"][obs_time][zone_id]["RSLT"] = ref["point_data"][i]["RSLT"]
  end
  return ru_data
end

# 観測情報手入力データスプールファイル
# jbhonsi_manualentered[obs_time][zone_id]["RDCND"] = 値
#                                         ["RSLT"] = 値
def main()
  opt = OptionParser.new
  logfile = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug',   TrueClass){|v| $debug   = v}
    opt.on('-l LOG', '--log LOG'){|v| logfile = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 2)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
  # ru読み込み
  ru_data = read_ru(ARGV[1])
  if ru_data["new"].size < 1 && ru_data["del"].size < 1
    $log.write("no available data in inputdata.")
    return
  end
  # 保存
  dbdata = PStore.new($config["spool_dir"] + $config["jbhonsi_manualentered_spool"])
  dbdata.transaction() do
    merge_data = dbdata['root']
    if ru_data["new"].size < 1
      $log.write("no data to add.")
    else
      if merge_data == nil
        merge_data = ru_data["new"]
      else
        # 古いデータ削除
        btimes = merge_data.keys.sort
        latest = btimes.last
        btimes.each{|bt|
          if bt < latest - 3600 * 3
            merge_data.delete(bt)
            $log.write("delete %s" % [bt])
          end
        }
        # 新しいデータ追加
        ru_data["new"].each_key{|bt|
          if merge_data[bt] == nil
            merge_data[bt] = ru_data["new"][bt]
          else
            merge_data[bt].merge!(ru_data["new"][bt])
          end
        }
      end
    end
    if ru_data["del"].size > 0
      # DEL_FLAG処理
      ru_data["del"].each_pair{|btime,zone_ids|
        zone_ids.each{|zid|
          if merge_data[btime] != nil && merge_data[btime][zid] != nil
            $log.write("delete %s %s" % [btime,zid])
            merge_data[btime].delete(zid)
          else
            $log.write("DEL_FLAG %s %s not exist in spool data." % [btime,zid])
          end
        }
      }
    end
    dbdata['root'] = merge_data
  end
  $log.write("***** proc end normally *****")
end
main()
