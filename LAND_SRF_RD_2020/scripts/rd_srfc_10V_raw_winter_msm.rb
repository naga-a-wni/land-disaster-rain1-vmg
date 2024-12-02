#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require 'optparse'
require 'wlib'
require 'meshkernel'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite.rb'
require 'create_ruheader_winter.rb'
require 'get_sstm.rb'
require 'get_rdcnd.rb'
require 'get_scale_winter.rb'
require 'adjust_elements.rb'
require 'smoothing_elements.rb'
require 'lock_and_wait.rb'

$config = nil
$log = nil
$verbose = false
$debug = false
$savefilename = nil
$c3op = false
$output_ids = nil
$rd_table_winter = nil
$zone_data = nil
$dewtmp_avg = nil
$change_data = nil

# 入力データの欠測値はすべて-9999
LACK_VALUE_16 = -9999
LACK_VALUE_8 = -99

$host = "localhost"
$port = 11112

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config> <input>
  Available options:
    -v --verbose                : verbose mode.
    -d --debug                  : debug
    -c --c3op                   : c3op
    -t TAGID --tagid TAGID      : input tagid
    -o OUTPUT --output OUTPUT   : output ru
    -l LOG --log LOG            : logfile
    -h HOST --host HOST         : mk2 host
    -p PORT --port PORT         : mk2 port
EOF
  exit
end

#
# 生データから日中夜間１次データ作成
#
# daynight["begin"]
#         ["end"]
#         ["term"]
#         ["AIRTMP_MIN"]
#         ["SNWFLL_TOTAL"]["raw"]
#         ["SNWFLL_TOTAL"]["round"]
#         ["RDTMP_MIN"]
#         ["PRCRIN_TOTAL"]
#         ["RDFEEZE_MAX"]
#         ["RDFEEZE_RENZOKU_SCALE"]
#         ["RDFEEZE_RENZOKU"] = []
#         ["RAIN_TELOP"]
#         ["RAIN_HOURS"]
#         ["SNOW_HOURS"]
#         ["hour_data"][ft]["snow"]["raw"]
#         ["hour_data"][ft]["snow"]["round"]
#         ["hour_data"][ft]["snow"]["diff"]
#         ["hour_data"][ft]["RDFEEZE"]
#
def set_daynight_data(zone_id, ft, daynight, refr_fcst, dewtmp, wx, mintmp_fts)
  # 10Vスケール判定に必要な 時間帯毎の「最低気温」「最低路温」「総雨量」「総降雪量」「雨天時間」「降雪時間」「降雨時間」を求めておく。
  daynight["end"] = ft
  daynight["hour_data"][ft] = {}
  daynight["hour_data"][ft]["snow"] = {}
  daynight["hour_data"][ft]["rain"] = {}
  # 雨天時間
  if wx == 300
    daynight["RAIN_TELOP"] += 1
  end
  # 降雪時間
  if refr_fcst["SNWFLL_1HOUR_TOTAL"] >= 0
    daynight["SNOW_HOURS"] += 1
  end
  # 降雨時間
  if refr_fcst["PRCRIN_1HOUR_TOTAL"] >= 0
    daynight["RAIN_HOURS"] += 1
  end
  # 気温
  if refr_fcst["AIRTMP"] != LACK_VALUE_16
    daynight["hour_data"][ft]["AIRTMP"] = refr_fcst["AIRTMP"]
  end
  # 最低気温
  if daynight["AIRTMP_MIN"] == nil || (refr_fcst["AIRTMP"] != LACK_VALUE_16 && refr_fcst["AIRTMP"] < daynight["AIRTMP_MIN"])
    daynight["AIRTMP_MIN"] = refr_fcst["AIRTMP"]
    mintmp_fts["min_airtmp_ft"] = ft
  end
  # 総降雪量
  daynight["hour_data"][ft]["snow"]["raw"] = refr_fcst["SNWFLL_1HOUR_TOTAL"]
  if refr_fcst["SNWFLL_1HOUR_TOTAL"] > 0
    daynight["SNWFLL_TOTAL"]["raw"] += refr_fcst["SNWFLL_1HOUR_TOTAL"]
    daynight["hour_data"][ft]["snow"]["round"] = refr_fcst["SNWFLL_1HOUR_TOTAL"].round
    daynight["SNWFLL_TOTAL"]["round"] += daynight["hour_data"][ft]["snow"]["round"]
    daynight["hour_data"][ft]["snow"]["diff"] = daynight["hour_data"][ft]["snow"]["raw"] - daynight["hour_data"][ft]["snow"]["round"]
  end
  # 路温
  if refr_fcst["RDTMP"] != LACK_VALUE_16
    daynight["hour_data"][ft]["RDTMP"] = refr_fcst["RDTMP"]
  end
  # 最低路温
  if daynight["RDTMP_MIN"] == nil || (refr_fcst["RDTMP"] != LACK_VALUE_16 && refr_fcst["RDTMP"] < daynight["RDTMP_MIN"])
    daynight["RDTMP_MIN"] = refr_fcst["RDTMP"]
    mintmp_fts["min_rdtmp_ft"] = ft
  end
  # 総雨量
  if refr_fcst["PRCRIN_1HOUR_TOTAL"] > 0 && refr_fcst["SNWFLL_1HOUR_TOTAL"] <= 0
    daynight["PRCRIN_TOTAL"] += refr_fcst["PRCRIN_1HOUR_TOTAL"]
  end
  # 無降水凍結スケール
  if refr_fcst["RDTMP"] != LACK_VALUE_16
    daynight["hour_data"][ft]["RDFEEZE"] = calc_rd_freeze(zone_id,ft,refr_fcst["RDTMP"],dewtmp)
    # 無降水スケール連続スケール
    tempscale = get_rd_freeze_renzoku_scale(zone_id,daynight["hour_data"][ft]["RDFEEZE"],daynight["RDFEEZE_RENZOKU"])
    if daynight["RDFEEZE_RENZOKU_SCALE"] < tempscale
      daynight["RDFEEZE_RENZOKU_SCALE"] = tempscale
    end
    if daynight["RDFEEZE_MAX"] < daynight["hour_data"][ft]["RDFEEZE"]
      daynight["RDFEEZE_MAX"] = daynight["hour_data"][ft]["RDFEEZE"]
    end
  end
