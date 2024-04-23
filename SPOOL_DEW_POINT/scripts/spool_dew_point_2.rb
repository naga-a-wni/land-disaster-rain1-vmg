#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'

require 'wlib'

$config = nil
$debug = false

def file_available(fname)
  if File.exist?(fname)
    s = File::stat(fname)
      if s.size > 0
        return true
      end
      return false
  end
  return false
end

# スプール後に平均に上書き
#   zonedata : zonedata[zoneid][ftm]
#
def write_spool_data(dewtmp_new)
  if dewtmp_new == nil || dewtmp_new.size < 1
    print "new dewtemp data not exist\n"
    return
  end
  spool_fname = $config["spool_path"] + $config["spool_avg"]
  dewtmp_avg = nil
  if file_available(spool_fname)
    File.open(spool_fname, "r+"){|f|
      f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
      dewtmp_avg = nil
      begin
        dewtmp_avg = Marshal.restore(f)
      rescue
        print "spool file : %s is not exist\n" % [ spool_fname ]
      end
      f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
    }
  end
  if dewtmp_avg == nil || dewtmp_avg.size < 1
    print "avg data not exist %s\n" % spool_fname
    dewtmp_avg = {}
  end
  dewtmp_new.each_pair{|zoneid,ftdata|
    if dewtmp_avg[zoneid] == nil
       print "zoneid=%s not exist in avg\n" % [zoneid]
       dewtmp_avg[zoneid] = {}
    end
    ftdata.each_pair{|ft,value|
#      if dewtmp_avg[zoneid][ft] == nil
#        print "zoneid=%s ft=%s not exist in avg\n" % [zoneid,ft.to_s]
#      end
      if value > $config["dewtmp_max"] || value < $config["dewtmp_min"]
        print "zoneid=%s invalid value=%s\n" % [zoneid,value.to_s]
      else
        dewtmp_avg[zoneid][ft] = value / 10.0
      end
    }
  }
  File.open(spool_fname, "w"){|f|
    f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
    Marshal.dump(dewtmp_avg, f)
    f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
  }
end

#
#  のASMポイントデータの全ftを区間に変換
# 区間に対応するASMポイントが代表値がない場合はnil
#
# input -
#   rudata   : rudata["announced_date"]
#              rudata["DEWTMP"][pno][ftm]
#
# output -
#   zonedata : zonedata["announced_date"]
#              zonedata["DEWTMP"][zoneid][ftm]
#
def asmpoint2rdzone(rudata)
  datas = rudata["DEWTMP"]
  zones = {}
  dbdata = PStore.new($config["zone_path"])
  dbdata.transaction() do
    zones = dbdata['root']
  end
  zonedata = {}
  zonedata["announced_date"] = rudata["announced_date"]
  zonedata["DEWTMP"] = {}
  # ASMポイントデータ変換
  $allzone = zones.keys.sort
  for zid in $allzone
    onez = zones[zid]
    next if(!datas.has_key?(onez["ASM_ID_daihyo"]))
    zonedata["DEWTMP"][zid] = {}
    datas[onez["ASM_ID_daihyo"]].each_pair{|ft,value|
      zonedata["DEWTMP"][zid][ft] = value
    }
  end
  if $debug
    fs = File.open("zonedew.txt",'w')
    zonedata["DEWTMP"].each_pair{|zid,ftdata|
      ftdata.each_pair{|ft,value|
        fs.print "zid=%s dew=%f\n" % [zid,value]
      }
    }
    fs.close
  end
  print "new dewtemp announced=%s zone_count=%d\n" % [ zonedata["announced_date"].to_s, zonedata["DEWTMP"].size ]
  return zonedata
end

#
# RUフォーマット
# announced_date:[year:INT16,mon:INT8,day:INT8,hour:INT8,min:INT8,sec:INT8],
# area_count:INT32,
# area_data:{area_count}[
#   AREA:STR,
#   LCLID:STR,
#   FCAS_count:INT16,
#   FCAS_data:{FCAS_count}[
#     FCAS_date :[year:INT16,mon:INT8,day:INT8,hour:INT8,min:INT8,sec:INT8],
#     DEWTMP:INT16    10倍値
#   ]
# ]
# 読み出した露点データの保存形
# rudata["announced_date"]
# rudata["DEWTMP"][pno][ftm] = 露点
#
def readrudata(rufile)
  rudata = {}
  gen = GenRw.open(rufile)
  rh = gen.get_header_copy
  ref = gen.get_value_ref
  rudata["announced_date"] = ref["announced_date"].get_value_time
  area_count = ref["area_count"]
  print "new dewtemp area_count=%d\n" % [ area_count ]
  rudata["DEWTMP"] = {}
  # AREA=ASMIDのループ
  for i in 0...area_count
    area_id = ref["area_data"][i]["AREA"]
    rudata["DEWTMP"][area_id] = {}
    # 時間予測値のループ
    fcas_count = ref["area_data"][i]["FCAS_count"]
    for j in 0...fcas_count
      fcasd = ref["area_data"][i]["FCAS_data"][j]["FCAS_date"].get_value_time
      rudata["DEWTMP"][area_id][fcasd] = ref["area_data"][i]["FCAS_data"][j]["DEWTMP"]
    end
  end
  return rudata
end

def main()
  if ARGV.size != 2
    puts "Usage: #{__FILE__} <configfilepath> <RUfliepath>"
    exit
  end
  print "start=%s\n" % Time.now.to_s
  $config = YAML.load_file(ARGV[0])
  rudata = readrudata(ARGV[1])
  zonedata = asmpoint2rdzone(rudata)
  spool_fname = $config["spool_path"] + $config["spool_new"]
  File.open(spool_fname, "w"){|f|
    f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
    asmdata = []
    asmdata.push(zonedata)
    Marshal.dump(asmdata, f)
    f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
  }
  write_spool_data(zonedata["DEWTMP"])
  print "end=%s\n" % Time.now.to_s
end
main()
