#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require 'optparse'
require 'fileutils'

require 'meshkernel'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite.rb'

$config = nil
$log = nil
$verbose = false
$debug = false
$spool = false
$restore = nil
$altitude_data = nil
$asm_zone = nil

MK2_HOST = "localhost"
MK2_PORT = 11112
VALID_MIN = -999
VALID_MAX = 999
LACK_VALUE_16 = -9999

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config>
  Available options:
    -v --verbose                : verbose mode.
    -s --spool                  : spool rawdata.
    -r --spool file             : restore rawdata.
    -d yyyymmddhh --debug yyyymmddhh : debugtime
    -l LOG --log LOG            : logfile
    -h HOST --host HOST         : mk2 host
    -p PORT --port PORT         : mk2 port
EOF
  exit
end

def isinvalid(v)
  return true if v == nil
  return true if v <= VALID_MIN
  return true if v >= VALID_MAX
  return false
end

#
# input[ft][level][elm]
#
def interpolation_index(input)
  # n時間ピッチを1時間ピッチへ線形内挿
  fts = input.keys.sort
  fts.each_index{|i|
    if i < 1
      next
    end
    ft = fts[i]
    pft = fts[i-1]
    diff_time = (ft - pft) / 3600
    if diff_time == 1
      next
    end
    for j in 1...diff_time
      ift = pft + 3600 * j
      input[ift] = {}
      input[ft].each_key{|lvl|
        input[ift][lvl] = {}
        # 気温
        cv = input[ft][lvl]["Temperature"]
        pv = input[pft][lvl]["Temperature"]
        if isinvalid(cv) || isinvalid(pv)
          input[ift][lvl]["Temperature"] = LACK_VALUE_16
          # 各層の気温INDEX
          input[ift][lvl]["INDEX"] = -1
        else
          iv = ((diff_time-j) * pv + j * cv ) / diff_time
          input[ift][lvl]["Temperature"] = iv
          # 各層の気温INDEX
          input[ift][lvl]["INDEX"] = temp2index(iv)
        end
        # ジオポテンシャル高度
        cv = input[ft][lvl]["GeopotentialHeight"]
        pv = input[pft][lvl]["GeopotentialHeight"]
        iv = ((diff_time-j) * pv + j * cv ) / diff_time
        input[ift][lvl]["GeopotentialHeight"] = iv
      }
    end
  }
end

#
# 気温INDEX(地表気圧面) > それより上層の気温INDEXの場合
# 最終気温INDEX=（地表面気圧よりUpperのMIN気温INDEXから上位1位＋2位＋気温INDEX（地表気圧面））/3
#
# lvl1 : 地表気圧面+1
# index: 地表気圧面のiNDEX
# lvldata[level][elm]
#
def check_index(lvl1,index,lvldata,asmid,ft)
  if index < 0
    return index
  end
  upper = []
  start = false
  $config["mk2_pressure_level"].each{|lvl|
    if lvl == lvl1
      start = true
    end
    if start && index > lvldata[lvl]["INDEX"] && lvldata[lvl]["INDEX"] >= 0
      upper.push(lvldata[lvl]["INDEX"])
    end
  }
  if upper.size > 0
    if upper.size == 1
      upper.push(index)
    end
    upper.sort!
    index_2 = ((upper[0] + upper[1] + index) / 3.0).round
    $log.write("%s ft=%s upper1=%s upper2=%s org_index=%s new_index=%s" % [ asmid, ft, upper[0], upper[1], index, index_2])
    return index_2
  end
  return index
end

def temp2index(temp)
  if isinvalid(temp)
    return -1
  end
  $config["index_temperature"].each_index{|i|
    if $config["index_temperature"][i] == temp
      return i
    end
    if $config["index_temperature"][i] > temp
      if i == $config["index_temperature"].size - 1
        return i
      end
      if $config["index_temperature"][i+1] < temp
        return $config["index_temperature"][i] - temp < temp - $config["index_temperature"][i+1] ? i :  i + 1
      end
    else
      if i == 0
        return i
      end
    end
  }
end