end

# 昼夜１区間内の最低気温路温と四捨五入した整数が同じになるftをチェックする。
def check_daynight_mintemp(daynight, mintemp_fts)
  same_mintemp_fts = { "min_airtmp_ft" => [],  "min_rdtmp_ft" => [] }
  min_airtmp_value = LACK_VALUE_16
  min_rdtmp_value = LACK_VALUE_16

  min_airtmp_value = daynight["AIRTMP_MIN"].round if ! daynight["AIRTMP_MIN"].nil?
  min_rdtmp_value = daynight["RDTMP_MIN"].round if ! daynight["RDTMP_MIN"].nil?
  daynight["hour_data"].each{|ft, val|
    if min_airtmp_value != LACK_VALUE_16 && !val["AIRTMP"].nil? && val["AIRTMP"].round == min_airtmp_value
      same_mintemp_fts["min_airtmp_ft"].push(ft) if mintemp_fts["min_airtmp_ft"] != ft
    end
    if min_rdtmp_value != LACK_VALUE_16 && !val["RDTMP"].nil? && val["RDTMP"].round == min_rdtmp_value
      same_mintemp_fts["min_rdtmp_ft"].push(ft) if mintemp_fts["min_rdtmp_ft"] != ft
    end
  }
  return same_mintemp_fts
end


