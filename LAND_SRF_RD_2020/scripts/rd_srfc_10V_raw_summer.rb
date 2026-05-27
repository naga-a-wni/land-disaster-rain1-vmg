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
require 'create_ruheader_summer.rb'
require 'get_sstm.rb'
require 'get_rdcnd.rb'
require 'get_obs_prec_integ.rb'
require 'adjust_elements.rb'
require 'get_scale_summer.rb'
require 'lock_and_wait.rb'
require 'get_fcst_soil_prec_index.rb'  # 土壌雨量指数
require 'get_soilprec_scale.rb'        # 土壌雨量指数

$config = nil
$log = nil
$verbose = false
$debug = false
$savefilename = nil
$output_ids = nil
$rd_table_summer = nil
$rd_obs_point_list = nil
$dewtmp_avg = nil
$rd_table_winter = nil
# 新第２通行止めスプール情報 202205
# [ZONE_ID][SMALL_ZONE_ID][RAIN_POINT_ID]["apply"] = time
# [ZONE_ID][SMALL_ZONE_ID][RAIN_POINT_ID]["latest"] = time
# [ZONE_ID][SMALL_ZONE_ID][RAIN_POINT_ID]["list"] = [time]
$level3_time_list = nil
# 連続雨量最終更新時刻
# latest_time_list[tagid] = btime
$latest_time_list = nil
# 雨量局とCL基準値の紐づけ情報
# $soilprec_threshold_info[小区間][雨量局][level][[x,y],[x,y],[x,y],...]
$soilprec_threshold_info = {}

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
    -t TAGID --tagid TAGID      : input tagid
    -o OUTPUT --output OUTPUT   : output ru
    -l LOG --log LOG            : logfile
    -h HOST --host HOST         : mk2 host
    -p PORT --port PORT         : mk2 port
EOF
  exit
end

