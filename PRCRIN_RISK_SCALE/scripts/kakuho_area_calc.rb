#!/usr/local/bin/ruby

require 'optparse'
require 'yaml'
require 'pstore'

require 'wlib'
require 'gribrw'

$mypath  = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite'

$debug   = false
$verbose = false
$config = nil
$marshal_data = {}
$announced = nil
$log = nil

def usage()
$stderr.puts <<EOF
  Usage: #{__FILE__} [OPTION] <inputfile> <config> <groupid>
  Available options:
     -L FILE --logfile FILE : logfile
     -d, --debug   : debug mode
     -v, --verbose : verbose mode.
EOF
  exit 1
end

#
# 確報の読み込み
#
def read_kakuho(kakuho, pary)
  # savedata[ft][pid][雨量配列]
  savedata = {}
  $log.write(kakuho)
  ifp = open(kakuho, "r+")
  buf = ifp.read(4096)
  ihd = WniHeader.new
  ihd.read(buf)
  $announced = ihd.announced_date
  created = ihd.created_date
  # localtimeなので注意
  $log.write("announced=%s" % $announced.to_s)
  $log.write("created=%s" % created.to_s)
  ifp.seek(ihd.header_size)
  g2 = GribV2.new
  buf = ifp.read
  g2.prepare(buf, true)
  ifp.close
  # 1回目と2回目の両方の計算に必要なデータを取る
  # basetime50分のときはbasetimeから3時間
  # その他はbasetimeの正時から3時間
  endtime = Time.local($announced.year, $announced.month, $announced.day, $announced.hour, 0, 0)
  if $announced.min == 50
    endtime = $announced + 3600 * 3
  else
    endtime += 3600 * 3
  end
  $log.write("endtime=%s" % endtime.to_s)
  while true
    sec = nil
    begin
    sec = g2.load
    rescue => e
      $log.write("GribV2: #{e.message} #{f}")
      break
    end
    break if(sec < 0)
    sec1 = g2.section(1)
    initime = Time.utc(
                        sec1["year"].value,   sec1["month"].value,
                        sec1["day"].value,    sec1["hour"].value,
                        sec1["minute"].value, sec1["second"].value
                      )
    $log.write("initime = %s" % initime.to_s)
    sec3 = g2.section(3)
    xsize = sec3["number_of_points_of_i"].value
    ysize = sec3["number_of_points_of_j"].value
    y_first = sec3["latitude_of_first_grid_point"].value  / 1000000.0
    y_last  = sec3["latitude_of_last_grid_point"].value   / 1000000.0
    x_first = sec3["longitude_of_first_grid_point"].value / 1000000.0
    x_last  = sec3["longitude_of_last_grid_point"].value  / 1000000.0
    xgird = sec3["i_direction_increment"].value / 1000000.0
    ygrid = sec3["j_direction_increment"].value / 1000000.0
    sec4 = g2.section(4)
    vt = initime + (sec4["forecast_time"].value * 60)
    if vt > endtime
      break
    end
    vtstr = vt.utc.strftime("%Y-%m-%d %H:%M:%S")
    $log.write("#{vtstr}")
    savedata[vt] = {}
    dt = g2.data
    pary.each{|point|
      savedata[vt][point] = []
      mesh_list = $marshal_data[point]
      mesh_list.each{|mesh|
        pos = mesh[0] + mesh[1] * xsize
        savedata[vt][point].push(dt[pos])
      }
    }
  end
  return savedata
end

def add_one_ft(ftsft,savedata)
  addftdata = {}
  ftsft.each{|ft|
    savedata[ft].each_pair{|pid,ary|
      if addftdata[pid] == nil
        addftdata[pid] = {}
        addftdata[pid]["add"] = []
      end
      ary.each_index{|i|
        if addftdata[pid]["add"][i] == nil
          addftdata[pid]["add"][i] = ary[i]
        else
          addftdata[pid]["add"][i] += ary[i]
        end
      }
    }
  }
  return addftdata
end

