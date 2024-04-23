#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require 'optparse'
require 'fileutils'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'wlib'
require 'logwrite.rb'


$config = nil
$log = nil
$verbose = false
$debug = false
$spool = false

$indexdata = nil
$ecmwf_indexdata = nil
$asm_zone = {}

# 変更は雪と天気のみ
# [zone_id][ft]["SNWFLL_1HOUR_TOTAL"]
#              ["WX"]
$adjust_data = {}

# 入力データの欠測値はすべて-9999
LACK_VALUE_16 = -9999

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config> <input>
  Available options:
    -v --verbose                : verbose mode.
    -d --debug                  : debug
    -s --spool                  : spool rawdata.
    -t TAGID --tagid TAGID      : input tagid
    -l LOG --log LOG            : logfile
EOF
  exit
end

#
# 411024529 RD体制判断10V用 短期COMPASS 30%パーセンタイル
#
# announced_date:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
# point_count:INT16,
# point_data:{point_count}[
#   ASM_ID:STR,                     ASM地点
#   SOIL_or_BRG:INT8,               橋が１、土が２、推定値(路観なし)は３
#   FCST_count:INT16,
#   FCST:{FCST_count}[
#     FCSTD:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
#     WX:INT16,                     天気
#     PRCRIN_1HOUR_TOTAL:FLOAT32,   降水量
#     AIRTMP:FLOAT32,               気温
#     SNWFLL_1HOUR_TOTAL:FLOAT32,   降雪量
#     WNDSPD:FLOAT32,               風速
#     WNDDIR:INT8,                  風向
#     RDTMP:FLOAT32,                路温
#     GUSTS:FLOAT32                 瞬間風速
#   ]
# ]
##
def make_adjust_data(input_data)
  # 入力ファイル読み込み
  gr = GenRw.open(input_data)
  refr = gr.get_value_ref
  announced_date = refr["announced_date"].get_value_time
  $log.write("announced_date %s" % [announced_date.to_s])
  if !$debug
    if Time.now - announced_date > 3600 * 78
      $log.write("source ru data too old announced_date=%s." % [announced_date.to_s])
      return
    end
  end
  prec_thds = $config["prec_snow_ratio"].keys.sort
  $log.write("[ %s ]" % [prec_thds.join(",")]) if $verbose
  asm_area_count = refr["point_count"]
  for i in 0...asm_area_count
    asm_id = refr["point_data"][i]["ASM_ID"]
    if $asm_zone[asm_id] == nil
      $log.write("asm_id=%s not exist in table." % [asm_id]) if $verbose
      next
    end
    if $indexdata[asm_id] == nil || $indexdata[asm_id].size < 1
      $log.write("asm_id=%s not exist in indexdata." % [asm_id])
      next
    end
    msm_fts = $indexdata[asm_id].keys.sort
    $asm_zone[asm_id].each{|zone_id|
      fcst_count = refr["point_data"][i]["FCST_count"]
      for j in 0...fcst_count
        ft = refr["point_data"][i]["FCST"][j]["FCSTD"].get_value_time
        if msm_fts.first > ft
          next
        end
        index = nil
        if msm_fts.last < ft
          if $ecmwf_indexdata == nil || $ecmwf_indexdata[asm_id] == nil || $ecmwf_indexdata[asm_id].size < 1
            $log.write("asm_id=%s not exist in ecmwf indexdata." % [asm_id])
            next
          end
          if $ecmwf_indexdata[asm_id][ft] == nil
            $log.write("asm_id=%s ft=%s not exist in ecmwf indexdata." % [asm_id,ft.to_s])
            next
          end
          index = $ecmwf_indexdata[asm_id][ft]["INDEX"]
          if index == nil
            $log.write("asm_id=%s ft=%s INDEX not exist in ecmwf indexdata." % [asm_id,ft.to_s])
            next
          end
        else
          if $indexdata[asm_id][ft] == nil
            $log.write("asm_id=%s ft=%s not exist in indexdata." % [asm_id,ft.to_s])
            next
          end
          index = $indexdata[asm_id][ft]["INDEX"]
          if index == nil
            $log.write("asm_id=%s ft=%s INDEX not exist." % [asm_id,ft.to_s])
            next
          end
        end
        if index < 0
          $log.write("asm_id=%s ft=%s index is invalid." % [asm_id,ft.to_s])
          next
        end
        prcrin_1hour_total = refr["point_data"][i]["FCST"][j]["PRCRIN_1HOUR_TOTAL"]
        snwfll_1hour_total = refr["point_data"][i]["FCST"][j]["SNWFLL_1HOUR_TOTAL"]
        wx = refr["point_data"][i]["FCST"][j]["WX"]
        # 300 雨
        # 400 雪
        # 430 みぞれ
        if wx != 300 && wx != 400 && wx != 430
          # 降水がない場合→現行と変化なし
          next
        end
        # 降水がある場合→雪水比に従う
        srr = nil # 雪水比（cm/mm）
        pthd = nil
        prec_thds.each_index{|i|
          pthd = prec_thds[i]
          if pthd > prcrin_1hour_total
            srr = $config["prec_snow_ratio"][pthd][index]
            break
          end
        }
        if srr == nil
          pthd = 4
          srr = $config["prec_snow_ratio_last"][index]
        end
        if srr == 0 && wx == 300
          # 変更なし
          next
        end
        # 降雪量補正
        snow = srr * prcrin_1hour_total
        $log.write("zone_id=%s asm_id=%s ft=%s index=%s" % [zone_id,asm_id,ft.to_s,index]) if $debug
        $log.write("pthd=%s srr=%s org prec=%s snow=%s wx=%s" % [pthd,srr,prcrin_1hour_total,snwfll_1hour_total,wx]) if $debug
        # スプールデータ
        if $adjust_data[zone_id] == nil
          $adjust_data[zone_id] = {}
        end
        if $adjust_data[zone_id][ft] == nil
          $adjust_data[zone_id][ft] = {}
        end
        $adjust_data[zone_id][ft]["SNWFLL_1HOUR_TOTAL"] = snow
        # 天気補正
        # 300 雨
        # 400 雪
        # 430 みぞれ
        if srr == 0
          # 雪水比=0：雨
          $adjust_data[zone_id][ft]["WX"] = 300
          # 天気テロップが雨の場合降雪量は「-」にする
          $adjust_data[zone_id][ft]["SNWFLL_1HOUR_TOTAL"] = LACK_VALUE_16
        elsif srr > 0 && srr < 0.3
          # 雪水比 ＞0,＜0.3：みぞれ
          $adjust_data[zone_id][ft]["WX"] = 430
          # 天気テロップがみぞれのとき降雪量は「0㎝」にする
          $adjust_data[zone_id][ft]["SNWFLL_1HOUR_TOTAL"] = 0
        else
          # 雪水比 0.3以上：雪
          $adjust_data[zone_id][ft]["WX"] = 400
        end
        # 「ロジック適用前の生値のテロップが雪、かつ、降水相フィルター適用後のテロップも雪」
        #  である場合、降雪量を変更しない（生値のままの降雪量とする）
        if wx == 400 && $adjust_data[zone_id][ft]["WX"] == 400
          $adjust_data[zone_id][ft]["SNWFLL_1HOUR_TOTAL"] = snwfll_1hour_total
        end
        $log.write("chg snow=%s wx=%s" % [$adjust_data[zone_id][ft]["SNWFLL_1HOUR_TOTAL"],$adjust_data[zone_id][ft]["WX"]]) if $debug
      end
    }
  end