def make_summer_ru(ru_data)
  announced_date = ru_data["announced_date"]
  # 連続雨量の過去値を読む
  obs_prec_integ = {}
  if $rd_obs_point_list != nil
    mk2_point_list = []
    $rd_obs_point_list.each_pair{|tagid,value|
      value.each_pair{|lclid,reset|
        pointid = "%s_%s_%s" % [tagid,lclid,reset.join("_")]
        mk2_point_list.push(MkPoint.new( pointid ))
      }
    }
    mk2_rid_list = []
    $rd_table_summer["zone_elements"].each_pair{|zone_id,zdata|
      zdata["SMALL_ZONE"].each_pair{|small_zone,szdata|
        szdata["RAIN_POINT"].each_pair{|rain_point,table_rain_point|
          mk2_rid_list.push(MkPoint.new( rain_point ))
        }
      }
    }
    # 生値の場合は現在時刻が配信時刻
    end_time = Time.now
    # 現在時刻の正時 = Ha 配信時刻のHH
    just_time = Time.at(((end_time.to_i) / 3600) * 3600)
    $log.write("just_time=%s" % [just_time.to_s])
    obs_prec_integ = get_obs_prec_integ(end_time,just_time,announced_date,mk2_point_list)
    obs_rain_scale = get_obs_scale_hour(just_time,announced_date,mk2_rid_list)
  end
  # ファイル書き込み
  gw = GenRw.new()
  gw.create(create_ruheader_summer(announced_date,$output_ids["summer_dataid16"],$output_ids["summer_data_name"]))
  refw = gw.get_value_ref
  refw["announced_date"].set_value_time(announced_date)
  refw["source"] = 0  # 生
  refw["created_date"].set_value_time(end_time)
  refw["send_date"].set_value_time(end_time)
  refw["created_by"] = ""
  all_zone_ids = $rd_table_summer["zone_elements"].keys.sort
  all_zone_count = all_zone_ids.size
  max_scale = {}
  notin_winter = []
  bcode_mismach = []
  zone_area_count = 0
  all_zone_ids.each_index{|i|
    zone_id = all_zone_ids[i]
    asm_id_daihyo = $rd_table_summer["zone_elements"][zone_id]["ASM_ID_daihyo"]
    if ru_data["point_data"][asm_id_daihyo] == nil
      $log.write("asm_id_daihyo=%s not exist in input data." % [asm_id_daihyo]) if $verbose
      next
    end
    refw["ZONE_data"].array_resize(zone_area_count+1)
    refw_zone = refw["ZONE_data"][zone_area_count]
    refw_zone["ZONE"] = zone_id  # 暖候期中区間番号（通行判断予測区間）
    refw_zone["ASM_ID_daihyo"] = asm_id_daihyo # 中区間の代表雨量局ASMID
    fcst_count = ru_data["point_data"][asm_id_daihyo]["FCST"].size
    refw_zone["FT"] = fcst_count
    refw_zone["FCAS"].array_resize(fcst_count)
    # 中区間1時間データ生成
    for j in 0...fcst_count
      ft = ru_data["point_data"][asm_id_daihyo]["FCST"][j]["FCSTD"]
      refw_zone["FCAS"][j]["FCASD"].set_value_time(ft)
      refw_zone["FCAS"][j]["RAIN_VSCAL"] = LACK_VALUE_16  # 10V_雨 整数値
      refw_zone["FCAS"][j]["WIND_VSCAL"] = LACK_VALUE_16  # 10V_風 整数値
      refw_zone["FCAS"][j]["SOILP_VSCAL"] = LACK_VALUE_16 # 10V_雨(土壌雨量指数) 整数値
    end
    small_zids = $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"].keys.sort
    small_zone_count = small_zids.size
    refw_zone["small_ZONE_count"] = small_zone_count
    refw_zone["small_ZONE_data"].array_resize(small_zone_count)
    small_zids.each_index{|j|  # 小区間ループ 202205
      small_zone = small_zids[j]
      refw_smallz = refw_zone["small_ZONE_data"][j]
      refw_smallz["small_ZONE"] = small_zone
      refw_smallz["FT"] = fcst_count
      refw_smallz["FCAS"].array_resize(fcst_count)
      # 小区間1時間データ生成
      for k in 0...fcst_count
        ft = ru_data["point_data"][asm_id_daihyo]["FCST"][k]["FCSTD"]
        refw_smallz["FCAS"][k]["FCASD"].set_value_time(ft)
        refw_smallz["FCAS"][k]["RAIN_VSCAL"] = LACK_VALUE_16  # 10V_雨 整数値
        refw_smallz["FCAS"][k]["WIND_VSCAL"] = LACK_VALUE_16  # 10V_風 整数値
        refw_smallz["FCAS"][k]["SOILP_VSCAL"] = LACK_VALUE_16 # 10V_雨(土壌雨量指数) 整数値
        refw_smallz["FCAS"][k]["second_flag"] = 0 # 第２通行止め基準対象期間【0,1】 202205
        refw_smallz["FCAS"][k]["use_second"] = 0  # 第２通行止め基準適用期間【0,1】 202205
      end
      small_zone_save = nil  # 202205
      rain_pids = $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"].keys.sort
      point_count = 0
      rain_pids.each{|rain_point|  # 雨量局ループ 202205
        table_rain_point = $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"][rain_point]
        asm_id_rp = table_rain_point["ASM_ID"]
#        if table_rain_point["sub_ASM_ID"] != nil
#          asm_id_rp = table_rain_point["sub_ASM_ID"]
#        end
        if ru_data["point_data"][asm_id_rp] == nil
          $log.write("asm_id_rp=%s not exist in input data." % [asm_id_rp]) if $verbose
          next
        end
        refw_smallz["point_data"].array_resize(point_count+1)
        refw_smallz["point_data"][point_count]["daihyo_flg"] = table_rain_point["daihyo_flg"]
        refw_smallz["point_data"][point_count]["ASM_ID"] = asm_id_rp
        refw_smallz["point_data"][point_count]["RAIN_POINT_ID"] = rain_point
        # 雨量局に紐づく暖候期テーブル情報の取得
        tid = table_rain_point["tagid"]
        lid = table_rain_point["LCLID"]
        # Ho 観測値最新入電時刻 生値は常にHa > Ho
        latest_obs = nil
        ho_just = nil  # Hoの正時
        if $latest_time_list[tid] != nil
          latest_obs = $latest_time_list[tid]
          ho_just = Time.at(((latest_obs.to_i) / 3600) * 3600)
#          $log.write("%s latest_obs %s." % [tid,latest_obs.to_s])
        else
          $log.write("%s latest_obs not exist." % [tid])
          ho_just = announced_date - 3600 * 24
        end
        prcrin_prst_nmm = table_rain_point["reset_prec"]
        prcrin_prst_nhour = table_rain_point["reset_hour"]
        mk2_pointid = "%s_%s_%s_%s" % [tid,lid,prcrin_prst_nmm,prcrin_prst_nhour]
        enable_sflag = table_rain_point["second_flag"]  # 第２通行止め
        judge_type = table_rain_point["judge_type"]    # フラグはテーブル参照
        if enable_sflag == 1  # 202205
          if small_zone_save == nil
            small_zone_save = {}
          end
          small_zone_save[rain_point] = {}
        end
        # 土壌雨量指数サポート
        soil_prec_lvldata = {}
        if $soilprec_threshold_info != nil && $soilprec_threshold_info[small_zone] != nil && $soilprec_threshold_info[small_zone][rain_point] != nil && $soilprec_threshold_info[small_zone][rain_point].size > 0
          $soilprec_threshold_info[small_zone][rain_point].each_pair{|lvl,prms|
            soil_prec_lvldata[lvl] = prms
          }
        end
        # 雨量局データ
        refw_smallz["point_data"][point_count]["BRG_SIL_flg"] = ru_data["point_data"][asm_id_rp]["SOIL_or_BRG"]  # 橋が１、土が２、推定値(路観なし)は３
        refw_smallz["point_data"][point_count]["judge_type"] = judge_type  # 判定種別【1,2,3】 1：雨2：風3：雨と風
        refw_smallz["point_data"][point_count]["FT"] = fcst_count
        refw_smallz["point_data"][point_count]["FCAS"].array_resize(fcst_count)
        # 露点温度
        zids_winter = nil
        if $rd_table_winter != nil && $rd_table_summer["zone_elements"][zone_id]["ASM_ID_child"] != nil
          asm_id_child = $rd_table_summer["zone_elements"][zone_id]["ASM_ID_child"]
          asm_id_child.each{|summer_aid|
            if $rd_table_winter["asm_zone"][summer_aid] != nil
              if zids_winter == nil
                zids_winter = $rd_table_winter["asm_zone"][summer_aid]
              else
                zids_winter = zids_winter | $rd_table_winter["asm_zone"][summer_aid]
              end
            end
          }
          if zids_winter == nil
            if $rd_table_summer["summer_only"].index(zone_id) == nil && notin_winter.index(zone_id) == nil
              $log.write("summer zone_id=%s not match in winter zone." % [zone_id])
              notin_winter.push(zone_id)
            end
          end
        end
        prcrin_prst = 0             # 連続雨量
        prcrin_prst_p = 0           # 前回連続雨量
        prcrin_prst_update_t = nil  # 連続雨量更新時刻
        prcrin_prst_reset_t = nil   # 連続雨量リセット時刻     第２通行止め
        prcrin_prst_start_t = nil   # 連続雨量開始時刻         第２通行止め
        prcrin_prst_rstart_t = nil  # 連続雨量リセット開始時刻 第２通行止め
        prcrin_prst_second_t = nil  # 最後に時雨量が第２通行止め運用閾値を超えた時刻  202205
        prcrin_prst_second_p = nil  # 上の前回値  202205
        prcrin_fccst = {}           # 連続雨量計算用予報雨量
        a_flag = false              # 第２通行止め
        obs_flag = true
        obs_flag = false if ho_just == nil
        obs_flag = false if obs_prec_integ.size < 1
        if ru_data["point_data"][asm_id_rp]["FCST"][fcst_count-1]["FCSTD"] < ho_just
          obs_flag = false
        end
        observation_time = nil
        reset_flag = false
        s_index = 0               # 土壌雨量指数
        ds = [0,0,0]              # 土壌雨量指数
        nf_flag = obs_flag        # 土壌雨量指数
        # 雨量局1時間データ生成
        for l in 0...fcst_count  # FTループ 202205
          ft = ru_data["point_data"][asm_id_rp]["FCST"][l]["FCSTD"]
          if enable_sflag == 1  # 202205
            small_zone_save[rain_point][ft] = {}
          end
          refw_smallz["point_data"][point_count]["FCAS"][l]["FCASD"].set_value_time(ft)
          wx = wx_conv(ru_data["point_data"][asm_id_rp]["FCST"][l]["WX"])
          refw_smallz["point_data"][point_count]["FCAS"][l]["WX"] = wx                        # 天気
          refw_smallz["point_data"][point_count]["FCAS"][l]["AIRTMP"] = ru_data["point_data"][asm_id_rp]["FCST"][l]["AIRTMP"]                         # 気温
          wndspd = ru_data["point_data"][asm_id_rp]["FCST"][l]["WNDSPD"]
          refw_smallz["point_data"][point_count]["FCAS"][l]["WNDSPD"] = wndspd                # 風速
          refw_smallz["point_data"][point_count]["FCAS"][l]["WNDDIR"] = ru_data["point_data"][asm_id_rp]["FCST"][l]["WNDDIR"]                         # 風向
          refw_smallz["point_data"][point_count]["FCAS"][l]["RDTMP"] = ru_data["point_data"][asm_id_rp]["FCST"][l]["RDTMP"]                           # 路温
          refw_smallz["point_data"][point_count]["FCAS"][l]["GUSTS"] = ru_data["point_data"][asm_id_rp]["FCST"][l]["GUSTS"]                           # 瞬間風速
          refw_smallz["point_data"][point_count]["FCAS"][l]["SNWFLL_1HOUR_TOTAL"] = ru_data["point_data"][asm_id_rp]["FCST"][l]["SNWFLL_1HOUR_TOTAL"] # 時間降雪量
          refw_smallz["point_data"][point_count]["FCAS"][l]["second_flag"] = 0 # 第二通行止めレベルOFF/ON【0,1】
          refw_smallz["point_data"][point_count]["FCAS"][l]["use_second"] = 0  # 第２通行止め基準適用期間【0,1】 202205
          # 露点温度
          refw_smallz["point_data"][point_count]["FCAS"][l]["DEWTMP"] = LACK_VALUE_16
          if zids_winter != nil && $dewtmp_avg != nil
            zids_winter.each{|wzone_id|
              # 支社ID
              if wzone_id[0,2] != zone_id[0,2]
                wsid = wzone_id + zone_id
                if bcode_mismach.index(wsid) == nil
                  $log.write("summer zone id=%s winter zone id=%s branch code not match." % [zone_id,wzone_id])
                  bcode_mismach.push(wsid)
                end
                next
              end
              if $dewtmp_avg[wzone_id] == nil || $dewtmp_avg[wzone_id][ft] == nil
                $log.write("winter zone_id=%s FCAS_time=%s dewtmp is not exist." % [ wzone_id, ft.to_s ]) if $verbose
              else
                refw_smallz["point_data"][point_count]["FCAS"][l]["DEWTMP"] = $dewtmp_avg[wzone_id][ft]
                break
              end
            }
          end
          #
          # 時間降水量、連続雨量、土壌雨量指数
          #
          prcrin_1hour_total = ru_data["point_data"][asm_id_rp]["FCST"][l]["PRCRIN_1HOUR_TOTAL"].round
          if obs_flag
            # 実況値使用
            prcrin_prst_start_t = nil
            if obs_prec_integ[ft] != nil && obs_prec_integ[ft][mk2_pointid] != nil
              if obs_prec_integ[ft][mk2_pointid]["prec60"] >= 0 && obs_prec_integ[ft][mk2_pointid]["precinteg"] >= 0
                # 実況値連続雨量あり
                $log.write("%s %s precinteg=%s" % [ft.to_s,mk2_pointid,obs_prec_integ[ft][mk2_pointid]["precinteg"]]) if $verbose
                observation_time = ft
                prcrin_prst = (obs_prec_integ[ft][mk2_pointid]["precinteg"] / 10.0).truncate
                prcrin_1hour_total = (obs_prec_integ[ft][mk2_pointid]["prec60"] / 10.0).truncate
                if obs_prec_integ[ft][mk2_pointid]["StartTime"] > 0                              # 第２通行止め
                  prcrin_prst_start_t = Time.at(obs_prec_integ[ft][mk2_pointid]["StartTime"])    # 第２通行止め
                end                                                                              # 第２通行止め
                if obs_prec_integ[ft][mk2_pointid]["ResetTime"] > 0                              # 第２通行止め
                  prcrin_prst_reset_t = Time.at(obs_prec_integ[ft][mk2_pointid]["ResetTime"])
                end                                                                              # 第２通行止め
                if obs_prec_integ[ft][mk2_pointid]["ResetStart"] > 0                             # 第２通行止め
                  prcrin_prst_rstart_t = Time.at(obs_prec_integ[ft][mk2_pointid]["ResetStart"])  # 第２通行止め
                end                                                                              # 第２通行止め
                if obs_prec_integ[ft][mk2_pointid]["UpdateTime"] > 0                                              # 第２通行止め
                  prcrin_prst_update_t = Time.at(obs_prec_integ[ft][mk2_pointid]["UpdateTime"])                   # 第２通行止め
                end                                                                                               # 第２通行止め
                if obs_prec_integ[ft][mk2_pointid]["SecondTime"] > 0                                              # 202205
                  prcrin_prst_second_t = Time.at(obs_prec_integ[ft][mk2_pointid]["SecondTime"])                   # 202205
                end                                                                                               # 202205
                if obs_prec_integ[ft][mk2_pointid]["S_index"] > 0
                  s_index = obs_prec_integ[ft][mk2_pointid]["S_index"]               # 土壌雨量指数
                end
                if obs_prec_integ[ft][mk2_pointid]["SoilPrec_s1"] > 0
                  ds[0] = obs_prec_integ[ft][mk2_pointid]["SoilPrec_s1"] / 10.0      # 土壌雨量指数
                end
                if obs_prec_integ[ft][mk2_pointid]["SoilPrec_s2"] > 0
                  ds[1] = obs_prec_integ[ft][mk2_pointid]["SoilPrec_s2"] / 10.0      # 土壌雨量指数
                end
                if obs_prec_integ[ft][mk2_pointid]["SoilPrec_s3"] > 0
                  ds[2] = obs_prec_integ[ft][mk2_pointid]["SoilPrec_s3"] / 10.0      # 土壌雨量指数
                end
              else
                # 実況値連続雨量なし
                if ft <= ho_just
                  # hoの正時以前
                  $log.write("precinteg point %s ft=%s invalid data." % [mk2_pointid,ft.to_s]) if $verbose
                  prcrin_1hour_total = LACK_VALUE_16
                  prcrin_prst = prcrin_prst_p
                else
                  # 生値の場合は常に最新連続雨量
                  # 最新の実況連続雨量を取得し、Ho+1のコマの予測時間雨量を足したものをHo+1のコマの連続雨量とする。
                  precinteg = get_latest_prec_integ(ho_just,latest_obs,mk2_pointid,obs_prec_integ,prcrin_prst_nmm,prcrin_prst_nhour)
                  if precinteg != nil
                    prcrin_prst_p = precinteg[0]
                    observation_time = precinteg[1]
                    if precinteg[2] != nil
                      prcrin_prst_update_t = precinteg[2]
                    end
                    if precinteg[3] != nil
                      prcrin_prst_reset_t = precinteg[3]
                    end
                    if precinteg[4] != nil
                      prcrin_prst_start_t = precinteg[4]
                    end
                    if precinteg[5] != nil
                      prcrin_prst_rstart_t = precinteg[5]
                    end
                    if precinteg[6] != nil
                      prcrin_prst_second_t = precinteg[6]
                    end
                    if precinteg[7]
                      prcrin_prst_p = 0
                      prcrin_prst_start_t = nil
                      prcrin_prst_rstart_t = prcrin_prst_reset_t
                      prcrin_prst_reset_t = ft
                    end
                    if prcrin_prst_p <= 0
                      a_flag = true
                    end
                    # 土壌雨量指数
                    if precinteg[8] > 0
                      s_index = precinteg[8]
                    end
                    if precinteg[9] > 0
                      ds[0] = precinteg[9] / 10.0
                    end
                    if precinteg[10] > 0
                      ds[1] = precinteg[10] / 10.0
                    end
                    if precinteg[11] > 0
                      ds[2] = precinteg[11] / 10.0
                    end
                  end
                  obs_flag = false
                end
              end
            else
              # 実況値配信抜け
              if ft <= ho_just
                # 現在時刻の正時以前
                $log.write("precinteg point %s ft=%s data not exist." % [mk2_pointid,ft.to_s])
                prcrin_1hour_total = LACK_VALUE_16
                prcrin_prst = prcrin_prst_p
              else
                # 生値の場合は常に最新連続雨量
                # 最新の実況連続雨量を取得し、Ho+1のコマの予測時間雨量を足したものをHo+1のコマの連続雨量とする。
                precinteg = get_latest_prec_integ(ho_just,latest_obs,mk2_pointid,obs_prec_integ,prcrin_prst_nmm,prcrin_prst_nhour)
                if precinteg != nil
                  prcrin_prst_p = precinteg[0]
                  observation_time = precinteg[1]
                  if precinteg[2] != nil
                    prcrin_prst_update_t = precinteg[2]
                  end
                  if precinteg[3] != nil
                    prcrin_prst_reset_t = precinteg[3]
                  end
                  if precinteg[4] != nil
                    prcrin_prst_start_t = precinteg[4]
                  end
                  if precinteg[5] != nil
                    prcrin_prst_rstart_t = precinteg[5]
                  end
                  if precinteg[6] != nil
                    prcrin_prst_second_t = precinteg[6]
                  end
                  if precinteg[7]
                    prcrin_prst_p = 0
                    prcrin_prst_start_t = nil
                    prcrin_prst_rstart_t = prcrin_prst_reset_t
                    prcrin_prst_reset_t = ft
                  end
                  if prcrin_prst_p <= 0
                    a_flag = true
                  end
                  # 土壌雨量指数
                  if precinteg[8] > 0
                    s_index = precinteg[8]
                  end
                  if precinteg[9] > 0
                    ds[0] = precinteg[9] / 10.0
                  end
                  if precinteg[10] > 0
                    ds[1] = precinteg[10] / 10.0
                  end
                  if precinteg[11] > 0
                    ds[2] = precinteg[11] / 10.0
                  end
                end
                obs_flag = false
              end
            end
          end
          refw_smallz["point_data"][point_count]["FCAS"][l]["PRCRIN_1HOUR_TOTAL"] = prcrin_1hour_total
          # 要素間整合
          if !obs_flag
            adjust_elements(l, ru_data["point_data"][asm_id_rp]["FCST"][l]["SNWFLL_1HOUR_TOTAL"], refw_smallz["point_data"][point_count]["FCAS"])
          end
          prcrin_1hour_total = refw_smallz["point_data"][point_count]["FCAS"][l]["PRCRIN_1HOUR_TOTAL"]
          prcrin_fccst[ft] = prcrin_1hour_total
          if !obs_flag
            # FCST
            prcrin_prst_input = [ft, mk2_pointid,obs_prec_integ,prcrin_fccst,prcrin_prst_p,prcrin_prst_nmm,prcrin_prst_nhour,prcrin_prst_update_t,prcrin_prst_reset_t,prcrin_prst_start_t,prcrin_prst_rstart_t,a_flag,prcrin_prst_second_t]
            prcrin_prst_output = get_prcrin_prst_mmm_nhour(prcrin_prst_input)
            a_flag = false if a_flag
            prcrin_prst = prcrin_prst_output[0]
            prcrin_prst_update_t = prcrin_prst_output[1]
            prcrin_prst_reset_t = prcrin_prst_output[2]
            prcrin_prst_rstart_t = prcrin_prst_output[3]
            prcrin_prst_start_t = prcrin_prst_output[4]
            reset_flag = prcrin_prst_output[5]
            prcrin_prst_second_p = prcrin_prst_second_t
            prcrin_prst_second_t = prcrin_prst_output[6]  # 202205
          end
          refw_smallz["point_data"][point_count]["FCAS"][l]["PRCRIN_PRST"] = prcrin_prst
          # 路面状態
          get_rdcnd(l, refw_smallz["point_data"][point_count]["FCAS"])
          # 吹雪指数
          wndspd = refw_smallz["point_data"][point_count]["FCAS"][l]["WNDSPD"]
          snwfll = refw_smallz["point_data"][point_count]["FCAS"][l]["SNWFLL_1HOUR_TOTAL"]
          airtmp = refw_smallz["point_data"][point_count]["FCAS"][l]["AIRTMP"]
          wx = refw_smallz["point_data"][point_count]["FCAS"][l]["WX"]
          refw_smallz["point_data"][point_count]["FCAS"][l]["SSTMI"] = get_sstm(wndspd,snwfll,airtmp,wx)
          # 風10Vスケール判定
          if table_rain_point["judge_type"] == 2 || table_rain_point["judge_type"] == 3
            refw_smallz["point_data"][point_count]["FCAS"][l]["WIND_VSCAL"] = get_scale_wind(table_rain_point["threshold_wind"],wndspd)
          else
            refw_smallz["point_data"][point_count]["FCAS"][l]["WIND_VSCAL"] = 0
          end
          # 第２通行止めを考慮しない 202205
          use_sflag = 0
          # 雨10Vスケール判定
          if table_rain_point["judge_type"] == 1 || table_rain_point["judge_type"] == 3
            scale = get_rain_scale(table_rain_point["threshold_rain"],prcrin_1hour_total,prcrin_prst,use_sflag)
            refw_smallz["point_data"][point_count]["FCAS"][l]["RAIN_VSCAL"] = scale
            if enable_sflag == 1  # 新第２通行止め判定データの保存 202205
              small_zone_save[rain_point][ft]["StartTime"] = prcrin_prst_start_t
              small_zone_save[rain_point][ft]["ResetTime"] = prcrin_prst_reset_t
              small_zone_save[rain_point][ft]["ResetStart"] = prcrin_prst_rstart_t
              small_zone_save[rain_point][ft]["prv_second"] = prcrin_prst_second_p
              small_zone_save[rain_point][ft]["SecondTime"] = prcrin_prst_second_t
              small_zone_save[rain_point][ft]["obs_flag"] = obs_flag
            end
          else
            refw_smallz["point_data"][point_count]["FCAS"][l]["RAIN_VSCAL"] = 0
          end
          #
          # 土壌雨量指数スケール判定
          #
          refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"] = 0
          if !nf_flag
            # 予測値使用
            # 土壌雨量指数タンク1貯留高取得
            # 予測値は欠測なし。負数は0とみなす。
            r60 = prcrin_1hour_total > 0 ? prcrin_1hour_total : 0
            ds = get_fcst_soil_prec_index(r60, ds)
            s_index = (( ds[0] + ds[1] + ds[2] ) * 10).truncate
          end
          soilp_scale_count = 0
          if soil_prec_lvldata.size > 0
            if obs_flag
              if obs_rain_scale[ft] != nil && obs_rain_scale[ft][rain_point] != nil
                soilp_vscal = obs_rain_scale[ft][rain_point]["soilp_vscal"]
                refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"] = soilp_vscal
                s_index_by_h_prec = obs_rain_scale[ft][rain_point]["s_index_by_h_prec"]
                soil_prec_lvldata.each_key{|lvl|
                  refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"].array_resize(soilp_scale_count+1)
                  refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"][soilp_scale_count]["scale"] = lvl
                  refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"][soilp_scale_count]["value"] = LACK_VALUE_16
                  if s_index_by_h_prec != nil && s_index_by_h_prec[lvl] != nil
                    refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"][soilp_scale_count]["value"] = s_index_by_h_prec[lvl]
                  else
                    $log.write("%s %s data not exist in s_index_by_h_prec." % [ft.to_s,rain_point])
                  end
                  soilp_scale_count += 1
                }
              end
            else
              # 予測値使用
              # 土壌雨量スケール取得
              soilp_vscal, s_index_by_h_prec = get_soilprec_scale( prcrin_1hour_total, s_index * 0.1, soil_prec_lvldata )
              refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"] = soilp_vscal
              # 土壌雨量スケール取得
              soil_prec_lvldata.each_key{|lvl|
                refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"].array_resize(soilp_scale_count+1)
                refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"][soilp_scale_count]["scale"] = lvl
                refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_index"][soilp_scale_count]["value"] = s_index_by_h_prec[lvl] * 10
                soilp_scale_count += 1
              }
            end
            # 土壌雨量指数スケール
            if refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"] > refw_smallz["point_data"][point_count]["FCAS"][l]["RAIN_VSCAL"]
              refw_smallz["point_data"][point_count]["FCAS"][l]["RAIN_CSCAL"] = refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"]
            end
          end
          if !obs_flag && nf_flag
            nf_flag = false
          end
          refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_SCALE_count"] = soilp_scale_count
          refw_smallz["point_data"][point_count]["FCAS"][l]["s_index"] = s_index  # 土壌雨量指数 整数値 10倍値（0.1mm単位）切り捨て
          refw_smallz["point_data"][point_count]["FCAS"][l]["s1"] = ds[0]  # 土壌雨量指数タンク1貯留高
          refw_smallz["point_data"][point_count]["FCAS"][l]["s2"] = ds[1]  # 土壌雨量指数タンク2貯留高
          refw_smallz["point_data"][point_count]["FCAS"][l]["s3"] = ds[2]  # 土壌雨量指数タンク3貯留高
          if reset_flag
            prcrin_prst_p = 0
            prcrin_prst_start_t = nil
          else
            prcrin_prst_p = prcrin_prst
          end
          # 中区間小区間最大スケール
          rain_vscal = refw_smallz["point_data"][point_count]["FCAS"][l]["RAIN_VSCAL"]
          wind_vscal = refw_smallz["point_data"][point_count]["FCAS"][l]["WIND_VSCAL"]
          soilp_vscal = refw_smallz["point_data"][point_count]["FCAS"][l]["SOILP_VSCAL"]  # 土壌雨量指数
          get_max_scale(max_scale,ft,zone_id,small_zone,rain_vscal,wind_vscal,soilp_vscal,use_sflag,use_sflag)  # 202205
        end  # FTループ 202205
        # 連続雨量計算の起算実況日時（実況値の最新観測日時）
        if observation_time == nil
          refw_smallz["point_data"][point_count]["observation_time"].set_value_time(Time.at(0))
          $log.write("precinteg point %s no available data." % [mk2_pointid]) if $verbose
        else
          refw_smallz["point_data"][point_count]["observation_time"].set_value_time(observation_time)
        end
        point_count += 1
      }  # 雨量局ループ 202205
      refw_smallz["point_count"] = point_count
      #
      # 新第２通行止め 202205
      #
      road_close_2_2(refw_smallz,small_zone_save,max_scale,fcst_count,point_count,zone_id,small_zone,obs_rain_scale)
    } # 小区間ループ 202205
    zone_area_count += 1
  }  # 中区間ループ 202205
  refw["ZONE_count"] = zone_area_count
  if zone_area_count < 1
    $log.write("available data not exist in input data.")
    exit
  end
  # 中区間小区間最大スケール
  set_max_scale(refw,max_scale)
  # ファイル出力
  if $savefilename != nil
    gw.save($savefilename)
  end
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
def read_ru(input_data)
  ru_data = {}
  # 入力ファイル読み込み
  gr = GenRw.open(input_data)
  refr = gr.get_value_ref
  announced_date = refr["announced_date"].get_value_time
  ru_data["announced_date"] = announced_date
  $log.write("announced_date %s" % [announced_date.to_s])
  ru_data["point_data"] = {}
  asm_area_count = refr["point_count"]
  for i in 0...asm_area_count
    asm_id = refr["point_data"][i]["ASM_ID"]
    if $rd_table_summer["all_asmids"].index(asm_id) != nil
      ru_data["point_data"][asm_id] = {}
      ru_data["point_data"][asm_id]["SOIL_or_BRG"] = refr["point_data"][i]["SOIL_or_BRG"]
      ru_data["point_data"][asm_id]["FCST"] = []
      fcst_count = refr["point_data"][i]["FCST_count"]
      for j in 0...fcst_count
        ftdata = {}
        ftdata["FCSTD"] = refr["point_data"][i]["FCST"][j]["FCSTD"].get_value_time
        ftdata["WX"] = refr["point_data"][i]["FCST"][j]["WX"]
        ftdata["AIRTMP"] = refr["point_data"][i]["FCST"][j]["AIRTMP"]
        ftdata["WNDSPD"] = refr["point_data"][i]["FCST"][j]["WNDSPD"]
        ftdata["WNDDIR"] = refr["point_data"][i]["FCST"][j]["WNDDIR"]
        ftdata["RDTMP"] = refr["point_data"][i]["FCST"][j]["RDTMP"]
        ftdata["GUSTS"] = refr["point_data"][i]["FCST"][j]["GUSTS"]
        ftdata["PRCRIN_1HOUR_TOTAL"] = refr["point_data"][i]["FCST"][j]["PRCRIN_1HOUR_TOTAL"]
        ftdata["SNWFLL_1HOUR_TOTAL"] = refr["point_data"][i]["FCST"][j]["SNWFLL_1HOUR_TOTAL"]
        ru_data["point_data"][asm_id]["FCST"].push(ftdata)
      end
    end
  end
  return ru_data