def calc_kakuho(savedata,num)
  # まず出力FT毎に足し合わせる
  # savedata[ft][pid][雨量配列]
  # から
  # calcdata[ft1,ft2,ft3][pid]["add"][足し合わせた雨量配列]
  #                           ["max"][最大値]
  # を作成
  calcdata = []
  # 後ろから
  fts = savedata.keys.sort.reverse
  # 1回目のbasetime50分以外(0分)と
  # 2回目のbasetime50分(50分)は最初から
  startidx = 0
  if num == 1
    if $announced.min == 50
      # 1回目のbasetime50分(0分)は6つめから
      startidx = 5
    end
  else
    if $announced.min != 50
      # 2回目のbasetime50分以外(50分)は2つめから
      startidx = 1
    end
  end
  $log.write("startidx %d" % startidx)
  ftsft1 = fts[startidx+12..-1]
  $log.write("ft1 %s" % ftsft1.join(","))
  calcdata.push(add_one_ft(ftsft1,savedata))
  # 出力ft2は6つめから6個
  ftsft2 = fts[startidx+6,6]
  $log.write("ft2 %s" % ftsft2.join(","))
  calcdata.push(add_one_ft(ftsft2,savedata))
  # 出力ft3は開始から6個
  ftsft3 = fts[startidx,6]
  $log.write("ft3 %s" % ftsft3.join(","))
  calcdata.push(add_one_ft(ftsft3,savedata))
  $log.write("calc start")
  # 最大と平均を計算
  calcdata.each{|ftdata|
    ftdata.each_pair{|key,value|
      ftdata[key]["max"] = value["add"].max.truncate
    }
  }
  $log.write("calc end")
  return calcdata
end

begin
  opt = OptionParser.new
  logfile = nil
  begin
    opt.on('-L FILE', '--logfile FILE'){|v| logfile = v}
    opt.on('-d', '--debug',   TrueClass){|v| $debug   = v}
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  if(ARGV.size != 3)
    usage()
  end
  $log = LogWrite.new(logfile)
  $config = YAML.load_file(ARGV[1])
  # 顧客別1kmメッシュ群（緯度経度）紐付けテーブル（Marshal）を読む。
  meshfile = "%s%s_%d.pst" % [$config["area_mesh_kakuho_dir"],$config["area_mesh_kakuho_name"],ARGV[2]]
  dbdata = PStore.new(meshfile)
  dbdata.transaction() do
    $marshal_data = dbdata['root']
  end
  if $marshal_data == nil || $marshal_data.size < 1
    print "table_area spool data not exist\n"
    exit
  end
  pary = $marshal_data.keys
  #
  # read GRIB2
  #
  kakuho = ARGV[0]
  savedata = read_kakuho(kakuho, pary)
  # calc & save
  $log.write("calc 1")
  calcdata = calc_kakuho(savedata,1)
  kakuho_spool = $config["spool_kakuho_dir"] + ARGV[2] + "/" + $announced.strftime("%Y%m%d%H%M_1.pst")  # 1回目
  dbdata = PStore.new(kakuho_spool)
  dbdata.transaction() do
    dbdata['root'] = calcdata
  end
  $log.write("calc 2")
  calcdata = calc_kakuho(savedata,2)
  kakuho_spool = $config["spool_kakuho_dir"] + ARGV[2] + "/"  + $announced.strftime("%Y%m%d%H%M_2.pst")  # 2回目
  dbdata = PStore.new(kakuho_spool)
  dbdata.transaction() do
    dbdata['root'] = calcdata
  end
  if !$debug
    $log.write("***** output end normally delete old files *****")
    spath = $config["spool_kakuho_dir"] + ARGV[2] + "/" + "*.pst"
    expire = $config["spool_kakuho_expire"]
    day = Time.now
    day = day - expire * 60
    Dir.glob(spath) {|fnam|
      if (day <=> File.mtime(fnam)) == 1
        File.delete(fnam)
      end
    }
  end
  $log.write("***** proc end normally *****")
rescue => e
  $log.write("#{e.backtrace[0]}: #{e.message} (#{e.class})")
  e.backtrace.each_index{|i|
    $log.write("\tfrom #{e.backtrace[i]}") if i != 0
  }
end