#
# rawdata[asmid][ft][level][elm]
# indexdata[asmid][ft][elm]
#
def get_temp_index(rawdata)
  indexdata = {}
  rawdata.each_pair{|asmid,ftdata|
    alt_data = $altitude_data[asmid]
    if alt_data == nil
      $log.write("%s altitude data not exist." % [ asmid ])
      next
    end
    indexdata[asmid] = {}
    ftdata.each_pair{|ft,lvldata|
      indexdata[asmid][ft] = {}
      level1 = nil
      # 低→高
      $config["mk2_pressure_level"].each_index{|i|
        level1 = $config["mk2_pressure_level"][i]
        if lvldata[level1]["GeopotentialHeight"] == alt_data["ALT"]
          indexdata[asmid][ft]["Temperature"] = lvldata[level1]["Temperature"]
          break
        elsif lvldata[level1]["GeopotentialHeight"] > alt_data["ALT"]
          if i == 0
            indexdata[asmid][ft]["Temperature"] = lvldata[level1]["Temperature"]
            break
          end
          level0 = $config["mk2_pressure_level"][i-1]
          # 標高差（高-低）
          y1 = lvldata[level1]["GeopotentialHeight"] - lvldata[level0]["GeopotentialHeight"]
          # 気温差（高-低）
          x1 = lvldata[level1]["Temperature"] - lvldata[level0]["Temperature"]
          # 標高差Δ（高-低）
          y2 = (lvldata[level1]["GeopotentialHeight"] - alt_data["ALT"]).to_f
          # 気温差Δ（高-低）
          x2 = (y2 / y1) * x1
          # 気温（高-低）
          indexdata[asmid][ft]["Temperature"] = lvldata[level1]["Temperature"] - x2
          break
        end
      }
      if indexdata[asmid][ft]["Temperature"] == nil
        # あり得ない
        $log.write("%s ft=%s %s" % [ asmid, ft, $config["mk2_pressure_level"].last])
        indexdata[asmid][ft]["Temperature"] = lvldata[$config["mk2_pressure_level"].last]["Temperature"]
        indexdata[asmid][ft]["INDEX"] = temp2index(indexdata[asmid][ft]["Temperature"])
      else
        indexdata[asmid][ft]["INDEX"] = temp2index(indexdata[asmid][ft]["Temperature"])
        indexdata[asmid][ft]["INDEX"] = check_index(level1,indexdata[asmid][ft]["INDEX"],lvldata,asmid,ft)
      end
    }
  }
  return indexdata
end

#
# rawdata[asmid][ft][level][elm]
#
def get_onebase_data(mkConn,btime,inputtable,point_list)
  $log.write("mk2 data read start.")
  # 面データから地点切り出し
  rawdata = {}
  ft_list = mkConn.get_ft_list(inputtable, btime, "Temperature")
  param_list = []
  ft_list.each{|ft|
    $config["mk2_pressure_level"].each{|level|
      param_list.push(MkDataParam.new( ft, level, btime ))
    }
  }
  pd = mkConn.read_point(inputtable, param_list, point_list, ["Temperature","GeopotentialHeight"], false)
  point_list.each_index{|i|
    pid = point_list[i].id
    rawdata[pid] = {}
    param_list.each{|param|
      ft = btime + param.ft
      if rawdata[pid][ft] == nil
        rawdata[pid][ft] = {}
      end
      if rawdata[pid][ft][param.level] == nil
        rawdata[pid][ft][param.level] = {}
      end
      elm_data = pd.get_data(param,"Temperature")
      if isinvalid(elm_data[i])
        rawdata[pid][ft][param.level]["Temperature"] = LACK_VALUE_16
      else
        rawdata[pid][ft][param.level]["Temperature"] = elm_data[i] - 273.15
      end
      elm_data = pd.get_data(param,"GeopotentialHeight")
      rawdata[pid][ft][param.level]["GeopotentialHeight"] = elm_data[i]
      # 各層の気温INDEX
      rawdata[pid][ft][param.level]["INDEX"] = temp2index(rawdata[pid][ft][param.level]["Temperature"])
    }
    interpolation_index(rawdata[pid])
  }
  # 保存
  #
  # rawdata[asmid][ft][level][elm]
  #
  if $spool
    $log.write("save rawdata.")
    savedir = $config["spool_dir"] + $config["msm_raw_temp_index"]
    if !File.exist?(savedir)
      FileUtils.mkdir(savedir)
    end
    savefile = "%s/%s.pst" % [savedir,Time.now.strftime("%Y%m%d%H%M%S")]
    dbdata = PStore.new(savefile)
    dbdata.transaction() do
      dbdata['root'] = rawdata
    end
    spath = savedir + "/*.pst"
    day = Time.now
    day = day - $config["rawdata_expire"] * 3600 * 24
    Dir.glob(spath){|fnam|
      if (day <=> File.mtime(fnam)) == 1
        FileUtils.remove(fnam)
      end
    }
  end
  return rawdata
