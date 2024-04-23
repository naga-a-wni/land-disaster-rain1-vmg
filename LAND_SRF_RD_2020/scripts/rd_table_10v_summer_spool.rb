#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require "rexml/document"

include REXML    # so that we don’t have to prefix everything
                 # with REXML::...

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require "send_mail.rb"

$verbose = false

$config = nil
$save_data = {}
# 全連続雨量観測地点情報
# $obs_point_list[tagid][lclid] = reset condition
$obs_point_list = {}
# 連続雨量の計算情報と雨量局情報の紐づけ情報
# $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level]['PRCRIN_prst'] = prcrin_prst
#                                                                    ['PRCRIN_1hour'] = prcrin_1hour
#                                                                    ['option'] = option
$mk2_point_list = {}
# 連続雨量に使用する全解析雨量のASMID
$analysis_point_list = []

# <?xml version='1.0' encoding='utf-8'?>
# <list info="RD_ZONE" issue="2009-05-18T09:17:41">
#   <SMMR_ZONE>
#     <ZONE_ID>140100000101</ZONE_ID>
#     <ZONE_NAME>国縫IC〜長万部IC</ZONE_NAME>
#     <DAYTM_INT  start="9 " end="17 "/>←追加
#     <NIGHT_INT  start="17 " end="9 "/>←追加
#     <DAYTM_MRF_INT  start="9 " end="18 "/>←追加
#     <NIGHT_MRF_INT  start="18 " end="9 "/>←追加
#     <small_ZONE>
#       <ZONE_ID>21020001000101</ZONE_ID>
#       <ZONE_NAME>小倉東～小倉南</ZONE_NAME>
#       <RAIN_POINT>
#         <RAIN_LCLID>21020001000101-0202-prec</RAIN_LCLID>
#         <ASM_ID>AS0984</ASM_ID>
#         <ASM_ID_child>AS0984,AS0975</ASM_ID_child>←追加
#         <daihyo_flg>0</daihyo_flg>
#         <RAIN_LCLID_NAME>小倉東IC</RAIN_LCLID_NAME>
#         <data_name>NEXCO北海道</data_name>
#         <tagid>402200351</tagid>
#         <obs_point_name>江別西</obs_point_name>
#         <LCLID>0101</LCLID>
#         <reset_hour>6</reset_hour>
#         <reset_prec>20</reset_prec>
#         <judge_type>1</judge_type>
#         <second_flg>1</second_flg>
#         <RAIN_THRLD>
#           <judge_level>100</judge_level>
#           <PRCRIN_1HOUR unit="mm">20</PRCRIN_1HOUR>
#           <PRCRIN_PRST unit="mm">200</PRCRIN_PRST>
#           <option>1</option>
#         </RAIN_THRLD>
#         <WIND_THRLD>
#           <judge_level>100</judge_level>
#           <WNDSPD unit="mps">25</WNDSPD>
#         </WIND_THRLD>
#       </RAIN_POINT>
#     </small_ZONE>
#   </SMMR_ZONE>
# </list>