#
# 日中夜間１次データから降雪量データ作成
#
# 整数問題処理
# 1.差分をもとめる(差分=生値総降雪量(昼)-四捨五入総降雪量(昼))
#   生値の総降雪量(16cm)から四捨五入した総降雪量(11cm)を引く→差分5cm
# 2.生値(cm/h)から四捨五入値(cm/h)を引き、差分量が大きいコマ(0.4cm)をFTが小さい方を優先し、
#   差分量のコマ数だけ(5コマ)、１(cm/h)に切り上げ処理するし、四捨五入値に足す
#
def make_snwfll_data(daynight_zone,zone_id)
  daynight_zone.each{|daynight|
    #
    # 雪
    # daynight["SNWFLL_TOTAL"]["raw"]            生値総降雪量
    #         ["SNWFLL_TOTAL"]["round"]          四捨五入総降雪量
    #         ["hour_data"][ft]["snow"]["raw"]   生値時間降雪量
    #         ["hour_data"][ft]["snow"]["round"] 四捨五入時間降雪量
    #         ["hour_data"][ft]["snow"]["diff"]  生値(cm/h)から四捨五入値(cm/h)を引いた値
    #         ["hour_data"][ft]["snow"]["out"]   出力時間降雪量
    #
    if daynight["SNWFLL_TOTAL"] != nil && daynight["SNWFLL_TOTAL"]["raw"] > 0
      daynight["SNWFLL_TOTAL"]["raw"] = daynight["SNWFLL_TOTAL"]["raw"].round  # 四捨五入
#      if zone_id == "220400000202"
#        $log.write("%s %s" % [zone_id,daynight["term"]])
#        $log.write("%s,%s" % [daynight["SNWFLL_TOTAL"]["raw"],daynight["SNWFLL_TOTAL"]["round"]])
#        fts = daynight["hour_data"].keys.sort
#        fts.each{|ft|
#          hdata = daynight["hour_data"][ft]
#          $log.write("%s,%s,%s,%s,%s" % [ft.to_s,daynight["hour_data"][ft]["snow"]["raw"],daynight["hour_data"][ft]["snow"]["round"],daynight["hour_data"][ft]["snow"]["diff"],daynight["hour_data"][ft]["snow"]["out"]])
#        }
#      end
      if daynight["SNWFLL_TOTAL"]["raw"] <= daynight["SNWFLL_TOTAL"]["round"]
        next
      end
      ttldiff = (daynight["SNWFLL_TOTAL"]["raw"] - daynight["SNWFLL_TOTAL"]["round"])
      if ttldiff > 1
        $log.write("%s %s SNWFLL_TOTAL diff=%s" % [zone_id,daynight["term"],ttldiff]) if $verbose
      end
      # keyが差分。大きいほど生値のほうが大きい
      diff_ft = {}
      # FTの小さい方を優先して処理する。
      fts = daynight["hour_data"].keys.sort
      fts.each{|ft|
        hdata = daynight["hour_data"][ft]
        if hdata["snow"]["diff"] != nil
          if diff_ft[hdata["snow"]["diff"]] == nil
            diff_ft[hdata["snow"]["diff"]] = []
          end
          diff_ft[hdata["snow"]["diff"]].push(ft)
        end
      }
      counter = 0
      inc = 1
      diffs = diff_ft.keys.sort
      # 差分の大きい方から
      diffs.reverse_each{|dif|
        diff_ft[dif].each{|ft|
          daynight["hour_data"][ft]["snow"]["out"] = daynight["hour_data"][ft]["snow"]["round"] + inc
          counter += 1
          if counter >= ttldiff
            break
          end
        }
        if counter >= ttldiff
          break
        end
      }
#      if zone_id == "260400000202" && ttldiff == 2
#        $log.write("%s %s SNWFLL_TOTAL diff=%s" % [zone_id,daynight["term"],ttldiff])
#        $log.write("%s,%s" % [daynight["SNWFLL_TOTAL"]["raw"],daynight["SNWFLL_TOTAL"]["round"]])
#        fts = daynight["hour_data"].keys.sort
#        fts.each{|ft|
#          hdata = daynight["hour_data"][ft]
#          $log.write("%s,%s,%s,%s,%s" % [ft.to_s,daynight["hour_data"][ft]["snow"]["raw"],daynight["hour_data"][ft]["snow"]["round"],daynight["hour_data"][ft]["snow"]["diff"],daynight["hour_data"][ft]["snow"]["out"]])
#        }
#      end
    end
  }
end

