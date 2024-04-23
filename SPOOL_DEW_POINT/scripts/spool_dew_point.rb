#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'

require 'wlib'

$config = nil
$allzone = []
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

#
# モデル露点RU 411023266-9 のASMポイントデータの全ftを区間に変換
# 区間に対応するASMポイントが代表値がない場合はnil
#
# input -
#   rudata   : rudata["model_name"]
#              rudata["announced_date"]
#              rudata["DEWTMP"][pno][ftm]
#
# output -
#   zonedata : zonedata["model_name"]
#              zonedata["announced_date"]
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
  zonedata["model_name"] = rudata["model_name"]
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
  return zonedata
end

# スプール
def spool_data(rudata)
  zonedata = asmpoint2rdzone(rudata)
  all_models ={"OWN"=>$config["spool_own"],"MSM"=>$config["spool_msm"],"GSM"=>$config["spool_gsm"],"GFS"=>$config["spool_gfs"]}
  use_models = all_models.keys
  p use_models
  use_models.each{|key|
    if zonedata["model_name"] == key
      value = all_models[key]
      spool_fname = $config["spool_path"] + value
      if !file_available(spool_fname)
        print "spool file : %s is not exist\n" % [ spool_fname ]
        File.open(spool_fname, "w"){|f|
          f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
          asmdata = []
          asmdata.push(zonedata)
          Marshal.dump(asmdata, f)
          f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
        }
        next
      end
      File.open(spool_fname, "r+"){|f|
        f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
        asmdata = nil
        begin
          asmdata = Marshal.restore(f)
        rescue
          print "spool file : %s is not exist\n" % [ spool_fname ]
        end
        if(asmdata == nil)
          asmdata = []
          asmdata.push(zonedata)
        else
          if asmdata.size > 1
            if asmdata[0]["announced_date"] > asmdata[1]["announced_date"]
              asmdata[1] = zonedata
            else
              asmdata[0] = zonedata
            end
          else
            asmdata.push(zonedata)
          end
        end
        asmdata.each{|data|
          print "model %s announced=%s\n" % [ key, data["announced_date"].to_s ]
        }
        f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
        File.open(spool_fname, "w"){|f|
          f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
          Marshal.dump(asmdata, f)
          f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
        }
      }
    end
  }
end

# モデル露点RU 411023266-9 のフォーマット
# announced_date:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
# element_count:INT16,
# element:{element_count}[
#   name:STR,
#   unit:STR,
#   comment:STR
# ],
# area_count:INT32,
# forecast_count:INT32,
# area_data:{area_count}[
#   AREA:STR,
#   CONTXT:STR,
#   LCLID:STR,
#   forecast_data:{forecast_count}[
#     forecast_date:[year:INT16,month:INT8,day:INT8,hour:INT8],
#     DEWTMP:FLOAT32
#   ]
# ]
#
# 読み出した露点データの保存形
# rudata["model_name"]
# rudata["announced_date"]
# rudata["DEWTMP"][pno][ftm] = 露点
#
def readrudata(rufile)
  rudata = {}
  gen = GenRw.open(rufile)
  rh = gen.get_header_copy
  rudata["model_name"] = rh.data_name.split("_").last
  ref = gen.get_value_ref
  rudata["announced_date"] = ref["announced_date"].get_value_time
  area_count = ref["area_count"]
  fcas_count = ref["forecast_count"]
  rudata["DEWTMP"] = {}
  # AREA=ASMIDのループ
  for i in 0...area_count
    area_id = ref["area_data"][i]["AREA"]
    rudata["DEWTMP"][area_id] = {}
    # 時間予測値のループ
    rudata["DEWTMP"][area_id] = {}
    for j in 0...fcas_count
      fcasd = ref["area_data"][i]["forecast_data"][j]["forecast_date"].get_value_time
      rudata["DEWTMP"][area_id][fcasd] = ref["area_data"][i]["forecast_data"][j]["DEWTMP"]
    end
  end
  return rudata
end