def load_pntfile(xmlfile)
  # 中区間に紐づく全要素
  points = {}
  #
  # 編集後寒候期→暖候期データ生成情報  
  # ASM_IDが含まれる中区間ID
  # winter_summer[ASM_ID] = [zone_id,zone_id,zone_id...]
  #
  winter_summer = {}
  # 冬に紐づかない中区間ID
  summer_only = []
  # 連続雨量リセット時間最大値
  max_reseet_hour = 0
  # 暖候期全ASMID
  all_asmids = []
  # 短期日中夜間全開始時刻
  srf_day_night = []
  # 中期日中夜間最早開始時刻
  mrf_day_night = [9,18]
  # asm地点と日中夜間定義紐づけ
  asm_daynight = {}
  # XMLファイルオープン
  dest = open(xmlfile, "r+")
  if !dest.flock( File::LOCK_EX )
    log.write("File [#{destpath}] lock failed.")
  end
  doc = Document.new(dest)
  dest.flock( File::LOCK_UN )
  dest.close
  # 中区間ループ
  # 必須要素がない場合はエラーで落として止める
  doc.elements.each('list/SMMR_ZONE'){|zone|
    z = zone.elements
    zone_id = z['ZONE_ID'].text
    if points.has_key?(zone_id)
      print "ZONE_ID=%s duplicated.\n" % [zone_id]
    end
    print "ZONE_ID=%s\n" % [zone_id]
    points[zone_id] = {}
    points[zone_id]["SMALL_ZONE"] = {}
    points[zone_id]["NAME"] = z['ZONE_NAME'].text
    mrf_daynight = {}
    # 短期日中夜間
    if z["DAYTM_INT "] == nil
      print "ZONE_ID=%s SRF daynight not exist.\n" % [zone_id] if $verbose
      mrf_daynight["DAYTM"] = {
        "start" => 9,
        "end"   => 17
      }
      mrf_daynight["NIGHT"] = {
        "start" => 17,
        "end"   => 9
      }
    else
      mrf_daynight["DAYTM"] = {
        "start" => z["DAYTM_INT "].attributes["start"].to_i,
        "end"   => z["DAYTM_INT "].attributes["end"].to_i
      }
      mrf_daynight["NIGHT"] = {
        "start" => z["NIGHT_INT "].attributes["start"].to_i,
        "end"   => z["NIGHT_INT "].attributes["end"].to_i
      }
    end
    # 短期の日中夜間を3の倍数に
    dnst = mrf_daynight["DAYTM"]["end"]
    if mrf_daynight["DAYTM"]["end"] % 3 != 0
      dnst = dnst + 3 - mrf_daynight["DAYTM"]["end"] % 3
    end
    mrf_daynight["srf_day_end"] = dnst
    if srf_day_night.index(dnst) == nil
      srf_day_night.push(dnst)
    end
    dnst = mrf_daynight["NIGHT"]["end"]
    if mrf_daynight["NIGHT"]["end"] % 3 != 0
      dnst = dnst + 3 - mrf_daynight["NIGHT"]["end"] % 3
    end
    mrf_daynight["srf_night_end"] = dnst
    if srf_day_night.index(dnst) == nil
      srf_day_night.push(dnst)
    end
    # 中期日中夜間
    if z["DAYTM_MRF_INT "] == nil
      print "ZONE_ID=%s MRF daynight not exist.\n" % [zone_id] if $verbose
      mrf_daynight["DAYTM_MRF"] = {
        "start" => 9,
        "end"   => 18
      }
      mrf_daynight["NIGHT_MRF"] = {
        "start" => 18,
        "end"   => 9
      }
    else
      mrf_daynight["DAYTM_MRF"] = {
        "start" => z["DAYTM_MRF_INT "].attributes["start"].to_i,
        "end"   => z["DAYTM_MRF_INT "].attributes["end"].to_i
      }
      mrf_daynight["NIGHT_MRF"] = {
        "start" => z["NIGHT_MRF_INT "].attributes["start"].to_i,
        "end"   => z["NIGHT_MRF_INT "].attributes["end"].to_i
      }
      # 中期の日中夜間チェック
      errdn = false
      if mrf_daynight["DAYTM_MRF"]["start"] % 3 != 0 || mrf_daynight["DAYTM_MRF"]["end"] % 3 != 0
        errdn = true
      end
      if mrf_daynight["NIGHT_MRF"]["start"] % 3 != 0 || mrf_daynight["NIGHT_MRF"]["end"] % 3 != 0
        errdn = true
      end
      if mrf_daynight["DAYTM_MRF"]["start"] != mrf_daynight["NIGHT_MRF"]["end"]
        errdn = true
      end
      if mrf_daynight["NIGHT_MRF"]["start"] != mrf_daynight["DAYTM_MRF"]["end"]
        errdn = true
      end
      if [9,12,15].index(mrf_daynight["DAYTM_MRF"]["end"] - mrf_daynight["DAYTM_MRF"]["start"]) == nil
        errdn = true
      end
      if errdn
        print "ZONE_ID=%s MRF daynight not suport.\n" % [zone_id]
        mrf_daynight["DAYTM_MRF"] = {
          "start" => 9,
          "end"   => 18
        }
        mrf_daynight["NIGHT_MRF"] = {
          "start" => 18,
          "end"   => 9
        }
      else
        if mrf_day_night[0] > mrf_daynight["DAYTM_MRF"]["start"]
          mrf_day_night[0] = mrf_daynight["DAYTM_MRF"]["start"]
        end
        if mrf_day_night[1] > mrf_daynight["NIGHT_MRF"]["start"]
          mrf_day_night[1] = mrf_daynight["NIGHT_MRF"]["start"]
        end
      end
    end
    # 小区間ループ
    z.each("small_ZONE"){|small_zone|
      sz = small_zone.elements
      small_zid = sz['ZONE_ID'].text
      if points[zone_id]["SMALL_ZONE"].has_key?(small_zid)
        print "ZONE_ID=%s small_ZONE ZONE_ID=%s duplicated.\n" % [zone_id,small_zid]
      end
      points[zone_id]["SMALL_ZONE"][small_zid] = {}
      points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"] = {}
      points[zone_id]["SMALL_ZONE"][small_zid]["NAME"] = sz['ZONE_NAME'].text
      # 雨量局ループ
      sz.each("RAIN_POINT"){|rain_point|
        rp = rain_point.elements
        rain_pid = rp['RAIN_LCLID'].text
        if points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"].has_key?(rain_pid)
          print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s duplicated.\n" % [zone_id,small_zid,rain_pid]
        end
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid] = {}
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["NAME"] = rp['RAIN_LCLID_NAME'].text
        asm_id_rp = rp['ASM_ID'].text.strip
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["ASM_ID"] = asm_id_rp
        all_asmids.push(asm_id_rp) if all_asmids.index(asm_id_rp) == nil
        if winter_summer[asm_id_rp] == nil
          winter_summer[asm_id_rp] = []
        end
        # asm地点と中期日中夜間定義紐づけ
        asm_daynight[asm_id_rp] = mrf_daynight["DAYTM_MRF"]
        asm_daynight[asm_id_rp]["srf_day_end"] = mrf_daynight["srf_day_end"]
        asm_daynight[asm_id_rp]["srf_night_end"] = mrf_daynight["srf_night_end"]
        asm_daynight[asm_id_rp]["day_3h"] = ( mrf_daynight["DAYTM_MRF"]["end"] - mrf_daynight["DAYTM_MRF"]["start"]) / 3
        asm_daynight[asm_id_rp]["night_3h"] = ( 24 - asm_daynight[asm_id_rp]["day_3h"] * 3 ) / 3
        winter_summer[asm_id_rp].push(zone_id) if winter_summer[asm_id_rp].index(zone_id) == nil
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["daihyo_flg"] = 0
        if rp['daihyo_flg'].text.strip == "1"
          points[zone_id]["ASM_ID_daihyo"] = asm_id_rp
          points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["daihyo_flg"] = 1
          # ASM_ID_childは中区間の代表地点の子供
          asm_ids = []
          if rp['ASM_ID_child'].text != nil && rp['ASM_ID_child'].text =~ /\d/
            asm_ids = rp['ASM_ID_child'].text.split(",").map{|v| v.strip}
          else
            print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s daihyo_flg=1 but ASM_ID_child is empty.\n" % [zone_id,small_zid,rain_pid]
            summer_only.push(zone_id)
          end
          asm_ids.each{|asm_id_child|
            # asm地点と中期日中夜間定義紐づけ
            if asm_daynight[asm_id_child] == nil
              asm_daynight[asm_id_child] = mrf_daynight["DAYTM_MRF"]
              asm_daynight[asm_id_child]["srf_day_end"] = mrf_daynight["srf_day_end"]
              asm_daynight[asm_id_child]["srf_night_end"] = mrf_daynight["srf_night_end"]
              asm_daynight[asm_id_child]["day_3h"] = ( mrf_daynight["DAYTM_MRF"]["end"] - mrf_daynight["DAYTM_MRF"]["start"]) / 3
              asm_daynight[asm_id_child]["night_3h"] = ( 24 - asm_daynight[asm_id_child]["day_3h"] * 3 ) / 3
            end
          }
          all_asmids = all_asmids | asm_ids
          points[zone_id]["ASM_ID_child"] = asm_ids
        end
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["data_name"] = rp['data_name'].text
        if rp['tagid'] == nil || rp['tagid'].text == nil
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s tagid not exist\n" % [zone_id,small_zid,rain_pid]
        end
        tagid = rp['tagid'].text.strip
        if tagid == "402200981"
          tagid = "402200352"
        end
        if tagid == "402200988"
          tagid = "402200465"
        end
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["tagid"] = tagid
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["obs_point_name"] = rp['obs_point_name'].text
        if rp['LCLID'] == nil || rp['LCLID'].text == nil
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s LCLID not exist\n" % [zone_id,small_zid,rain_pid]
        end
        lclid = rp['LCLID'].text.strip
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["LCLID"] = lclid
        reset_hour = rp['reset_hour'].text.strip.to_i
        if reset_hour > 1 && reset_hour < 100
          points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["reset_hour"] = reset_hour
          max_reseet_hour = reset_hour if max_reseet_hour < reset_hour
        else
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s reset_hour=%s" % [zone_id,small_zid,rain_pid,rp['reset_hour'].text]
        end
        reset_prec = rp['reset_prec'].text.strip.to_i
        if reset_prec >= 0 && reset_prec < 1000
          points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["reset_prec"] = reset_prec
        else
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s reset_prec=%s" % [zone_id,small_zid,rain_pid,rp['reset_prec'].text]
        end
        if rp['judge_type'].text.strip  =~ /^([123])$/
          points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["judge_type"] = $1.to_i
        else
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s judge_type=%s" % [zone_id,small_zid,rain_pid,rp['judge_type'].text]
        end
        if rp['second_flg'].text.strip  =~ /^([01])$/
          points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["second_flag"] = $1.to_i
        else
          raise "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s second_flg=%s" % [zone_id,small_zid,rain_pid,rp['second_flg'].text]
        end
        # 観測地点情報
        if $obs_point_list[tagid] == nil
          $obs_point_list[tagid] = {}
        end
        if $obs_point_list[tagid][lclid] == nil
          $obs_point_list[tagid][lclid] = []
        end
        reset_condition = "%s_%s" % [reset_prec,reset_hour]
        if $obs_point_list[tagid][lclid].index(reset_condition) == nil
          $obs_point_list[tagid][lclid].push(reset_condition)
        end
        if tagid == "411023885" && $analysis_point_list.index(lclid) == nil
          $analysis_point_list.push(lclid)
        end
        # 連続雨量の計算情報と雨量局情報の紐づけ情報
        pointid = "%s_%s_%s" % [tagid,lclid,reset_condition]
        if $mk2_point_list[pointid] == nil
          $mk2_point_list[pointid] = {}
        end
        if $mk2_point_list[pointid][zone_id] == nil
          $mk2_point_list[pointid][zone_id] = {}
        end
        if $mk2_point_list[pointid][zone_id][small_zid] == nil
          $mk2_point_list[pointid][zone_id][small_zid] = {}
        end
        if $mk2_point_list[pointid][zone_id][small_zid][rain_pid] == nil
          $mk2_point_list[pointid][zone_id][small_zid][rain_pid] = {}
        end
        # しきい値（雨）のデータのループ
        rain_level = {}
        rp.each("RAIN_THRLD"){|threshold_rain|
          tr = threshold_rain.elements
          if tr['judge_level'] != nil && tr['judge_level'].text != nil
            if tr['judge_level'].text.strip  =~ /^(\d+)$/
              judge_level = $1.to_i
              if rain_level[judge_level] != nil
                "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s duplicated.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
              rain_level[judge_level] = {}
              if tr['PRCRIN_1HOUR'] != nil && tr['PRCRIN_1HOUR'].text != nil
                prcrin_1hour = tr['PRCRIN_1HOUR'].text.strip.to_i
                if prcrin_1hour > 0
                  rain_level[judge_level]['PRCRIN_1hour'] = prcrin_1hour
                  if $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] == nil
                    $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] = {}
                  end
                  $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level]['PRCRIN_1hour'] = prcrin_1hour
                else
                  print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s PRCRIN_1HOUR=%s\n" % [zone_id,small_zid,rain_pid,judge_level,tr['PRCRIN_1HOUR'].text] if $verbose
                end
              else
                print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s PRCRIN_1HOUR not exist.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
              if tr['PRCRIN_PRST'] != nil && tr['PRCRIN_PRST'].text != nil
                prcrin_prst = tr['PRCRIN_PRST'].text.strip.to_i
                if prcrin_prst > 0
                  rain_level[judge_level]['PRCRIN_prst'] = prcrin_prst
                  if $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] == nil
                    $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] = {}
                  end
                  $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level]['PRCRIN_prst'] = prcrin_prst
                else
                  print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s PRCRIN_PRST=%s\n" % [zone_id,small_zid,rain_pid,judge_level,tr['PRCRIN_PRST'].text] if $verbose
                end
              else
                print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s PRCRIN_PRST not exist.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
              rain_level[judge_level]['option'] = 0
              if tr['option'] != nil && tr['option'].text != nil
                if tr['option'].text.strip  =~ /^([012])$/
                  option = $1.to_i
                  rain_level[judge_level]['option'] = option
                  if $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] == nil
                    $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level] = {}
                  end
                  $mk2_point_list[pointid][zone_id][small_zid][rain_pid][judge_level]['option'] = option
                else
                  print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s option=%s\n" % [zone_id,small_zid,rain_pid,judge_level,tr['option'].text]
                end
              else
                print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s option not exist.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
            else
              print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level=%s\n" % [zone_id,small_zid,rain_pid,tr['judge_level'].text] if $verbose
            end
          else
            print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s RAIN_THRLD judge_level not exist.\n" % [zone_id,small_zid,rain_pid]
          end
        }
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["threshold_rain"] = rain_level
        # しきい値（風）のデータのループ
        wind_level = {}
        rp.each("WIND_THRLD"){|threshold_wind|
          tw = threshold_wind.elements
          if tw['judge_level'] != nil && tw['judge_level'].text != nil
            if tw['judge_level'].text.strip  =~ /^(\d+)$/
              judge_level = $1.to_i
              if wind_level[judge_level] != nil
                "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s WIND_THRLD judge_level=%s duplicated.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
              if tw['WNDSPD'] != nil && tw['WNDSPD'].text != nil
                wndspd = tw['WNDSPD'].text.strip.to_i
                if wndspd > 0
                  wind_level[judge_level] = wndspd
                else
                  print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s WIND_THRLD judge_level=%s WNDSPD=%s\n" % [zone_id,small_zid,rain_pid,judge_level,wndspd]
                end
              else
                print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s WIND_THRLD judge_level=%s WNDSPD not exist.\n" % [zone_id,small_zid,rain_pid,judge_level]
              end
            else
              print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s WIND_THRLD judge_level=%s\n" % [zone_id,small_zid,rain_pid,tw['judge_level'].text] if $verbose
            end
          else
            print "ZONE_ID=%s small_ZONE ZONE_ID=%s RAIN_POINT=%s WIND_THRLD judge_level not exist.\n" % [zone_id,small_zid,rain_pid]
          end
        }
        points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"][rain_pid]["threshold_wind"] = wind_level
      }  # 雨量局ループ
      if points[zone_id]["SMALL_ZONE"][small_zid]["RAIN_POINT"].size < 1
        # 雨量局を持たない小区間はエラー
        raise "ZONE_ID=%s small_ZONE ZONE_ID=%s has no RAIN_POINT" % [zone_id,small_zid]
      end
    }  # 小区間ループ
    if points[zone_id]["SMALL_ZONE"].size < 1
      # 小区間を持たない中区間はエラー
      raise "ZONE_ID=%s has no small_ZONE" % [zone_id]
    end
    if points[zone_id]["ASM_ID_daihyo"] == nil
      # 代表雨量局を区間を持たない中区間はエラー
      raise "ZONE_ID=%s has no daihyo_flg=1" % [zone_id]
    end
  }  # 中区間ループ
  # 中区間に紐づく全要素
  $save_data["zone_elements"] = points
  print "all zone count=%d\n" % [points.size]
  #
  # 編集後寒候期→暖候期データ生成情報  
  # ASM_IDが含まれる中区間ID
  # winter_summer[ASM_ID] = [zone_id,zone_id,zone_id...]
  #
  $save_data["winter_summer"] = winter_summer
  # 連続雨量リセット時間最大値
  $save_data["max_reseet_hour"] = max_reseet_hour
  print "max_reseet_hour=%d\n" % [max_reseet_hour]
  # 暖候期全ASMID
  $save_data["all_asmids"] = all_asmids
  # 冬に紐づかない中区間ID
  $save_data["summer_only"] = summer_only
  # 短期日中夜間全開始時刻
  $save_data["srf_day_night"] = srf_day_night
  # 中期日中夜間最早開始時刻
  $save_data["mrf_day_night"] = mrf_day_night
  # asm地点と日中夜間定義紐づけ
  $save_data["asm_daynight"] = asm_daynight