#
# 411024527,411024528,411024529 RD短期COMPASS
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
#
def make_winter_ru(input_data)
  # 入力ファイル読み込み
  gr = GenRw.open(input_data)
  refr = gr.get_value_ref
  announced_date = refr["announced_date"].get_value_time
  $log.write("announced_date %s" % [announced_date.to_s])
  obs_prec_integ = {}
  # ファイル書き込み
  gw = GenRw.new()
  if $c3op
    gw.create(create_ruheader_winter(announced_date,$output_ids["c3op_dataid16"],$output_ids["c3op_data_name"]))
  else
    gw.create(create_ruheader_winter(announced_date,$output_ids["winter_dataid16"],$output_ids["winter_data_name"]))
  end
  refw = gw.get_value_ref
  refw["announced_date"].set_value_time(announced_date)
  refw["source"] = 0  # 生
  refw["created_date"].set_value_time(Time.now)
  refw["send_date"].set_value_time(Time.now)
  refw["created_by"] = ""
  asm_area_count = refr["point_count"]
  zone_area_count = 0
  for i in 0...asm_area_count
    asm_id = refr["point_data"][i]["ASM_ID"]
    asm_zones = $rd_table_winter["asm_zone"][asm_id]
    if asm_zones == nil
      $log.write("asm_id=%s not exist in winter_table." % [asm_id]) if $verbose
      next
    end
    asm_zones.each{|zone_id|
      refw["ZONE_data"].array_resize(zone_area_count+1)
      refw["ZONE_data"][zone_area_count]["ZONE"] = zone_id  # RD中区間番号
      refw["ZONE_data"][zone_area_count]["MAX_10V_DEF"] = $zone_data[zone_id]["MAX_10V_DEF"]  # 10V定義の最大値
      refw["ZONE_data"][zone_area_count]["ASM_ID"] = asm_id # 紐付けASM
      refw["ZONE_data"][zone_area_count]["BRG_SIL_flg"] = refr["point_data"][i]["SOIL_or_BRG"]  # 橋が１、土が２、推定値(路観なし)は３
      # 降水量、降雪量以外は1時間データをそのままコピー
      fcst_count = refr["point_data"][i]["FCST_count"]
      refw["ZONE_data"][zone_area_count]["FT"] = fcst_count
      refw["ZONE_data"][zone_area_count]["FCAS"].array_resize(fcst_count)
      daynight_zone = []       # １区間の全日中夜間データ
      daynight = nil           # 日中夜間データ
      # 1時間データ生成
      # スムージングで値を変更してはいけないコマを記録 2023/10
      night_mintmp_fts = {}
      fix_airtmp_fts = []
      fix_rdtmp_fts = []
      for j in 0...fcst_count
        ft = refr["point_data"][i]["FCST"][j]["FCSTD"].get_value_time
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["FCASD"].set_value_time(ft)
        wx = wx_conv(refr["point_data"][i]["FCST"][j]["WX"])
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["WX"] = wx                        # 天気
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["AIRTMP"] = refr["point_data"][i]["FCST"][j]["AIRTMP"]                         # 気温
        wndspd = refr["point_data"][i]["FCST"][j]["WNDSPD"]
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["WNDSPD"] = wndspd                # 風速
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["WNDDIR"] = refr["point_data"][i]["FCST"][j]["WNDDIR"]                         # 風向
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["RDTMP"] = refr["point_data"][i]["FCST"][j]["RDTMP"]                           # 路温
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["GUSTS"] = refr["point_data"][i]["FCST"][j]["GUSTS"]                           # 瞬間風速
        #
        # 時間降水量
        #
        prcrin_1hour_total = refr["point_data"][i]["FCST"][j]["PRCRIN_1HOUR_TOTAL"].round
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["PRCRIN_1HOUR_TOTAL"] = prcrin_1hour_total
        # MSM
        # [zone_id][ft]["SNWFLL_1HOUR_TOTAL"]
        #              ["WX"]
        #              ["AIRTMP"]
        #              ["RDTMP"]
        if $change_data != nil && $change_data[zone_id] != nil && $change_data[zone_id][ft] != nil
          $change_data[zone_id][ft].each_pair{|key,value|
            if key == "SNWFLL_1HOUR_TOTAL"
              refr["point_data"][i]["FCST"][j][key] = value
              $log.write("msm change_data %s %s %s=%s" % [zone_id,ft.to_s,key,value]) if $verbose
            else
              refw["ZONE_data"][zone_area_count]["FCAS"][j][key] = value
              $log.write("msm change_data %s %s %s=%s" % [zone_id,ft.to_s,key,value]) if $verbose
            end
          }
        end
        # 露点温度
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["DEWTMP"] = LACK_VALUE_16
        if $dewtmp_avg != nil
          if $dewtmp_avg[zone_id] == nil || $dewtmp_avg[zone_id][ft] == nil
            $log.write("zone_id=%s FCAS_time=%s dewtmp is not exist." % [ zone_id, ft.to_s ]) if $verbose
          else
            refw["ZONE_data"][zone_area_count]["FCAS"][j]["DEWTMP"] = $dewtmp_avg[zone_id][ft]
          end
        end
        #
        # 風10Vスケール判定
        #
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["WIND_VSCAL"] = get_scale_wind($zone_data[zone_id]["threshold_wind"],wndspd)
        # 日中夜間
        term = isdaynight(zone_id,ft)
        if daynight == nil || daynight["term"] != term
          
	  if daynight != nil                    # 最低気温/路温が確定した 
            fix_airtmp_fts.push(night_mintmp_fts["min_airtmp_ft"]) if night_mintmp_fts["min_airtmp_ft"] != nil 
            fix_rdtmp_fts.push(night_mintmp_fts["min_rdtmp_ft"]) if night_mintmp_fts["min_rdtmp_ft"] != nil  
            same_mintemp_fts  =check_daynight_mintemp(daynight, night_mintmp_fts)
            fix_airtmp_fts.concat(same_mintemp_fts["min_airtmp_ft"])
            fix_rdtmp_fts.concat(same_mintemp_fts["min_rdtmp_ft"])
          end
          # 夜間最低気温/路温の時刻
          night_mintmp_fts["min_airtmp_ft"] = nil
          night_mintmp_fts["min_rdtmp_ft"] = nil
          # 日中夜間変更
          daynight = {}
          daynight["hour_data"] = {}
          daynight["RDFEEZE_RENZOKU"] = []
          daynight["term"] = term
          daynight["begin"] = ft
          daynight["RAIN_TELOP"] = 0
          daynight["RAIN_HOURS"] = 0
          daynight["SNOW_HOURS"] = 0
          daynight["PRCRIN_TOTAL"] = 0
          daynight["RDFEEZE_MAX"] = LACK_VALUE_8
          daynight["RDFEEZE_RENZOKU_SCALE"] = LACK_VALUE_8
          daynight["SNWFLL_TOTAL"] = {}
          daynight["SNWFLL_TOTAL"]["raw"] = 0
          daynight["SNWFLL_TOTAL"]["round"] = 0
          daynight_zone.push(daynight)
#          $log.write( "zone_id=%s daynight start %s %s" % [zone_id,term,ft.to_s] )
        end
        # 日中夜間一次データ作成
        set_daynight_data(zone_id, ft, daynight, refr["point_data"][i]["FCST"][j], refw["ZONE_data"][zone_area_count]["FCAS"][j]["DEWTMP"], wx, night_mintmp_fts)
      end
      # 最後のdaynight_dataが夜間の場合、最低気温のftを保存しておく
      if daynight != nil                    # 最低気温/路温が確定した
        fix_airtmp_fts.push(night_mintmp_fts["min_airtmp_ft"]) if night_mintmp_fts["min_airtmp_ft"] != nil
        fix_rdtmp_fts.push(night_mintmp_fts["min_rdtmp_ft"]) if night_mintmp_fts["min_rdtmp_ft"] != nil
        same_mintemp_fts  =check_daynight_mintemp(daynight, night_mintmp_fts)
        fix_airtmp_fts.concat(same_mintemp_fts["min_airtmp_ft"])
        fix_rdtmp_fts.concat(same_mintemp_fts["min_rdtmp_ft"])
      end
      # 時間降雪量データ作成
      make_snwfll_data(daynight_zone,zone_id)
      for j in 0...fcst_count
        ft = refr["point_data"][i]["FCST"][j]["FCSTD"].get_value_time
        daynight_zone.each{|daynight|
          if  daynight["hour_data"][ft] == nil
            next
          end
          if daynight["hour_data"][ft]["snow"]["raw"] == nil || daynight["hour_data"][ft]["snow"]["raw"] < 0
            # 生値時間降雪量欠測
            refw["ZONE_data"][zone_area_count]["FCAS"][j]["SNWFLL_1HOUR_TOTAL"] = LACK_VALUE_16
          else
            if daynight["hour_data"][ft]["snow"]["out"] != nil
              # 出力時間降雪量
              refw["ZONE_data"][zone_area_count]["FCAS"][j]["SNWFLL_1HOUR_TOTAL"] = daynight["hour_data"][ft]["snow"]["out"]
            else
              # 四捨五入時間降雪量
              refw["ZONE_data"][zone_area_count]["FCAS"][j]["SNWFLL_1HOUR_TOTAL"] = daynight["hour_data"][ft]["snow"]["round"]
            end
          end
        }
      end
      #
      # 再計算
      #
      smoothing_count = 0 
      adjust_count = 0 
      while(adjust_count < 5)               # とりあえず5回要素間整合したら終了 
        adjust_data_flg = 0
        # 要素間整合
        for j in 0...fcst_count
          chg_airtmp_flg, chg_rdtmp_flg = adjust_elements_and_check_tmp(j, refr["point_data"][i]["FCST"][j]["SNWFLL_1HOUR_TOTAL"], refw["ZONE_data"][zone_area_count]["FCAS"])
          # 前後で変化があったら固定ftリストに入れる
          if chg_airtmp_flg
            fix_airtmp_fts.push(refw["ZONE_data"][zone_area_count]["FCAS"][j]["FCASD"].get_value_time)
            adjust_data_flg = 1
          end
          if chg_rdtmp_flg 
            fix_rdtmp_fts.push(refw["ZONE_data"][zone_area_count]["FCAS"][j]["FCASD"].get_value_time)
            adjust_data_flg = 1
          end
        end
        adjust_count += 1
        # p "#{zone_id}, #{adjust_data_flg}"
        # p fix_airtmp_fts
        # p fix_rdtmp_fts
        if adjust_count >= 5 
          break
        end
        if smoothing_count == 0 || adjust_data_flg == 1    # まだスムージングしてない または要素間整合で変化があったら
          smoothing_tmp(refw["ZONE_data"][zone_area_count]["FCAS"], fcst_count, fix_airtmp_fts, fix_rdtmp_fts)      
          smoothing_count += 1
        else
          # すでに１回以上スムージングしている かつ 要素間整合で変化がなかったら
          # $log.write("adjust finish")
          break
        end
      end
      # $log.write("#{zone_id}  adjust_count : #{adjust_count}  smoothing_count : #{smoothing_count}")

      #end
      for j in 0...fcst_count
        # 路面状態
        get_rdcnd(j, refw["ZONE_data"][zone_area_count]["FCAS"])
        # 吹雪指数
        wndspd = refw["ZONE_data"][zone_area_count]["FCAS"][j]["WNDSPD"]
        snwfll = refw["ZONE_data"][zone_area_count]["FCAS"][j]["SNWFLL_1HOUR_TOTAL"]
        airtmp = refw["ZONE_data"][zone_area_count]["FCAS"][j]["AIRTMP"]
        wx = refw["ZONE_data"][zone_area_count]["FCAS"][j]["WX"]
        refw["ZONE_data"][zone_area_count]["FCAS"][j]["SSTMI"] = get_sstm(wndspd,snwfll,airtmp,wx)
      end
      # 日中夜間データ生成
      # daynight["begin"]
      #         ["end"]
      #         ["term"]
      #         ["AIRTMP_MIN"]
      #         ["SNWFLL_TOTAL"]["raw"]
      #         ["RDTMP_MIN"]
      #         ["PRCRIN_TOTAL"]
      #         ["RDFEEZE_MAX"]
      #         ["RDFEEZE_RENZOKU_SCALE"]
      #         ["RAIN_TELOP"]
      #         ["RAIN_HOURS"]
      #         ["SNOW_HOURS"]
      day_night_count = 0
      daynight_zone.each{|daynight|
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"].array_resize(day_night_count+1)
        # 昼夜定義の開始日
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"][day_night_count]["DAYTM_NIGHT_BEGIND"].set_value_time(daynight["begin"])
        # 昼夜定義の終了日
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"][day_night_count]["DAYTM_NIGHT_ENDD"].set_value_time(daynight["end"])
        # 10V(無降水) 整数値
        rd_freeze_scale = daynight["RDFEEZE_MAX"]
        rd_freeze_renzoku_scale = daynight["RDFEEZE_RENZOKU_SCALE"]
        if $zone_data[zone_id]["RDICING_DURATION_HOUR"] > 1
          if rd_freeze_renzoku_scale < $zone_data[zone_id]["RDICING_DURATION_SCALE"]
            if rd_freeze_scale > 1
              rd_freeze_scale -= 1
            end
          else
            rd_freeze_scale = rd_freeze_renzoku_scale
          end
        end
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"][day_night_count]["NOPRFZ_VSCAL"] = rd_freeze_scale
        # 10V(寒候期) 整数値
        rank = get_7v_scale(daynight,zone_id)
        # 7vスケールから10vスケールへの変換
        scale_10v = sevenv2tenv(rank, zone_id, rd_freeze_scale, daynight["term"], daynight["RAIN_HOURS"])
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"][day_night_count]["VSCAL"] = scale_10v
        # 0:日中,1:夜間 整数値
        refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT"][day_night_count]["DAYTM_NIGHT_flg"] = daynight["term"] == "day" ? 0 : 1
        day_night_count +=1
      }
      refw["ZONE_data"][zone_area_count]["DAYTM_NIGHT_count"] = day_night_count
      zone_area_count += 1
    }
  end
  refw["ZONE_count"] = zone_area_count
  if zone_area_count < 1
    $log.write("available data not exist in input data.")
    exit
  end
  # ファイル出力
  if $savefilename != nil
    gw.save($savefilename)
  end