end

def main()
  opt = OptionParser.new
  logfile = nil
  input_tagid = ""
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
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
  lock_f = lock_and_wait($config["spool_dir"] + $config["lock_file_raw_summer"][input_tagid])
  if input_tagid == "" || $config[input_tagid] == nil
    $log.write("input_tagid=%s not supported." % [input_tagid])
    return
  else
    $output_ids = $config[input_tagid]
  end
  $log.write("spool data read start.")
  # 暖候期テーブルのスプールを読む
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_summer_spool"])
  dbdata.transaction() do
    $rd_table_summer = dbdata['root']
  end
  if $rd_table_summer == nil || $rd_table_summer.size < 1
    $log.write("%s data not spooled." % [$config["rd_table_summer_spool"]])
    return
  end
  # 連続雨量観測地点のスプールを読む
  dbdata = PStore.new($config["rd_obs_point_list_spool"])
  dbdata.transaction() do
    $rd_obs_point_list = dbdata['root']
  end
  if $rd_obs_point_list == nil || $rd_obs_point_list.size < 1
    $log.write("%s data not spooled." % [$config["rd_obs_point_list_spool"]])
    $rd_obs_point_list = nil
  end
  # 寒候期テーブルのスプールを読む
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_winter_spool"])
  dbdata.transaction() do
    $rd_table_winter = dbdata['root']
  end
  if $rd_table_winter == nil || $rd_table_winter.size < 1
    $log.write("%s data not spooled." % [$config["rd_table_winter_spool"]])
    $rd_table_winter = nil
  else
    # 露点温度スプールデータ読み出し
    spool_fname = $config["dewtmp_spool_avg"]
    if File.exist?(spool_fname)
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
        $dewtmp_avg = nil
      end
    else
      $log.write("%s data not spooled." % [$config["dewtmp_spool_avg"]])
    end
  end
  # SSH COMMAND
  cmd = "ssh amoeba@%s /usr/amoeba/tools/LAND_SRF_RD_2020/scripts/copy_pst_scp.rb /usr/amoeba/tools/LAND_SRF_RD_2020/config/config.yml /home/amoeba/log/LAND_SRF_RD_2020/copy_pst_scp.log" % [$config["raw_host"]]
  $log.write(cmd)
  ret = system(cmd)
  if(!ret)
    $log.write("SSH COMMAND FAILED")
  end
  # 連続雨量レベル3超過時刻
  dbdata = PStore.new($config["rd_level3_time_list_spool"])
  dbdata.transaction() do
    $level3_time_list = dbdata['root']
  end
  # 連続雨量最終更新時刻
  dbdata = PStore.new($config["rd_latest_time_list"])
  dbdata.transaction() do
    $latest_time_list = dbdata['root']
  end
  # 土壌雨量スケールの閾値
  s_path = $config["cl_data_spool_dir"] + "*.pst"
  fnams = Dir.glob(s_path)
  fnams.each{|fnam|
    dbdata = PStore.new(fnam)
    dbdata.transaction() do
      if dbdata['root'] != nil && dbdata['root'].size > 0
        $soilprec_threshold_info = $soilprec_threshold_info.merge(dbdata['root'])
      end
    end
  }
  $log.write("spool data read end.")
  # 暖候期出力RUの生成
  ru_data = read_ru(ARGV[1])
  make_summer_ru(ru_data)
  unlock_and_wait(lock_f)
  $log.write("***** proc end normally *****")
end
main()