# スプールデータ読み出し
def read_spool_data()
  dataary = []
  all_models ={"OWN"=>$config["spool_own"],"MSM"=>$config["spool_msm"],"GSM"=>$config["spool_gsm"],"GFS"=>$config["spool_gfs"]}
  use_models = $config["merge_models"]
  p use_models
  if use_models == nil
    use_models = all_models.keys
  end
  use_models.each{|key|
    value = all_models[key]
    spool_fname = $config["spool_path"] + value
    if !file_available(spool_fname)
      print "spool file : %s is not exist\n" % [ spool_fname ]
      next
    end
    File.open(spool_fname, "r+"){|f|
      f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
      asmdata = nil
      begin
        asmdata = Marshal.restore(f)
      rescue
        print "spool file : %s is not exist\n" % [ spool_fname ]
      end
      if(asmdata != nil)
        dataary.concat(asmdata)
        asmdata.each{|data|
          print "model %s announced=%s\n" % [ key, data["announced_date"].to_s ]
        }
      end
      f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
    }
  }
  print "spooled data count=%d\n" % [dataary.size]
  return dataary
end

# 露点温度４モデル（最新ベース＋前回ベース）の平均を出す。
#
# 露点データの保存形
# dataary["model_name"]
# dataary["announced_date"]
# dataary["DEWTMP"][pno][ftm]
#
def get_dewtmp_avg(dataary)
  # [pno][ftm] = [値配列]を作成
  calcdata = {}
  for pno in $allzone
    dataary.each{|modeldata|
      if modeldata["DEWTMP"][pno] != nil
        if calcdata[pno] == nil
          calcdata[pno] = {}
        end
        modeldata["DEWTMP"][pno].each_pair{|ft,value|
          if calcdata[pno][ft] == nil
            calcdata[pno][ft] = []
          end
          if modeldata["DEWTMP"][pno][ft] != -9999
            calcdata[pno][ft].push(value)
          end
        }
      end
    }
  end
  # 平均値計算 [pno][ftm] = 平均値を作成
  avgdata = {}
  calcdata.each_pair{|pno,ftdata|
    if avgdata[pno] == nil
      avgdata[pno] = {}
    end
    ftdata.each_pair{|ft,ary|
      if ary.size < 1
        next
      end
      ttl = 0
      ary.each{|value|
        ttl += value
      }
      avgdata[pno][ft] = ttl / ary.size
    }
  }
  # 新データで上書き
  spool_fname = $config["spool_path"] + $config["spool_new"]
  dewtmp_new = nil
  if file_available(spool_fname)
    File.open(spool_fname, "r+"){|f|
      f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
      dewtemp = nil
      begin
        dewtemp = Marshal.restore(f)
      rescue
        print "spool file : %s is not exist\n" % [ spool_fname ]
      end
      if dewtemp != nil && dewtemp[0] != nil
        print "new dewtemp announced=%s\n" % [ dewtemp[0]["announced_date"].to_s ]
        dewtmp_new = dewtemp[0]["DEWTMP"]
      end
      f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
    }
  end
  if dewtmp_new != nil && dewtmp_new.size > 0
    dewtmp_new.each_pair{|zoneid,ftdata|
      if avgdata[zoneid] == nil
        print "zoneid=%s not exist in avg\n" % [zoneid]
        avgdata[zoneid] = {}
      end
      ftdata.each_pair{|ft,value|
#        if avgdata[zoneid][ft] == nil
#          print "zoneid=%s ft=%s not exist in avg\n" % [zoneid,ft.to_s]
#        end
        if value > $config["dewtmp_max"] || value < $config["dewtmp_min"]
          print "zoneid=%s invalid value=%s\n" % [zoneid,value.to_s]
        else
          avgdata[zoneid][ft] = value / 10.0
        end
      }
    }
  else
    print "new dewtemp data not exist %s\n" % [spool_fname]
  end
  spool_fname = $config["spool_path"] + $config["spool_avg"]
  File.open(spool_fname, "w"){|f|
    f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
    Marshal.dump(avgdata, f)
    f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
  }
end

def main()
  if ARGV.size != 2
    puts "Usage: #{__FILE__} <configfilepath> <RUfliepath>"
    exit
  end
  print "start=%s\n" % Time.now.to_s
  $config = YAML.load_file(ARGV[0])
  rudata = readrudata(ARGV[1])
  spool_data(rudata)
  # 露点温度スプールデータを読み出す
  dataary = read_spool_data()
  # 露点温度４モデル（最新ベース＋前回ベース）の平均を出す
  get_dewtmp_avg(dataary)
  print "end=%s\n" % Time.now.to_s
end
main()