end

def main()
  opt = OptionParser.new
  logfile = nil
  input_tagid = ""
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
    opt.on('-c', '--c3op', TrueClass){|v| $c3op = v}
    opt.on('-t TAGID', '--tagid TAGID'){|v| input_tagid = v}
    opt.on('-o OUTPUT', '--output OUTPUT'){|v| $savefilename = v}
    opt.on('-l LOG', '--log LOG'){|v| logfile = v}
    opt.on('-h HOST', '--host HOST'){|v| $host = v}
    opt.on('-p PORT', '--port PORT'){|v| $port = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 2)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
  if input_tagid == "" || $config[input_tagid] == nil
    $log.write("input_tagid=%s not supported." % [input_tagid])
    return
  else
    $output_ids = $config[input_tagid]
  end
  lock_f = lock_and_wait($config["spool_dir"] + $config["lock_file_raw_winter"][input_tagid])
#  if $c3op
#    if input_tagid != "411024529"
#      $log.write("msm input_tagid=%s not supported." % [input_tagid])
#      return
#    end
#  end
  $log.write("spool data read start.")
  # 寒候期テーブルのスプールを読む
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_winter_spool"])
  dbdata.transaction() do
    $rd_table_winter = dbdata['root']
  end
  if $rd_table_winter == nil || $rd_table_winter.size < 1
    $log.write("%s data not spooled." % [$config["rd_table_winter_spool"]])
    return
  end
  $zone_data = $rd_table_winter["zone_elements"]
  # 露点温度スプールデータ読み出し
  spool_fname = $config["dewtmp_spool_avg"]
  if dew_file_available(spool_fname)
    File.open(spool_fname, "r+"){|f|
      f.flock(File::LOCK_EX)  # ロックする（すでにロックされていたら待つ）
      begin
        $dewtmp_avg = Marshal.restore(f)
      rescue
        $log.write("spool file : %s is not exist\n" % [ spool_fname ])
      end
      f.flock(File::LOCK_UN)  # アンロックし、他のプログラムが読み出せるようにする
    }
    if $dewtmp_avg == nil || $dewtmp_avg.size < 1
      $log.write("%s data not spooled." % [$config["dewtmp_spool_avg"]])
    end
  else
    $log.write("%s data not spooled." % [$config["dewtmp_spool_avg"]])
  end
  # c3opスプールデータ読み出し
  if $c3op
    $log.write("msm version.")
    spool_fname = $config["msm_spool_dir"] + input_tagid + "_" + $config["msm_change_spool"]
    $log.write(spool_fname)
    dbdata = PStore.new(spool_fname)
    dbdata.transaction() do
      if(dbdata['root'] != nil)
        $change_data = dbdata['root']
      end
    end
    if $change_data == nil || $change_data.size < 1
      $log.write("%s data not spooled." % [spool_fname])
    else
      $log.write("change zone count=%s" % [$change_data.size])
    end
  end
  $log.write("spool data read end.")
  # 寒候期出力RUの生成
  make_winter_ru(ARGV[1])
  unlock_and_wait(lock_f)
  $log.write("***** proc end normally *****")
end
main()