end

def main()
  opt = OptionParser.new
  logfile = nil
  input_tagid = ""
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
    opt.on('-s', '--spool', TrueClass){|v| $spool = v}
    opt.on('-t TAGID', '--tagid TAGID'){|v| input_tagid = v}
    opt.on('-l LOG', '--log LOG'){|v| logfile = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 2)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
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
  $asm_zone = rd_table_winter["asm_zone"]
  # indexデータのスプールを読む
  #
  # indexdata[asmid][ft][elm]
  #
  dbdata = PStore.new($config["spool_dir"] + $config["msm_adjust_temp_index"])
  dbdata.transaction() do
    $indexdata = dbdata['root']
  end
  if $indexdata == nil || $indexdata.size < 1
    $log.write("msm indexdata data not spooled.")
    exit
  end
  dbdata = PStore.new($config["spool_dir"] + $config["ecwmf_adjust_temp_index"])
  dbdata.transaction() do
    $ecmwf_indexdata = dbdata['root']
  end
  if $ecmwf_indexdata == nil || $ecmwf_indexdata.size < 1
    $log.write("ecmwf indexdata data not spooled.")
  end
  # 補正元データの生成
  make_adjust_data(ARGV[1])
  $log.write("change zone count=%s" % [$adjust_data.size])
  # 保存
  spool_fname = $config["spool_dir"] + input_tagid + "_" + $config["msm_change_spool"]
  dbdata = PStore.new(spool_fname)
  dbdata.transaction() do
    dbdata['root'] = $adjust_data
  end
  # 過去データ保存
  if $spool
    $log.write("spool changedata.")
    savedir = $config["spool_dir"] + $config["change_data_spool"] + "/" + input_tagid
    if !File.exist?(savedir)
      FileUtils.mkdir(savedir)
    end
    savefile = "%s/%s.pst" % [savedir,Time.now.strftime("%Y%m%d%H%M%S")]
    dbdata = PStore.new(savefile)
    dbdata.transaction() do
      dbdata['root'] = $adjust_data
    end
    spath = savedir + "/*.pst"
    day = Time.now
    day = day - $config["rawdata_expire_ecmwf"] * 3600 * 24
    Dir.glob(spath){|fnam|
      if (day <=> File.mtime(fnam)) == 1
        FileUtils.remove(fnam)
      end
    }
  end
end

begin
  main()
  $log.write("***** proc end normally *****")
rescue => e
  if $log != nil
    $log.write("#{e.backtrace[0]}: #{e.message} (#{e.class})")
    e.backtrace.each_index{|i|
      $log.write("\tfrom #{e.backtrace[i]}") if i != 0
    }
  else
    print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
    e.backtrace.each_index{|i|
      print "\tfrom #{e.backtrace[i]}\n" if i != 0
    }
  end
  $log.write("***** proc end error *****")
end