end

def main()
  if ARGV.size < 1
    print "Usage:#{__FILE__} <config>\n"
    return
  end
  $config = YAML.load_file(ARGV[0])
  pntfile = $config["spool_dir"] + $config["rd_table_summer"]
  if File.exist?(pntfile) == false
    print "xml file not exist %s\n" % $config["rd_table_summer"]
    return
  end
  load_pntfile(pntfile)
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_summer_spool"])
  dbdata.transaction() do
    dbdata['root'] =  $save_data
  end
  # 全連続雨量観測地点情報
  dbdata = PStore.new($config["rd_obs_point_list_spool"])
  dbdata.transaction() do
    dbdata['root'] =  $obs_point_list
  end
#  tagids = $obs_point_list.keys.sort
#  tagids.each{|tid|
#    print "obs tagid=%s\n" % [tid] if $verbose
#    lclids = $obs_point_list[tid].keys.sort
#    lclids.each{|lid|
#      cnds = $obs_point_list[tid][lid].sort
#      print "lclid=%s [%s]\n" % [lid,cnds.join(",")] if $verbose
#    }
#  }
# 連続雨量の計算情報と雨量局情報の紐づけ情報
  road_close = {}
  road_close["mk2_point_list"] = $mk2_point_list
  road_close["zone_elements"] = $save_data["zone_elements"]
  dbdata = PStore.new($config["rd_mk2_point_list_spool"])
  dbdata.transaction() do
    dbdata['root'] =  road_close
  end
  # 連続雨量に使用する全解析雨量のASMID
  dbdata = PStore.new($config["rd_analysis_point_list_spool"])
  dbdata.transaction() do
    dbdata['root'] =  $analysis_point_list
  end
  print "all analysis point=[%s]\n" % [$analysis_point_list.join(",")]
end

print "timenow=%s\n" % Time.now.to_s
begin
  main()
rescue => e
  send_mail("Table summer update failure")
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
print "timenow=%s\n" % Time.now.to_s