end

#
# indexdata[asmid][ft][elm]
#
def make_spool_data(mkConn,point_list,inputtable,latesttime)
  # 各層の生データを読む
  rawdata = {}
  $log.write("basetime=%s" % [ latesttime.to_s ])
  if $restore != nil
    $log.write("restore rawdata.")
    dbdata = PStore.new($restore)
    dbdata.transaction() do
      rawdata = dbdata['root']
    end
  else
    rawdata = get_onebase_data(mkConn,latesttime,inputtable,point_list)
  end
  if rawdata.size < 1
    return rawdata
  end
  # 地表面気圧の気温INDEX
  indexdata = get_temp_index(rawdata)
  return indexdata
end

begin
  opt = OptionParser.new
  host = MK2_HOST
  port = MK2_PORT
  logfile = nil
  debugtime = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-s', '--spool', TrueClass){|v| $spool = v}
    opt.on('-r FILE', '--rst FILE'){|v| $restore = v}
    opt.on('-d yyyymmddhhmm', '--debug yyyymmddhh'){|v| debugtime = v}
    opt.on('-l LOG', '--log LOG'){|v| logfile = v}
    opt.on('-h HOST', '--host HOST'){|v| host = v}
    opt.on('-p PORT', '--port PORT'){|v| port = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 1)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
  $log.write("spool data read start.")
  # 寒候期テーブルのスプールを読む
  rd_table_winter = nil
  dbdata = PStore.new($config["srf_spool_dir"] + $config["rd_table_winter_spool"])
  dbdata.transaction() do
    rd_table_winter = dbdata['root']
  end
  if rd_table_winter == nil || rd_table_winter.size < 1
    $log.write("%s data not spooled." % [$config["rd_table_winter_spool"]])
    return
  end
  $asm_zone = rd_table_winter["asm_zone"].keys
  # altitude
  dbdata = PStore.new($config["spool_dir"] + $config["fcasjp_altitude_spool"])
  dbdata.transaction() do
    $altitude_data = dbdata['root']
  end
  if $altitude_data == nil
    $log.write("fcasjp spool file not exist.")
    exit
  end
  # mkpointのリスト作成
  point_list = []
  $asm_zone.each{|asmid|
    if $altitude_data[asmid] == nil
      $log.write("ASM_ID=%s not exist in fcasjp spool file." % [ asmid ])
    else
      $log.write("%s LATD=%s LOND=%s" % [ asmid,$altitude_data[asmid]["LATD"],$altitude_data[asmid]["LOND"] ]) if $verbose
      point_list.push(MkPoint.new(asmid,$altitude_data[asmid]["LATD"],$altitude_data[asmid]["LOND"]))
    end
  }
  # スプールデータ生成
  mkConn = MkConnection.new( host, port )
  inputtable = $config["mk2_msm_table"]
  # 最新時刻を取得
  latesttime = nil
  if debugtime != nil && debugtime.size == 10
    latesttime = Time.gm(debugtime[0..3].to_i, debugtime[4..5].to_i, debugtime[6..7].to_i, debugtime[8..9].to_i, 0, 0)
    $log.write("msm debugtime=%s" % [latesttime.to_s])
  else
    latesttime = mkConn.get_latest_time(inputtable)
  end
  ft_list = mkConn.get_ft_list(inputtable, latesttime, "Temperature")
  if ft_list.size < 14
    $log.write("msm latesttime=%s data import not completed." % latesttime)
    $log.write("[%s]" % ft_list.join(","))
    latesttime -= 3600 * 3
  end
  savedata = make_spool_data( mkConn, point_list,inputtable,latesttime )
  if savedata == nil || savedata.size < 1
    $log.write("no dat to spool.")
    exit
  end
  # 保存
  #
  # indexdata[asmid][ft][elm]
  #
  dbdata = PStore.new($config["spool_dir"] + $config["msm_adjust_temp_index"])
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
