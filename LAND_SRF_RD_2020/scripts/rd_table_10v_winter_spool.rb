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

LACK_VALUE_16 = -9999
SNOW_RAIN_MAX = 9999

# <?xml version='1.0' encoding='utf-8'?>
# <list info="RD_ZONE" issue="2009-05-18T09:17:41">
#   <WNTR_ZONE>
#   <ZONE_ID>140100000101</ZONE_ID>
#   <ZONE_NAME>国縫IC〜長万部IC</ZONE_NAME>
#   <SNWFLL_THRLD_10>-</SNWFLL_THRLD_10>←追加
#   <SNWFLL_THRLD_9>-</SNWFLL_THRLD_9>←追加
#   <SNWFLL_THRLD_8>-</SNWFLL_THRLD_8>←追加
#   <SNWFLL_THRLD_7>-</SNWFLL_THRLD_7>←追加
#   <SNWFLL_THRLD_6>-</SNWFLL_THRLD_6>
#   <SNWFLL_THRLD_5>10</SNWFLL_THRLD_5>
#   <SNWFLL_THRLD_4>3</SNWFLL_THRLD_4>
#   <SNWFLL_THRLD_3>0</SNWFLL_THRLD_3>
#   <AIRTMP_THRLD_2>2.4</AIRTMP_THRLD_2>
#   <PRCRIN_THRLD_2>1</PRCRIN_THRLD_2>
#   <RDTEMP_THRLD_2>2.4</RDTEMP_THRLD_2>
#   <judge_pair_and>TR</judge_pair_and>
#   <judge_pair_or>RH</judge_pair_or>
#   <ASM_ID_daihyo>AS0984</ASM_ID_daihyo>
#   <ASM_ID>AS0976,AS0975</ASM_ID>
#   <DAYTM_INT  start="9 " end="17 "/>
#   <NIGHT_INT  start="17 " end="9 "/>
#   <DAYTM_MRF_INT  start="9 " end="18 "/>←追加
#   <NIGHT_MRF_INT  start="18 " end="9 "/>←追加
#   <MAX_10V_DEF>100</MAX_10V_DEF>←追加
#   <VSCAL>
#     <SCALE value="1">1</SCALE>
#     <SCALE value="2">2,3</SCALE>
#     <SCALE value="3">4</SCALE>
#   </VSCAL>
#   <NOPRFZ_VSCAL>
#     <SCALE value="10">1</SCALE>
#     <SCALE value="20">2,3</SCALE>
#     <SCALE value="30">4</SCALE>
#   </NOPRFZ_VSCAL>
#   <NOPRFZ_PRD>5</NOPRFZ_PRD>
#   <NOPRFZ_SCALE_MINI>6</NOPRFZ_SCALE_MINI>
#   <WIND_THRLD>←追加
#     <judge_level>100</judge_level>←追加
#     <WNDSPD unit="mps">25</WNDSPD>←追加
#   </WIND_THRLD>←追加
#   </WNTR_ZONE>
# </list>

def load_pntfile(xmlfile)
  # 中区間に紐づく全要素
  points = {}
  # asmid代表地点逆引き
  asm_zone = {}
  # asm地点と日中夜間定義紐づけ
  asm_daynight = {}
  # 短期日中夜間全開始時刻
  srf_day_night = []
  # 中期日中夜間最早開始時刻
  mrf_day_night = [9,18]
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
  doc.elements.each('list/WNTR_ZONE'){|zone|
    z = zone.elements
    # RD_ZONE.xml
    zone_id = z['ZONE_ID'].text
    if points.has_key?(zone_id)
      print "ZONE_ID=%s duplicated.\n" % [zone_id]
    end
    print "ZONE_ID=%s\n" % [zone_id]
    points[zone_id] = {}
    points[zone_id]["NAME"] = z['ZONE_NAME'].text
    asm_id_daihyo = z['ASM_ID_daihyo'].text.strip
    points[zone_id]["ASM_ID_daihyo"] = asm_id_daihyo
    if asm_zone[asm_id_daihyo] == nil
      asm_zone[asm_id_daihyo] = []
    end
    asm_zone[asm_id_daihyo].push(zone_id)
    asm_ids = Array.new
    if z['ASM_ID'].text != nil && z['ASM_ID'].text =~ /\d/
      asm_ids = z['ASM_ID'].text.split(",").map{|v| v.strip}
    end
    points[zone_id]["ASMID"] = asm_ids
    if z['SNWFLL_THRLD_10'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_10 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_10'].text != "-" && z['SNWFLL_THRLD_10'].text != nil)
      points[zone_id]["SCALE_SNWFLL_10"] = z['SNWFLL_THRLD_10'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_10"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_9'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_9 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_9'].text != "-" && z['SNWFLL_THRLD_9'].text != nil)
      points[zone_id]["SCALE_SNWFLL_9"] = z['SNWFLL_THRLD_9'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_9"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_8'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_8 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_8'].text != "-" && z['SNWFLL_THRLD_8'].text != nil)
      points[zone_id]["SCALE_SNWFLL_8"] = z['SNWFLL_THRLD_8'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_8"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_7'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_7 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_7'].text != "-" && z['SNWFLL_THRLD_7'].text != nil)
      points[zone_id]["SCALE_SNWFLL_7"] = z['SNWFLL_THRLD_7'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_7"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_6'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_6 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_6'].text != "-" && z['SNWFLL_THRLD_6'].text != nil)
      points[zone_id]["SCALE_SNWFLL_6"] = z['SNWFLL_THRLD_6'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_6"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_5'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_5 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_5'].text != "-" && z['SNWFLL_THRLD_5'].text != nil)
      points[zone_id]["SCALE_SNWFLL_5"] = z['SNWFLL_THRLD_5'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_5"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_4'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_4 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_4'].text != "-" && z['SNWFLL_THRLD_4'].text != nil)
      points[zone_id]["SCALE_SNWFLL_4"] = z['SNWFLL_THRLD_4'].text.to_f
    else      
      points[zone_id]["SCALE_SNWFLL_4"] = SNOW_RAIN_MAX
    end
    if z['SNWFLL_THRLD_3'] == nil
      raise "ZONE_ID=%s SNWFLL_THRLD_3 not exist\n" % [zone_id]
    end
    if(z['SNWFLL_THRLD_3'].text != "-" && z['SNWFLL_THRLD_3'].text != nil)
      points[zone_id]["SCALE_SNWFLL_3"] = z['SNWFLL_THRLD_3'].text.to_f
    else
      points[zone_id]["SCALE_SNWFLL_3"] = SNOW_RAIN_MAX
    end
    if z['AIRTMP_THRLD_2'] == nil
      raise "ZONE_ID=%s AIRTMP_THRLD_2 not exist\n" % [zone_id]
    end
    if(z['AIRTMP_THRLD_2'].text != "-" && z['AIRTMP_THRLD_2'].text != nil)
      points[zone_id]["SCALE_AIRTMP_2"] = z['AIRTMP_THRLD_2'].text.to_f
    else
      points[zone_id]["SCALE_AIRTMP_2"] = LACK_VALUE_16
    end
#    if(z['PRCRIN_THRLD_2'].text != "-" && z['PRCRIN_THRLD_2'].text != nil)
#      points[zone_id]["SCALE_PRCRIN_2"] = z['PRCRIN_THRLD_2'].text.to_f
#    else
#      points[zone_id]["SCALE_PRCRIN_2"] = SNOW_RAIN_MAX
#    end
    if z['RDTEMP_THRLD_2'] == nil
      raise "ZONE_ID=%s RDTEMP_THRLD_2 not exist\n" % [zone_id]
    end
    if(z['RDTEMP_THRLD_2'].text != "-" && z['RDTEMP_THRLD_2'].text != nil)
      points[zone_id]["SCALE_RDTEMP_2"] = z['RDTEMP_THRLD_2'].text.to_f
    else
      points[zone_id]["SCALE_RDTEMP_2"] = LACK_VALUE_16
    end
    if z['judge_pair_and'] == nil
      raise "ZONE_ID=%s judge_pair_and not exist\n" % [zone_id]
    end
    ja = z['judge_pair_and'].text
    judge_and = []
    for i in 0...ja.size
      judge_and.push(ja[i,1])
    end
    points[zone_id]["JUDGE_PAIR_AND"] = judge_and
    if z['judge_pair_or'] == nil
      raise "ZONE_ID=%s judge_pair_or not exist\n" % [zone_id]
    end
    jo = z['judge_pair_or'].text
    judge_or = []
    for i in 0...jo.size
      judge_or.push(jo[i,1])
    end
    points[zone_id]["JUDGE_PAIR_OR"]  = judge_or
    mrf_daynight = {}
    # 短期日中夜間
    if z["DAYTM_INT "] == nil
      print "ZONE_ID=%s SRF daynight not exist.\n" % [zone_id] if $verbose
      points[zone_id]["DAYTM"] = {
        "start" => 9,
        "end"   => 17
      }
      points[zone_id]["NIGHT"] = {
        "start" => 17,
        "end"   => 9
      }
    else
      points[zone_id]["DAYTM"] = {
        "start" => z["DAYTM_INT "].attributes["start"].to_i,
        "end"   => z["DAYTM_INT "].attributes["end"].to_i
      }
      points[zone_id]["NIGHT"] = {
        "start" => z["NIGHT_INT "].attributes["start"].to_i,
        "end"   => z["NIGHT_INT "].attributes["end"].to_i
      }
    end
    # 短期の日中夜間を3の倍数に
    dnst = points[zone_id]["DAYTM"]["end"]
    if points[zone_id]["DAYTM"]["end"] % 3 != 0
      dnst = dnst + 3 - points[zone_id]["DAYTM"]["end"] % 3
    end
    mrf_daynight["srf_day_end"] = dnst
    if srf_day_night.index(dnst) == nil
      srf_day_night.push(dnst)
    end
    dnst = points[zone_id]["NIGHT"]["end"]
    if points[zone_id]["NIGHT"]["end"] % 3 != 0
      dnst = dnst + 3 - points[zone_id]["NIGHT"]["end"] % 3
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
    # asm地点と日中夜間定義紐づけ
    asm_daynight[asm_id_daihyo] = mrf_daynight["DAYTM_MRF"]
    asm_daynight[asm_id_daihyo]["srf_day_end"] = mrf_daynight["srf_day_end"]
    asm_daynight[asm_id_daihyo]["srf_night_end"] = mrf_daynight["srf_night_end"]
    asm_daynight[asm_id_daihyo]["day_3h"] = ( mrf_daynight["DAYTM_MRF"]["end"] - mrf_daynight["DAYTM_MRF"]["start"]) / 3
    asm_daynight[asm_id_daihyo]["night_3h"] = ( 24 - asm_daynight[asm_id_daihyo]["day_3h"] * 3 ) / 3
    # 10V定義の最大値
    points[zone_id]["MAX_10V_DEF"] = LACK_VALUE_16
    if z['MAX_10V_DEF'] != nil && z['MAX_10V_DEF'].text
      value = z['MAX_10V_DEF'].text.strip
      if value  =~ /^(\d+)$/
        points[zone_id]["MAX_10V_DEF"] = $1.to_i
      end
    end
    # 10v7v変換テーブル
    conv_7v_10v = {}
    z.each("VSCAL/SCALE"){|scale_10v|
      if scale_10v.attributes["value"] == nil
        print "%s VSCAL has no attributes.\n" % [zone_id]
        next
      end
      value = scale_10v.attributes["value"].strip
      if value  =~ /^(\d+)$/
        n10v = value.to_i
        if scale_10v.text != nil
          ary7v = scale_10v.text.split(",")
          ary7v.each{|v|
            if conv_7v_10v[v.to_i] != nil
              print "%s 7v=%s %s %s\n" % [zone_id,v,n10v,conv_7v_10v[v.to_i]] if $verbose
            end
            conv_7v_10v[v.to_i] = n10v
          }
        end
      else
        print "%s VSCAL value=%s\n" % [zone_id,value] if $verbose
        next
      end
    }
    points[zone_id]["SCALE_10V_7V"] = conv_7v_10v
    # 10v無効水凍結スケール変換テーブル
    conv_rdicing_10v = {}
    z.each("NOPRFZ_VSCAL/SCALE"){|scale_10v|
      if scale_10v.attributes["value"] == nil
        print "%s NOPRFZ_VSCAL has no attributes.\n" % [zone_id]
        next
      end
      value = scale_10v.attributes["value"].strip
      if value  =~ /^(\d+)$/
        n10v = value.to_i
        if scale_10v.text != nil
          ary7v = scale_10v.text.split(",")
          ary7v.each{|v|
            if conv_rdicing_10v[v.to_i] != nil
              print "%s 7v=%s %s %s\n" % [zone_id,v,n10v,conv_rdicing_10v[v.to_i]] if $verbose
            end
            conv_rdicing_10v[v.to_i] = n10v
          }
        end
      else
        print "%s NOPRFZ_VSCAL value=%s\n" % [zone_id,value] if $verbose
        next
      end
    }
    points[zone_id]["SCALE_10V_RDICING"] = conv_rdicing_10v
    # 無降水凍結継続時間テーブル
    # 区間がテーブルに未登録、または、テーブルの連続判定を行う最小スケールが無効値の場合は、
    # 最小スケール=６、連続時間＝１０時間で連続判定を行う。
    points[zone_id]["RDICING_DURATION_HOUR"] = 10
    points[zone_id]["RDICING_DURATION_SCALE"] = 6
    if z['NOPRFZ_PRD'] != nil && z['NOPRFZ_PRD'].text
      hour = z['NOPRFZ_PRD'].text.strip.to_i
      if hour > 0 && hour < 100
        points[zone_id]["RDICING_DURATION_HOUR"] = hour
      else
        print "%s NOPRFZ_PRD=%s\n" % [zone_id,z['NOPRFZ_PRD'].text] if $verbose
      end
    end
    if z['NOPRFZ_SCALE_MINI'] != nil && z['NOPRFZ_SCALE_MINI'].text
      mscale = z['NOPRFZ_SCALE_MINI'].text.strip.to_i
      if mscale > 0
        points[zone_id]["RDICING_DURATION_SCALE"] = mscale
      else
        print "%s NOPRFZ_SCALE_MINI=%s\n" % [zone_id,z['NOPRFZ_SCALE_MINI'].text] if $verbose
      end
    end
    # しきい値（風）のデータのループ
    wind_level = {}
    z.each("WIND_THRLD"){|threshold_wind|
      tw = threshold_wind.elements
      if tw['judge_level'] != nil && tw['judge_level'].text != nil
        if tw['judge_level'].text.strip  =~ /^(\d+)$/
          judge_level = $1.to_i
          if wind_level[judge_level] != nil
            "ZONE_ID=%s WIND_THRLD judge_level=%s duplicated.\n" % [zone_id,judge_level]
          end
          if tw['WNDSPD'] != nil && tw['WNDSPD'].text != nil
            wndspd = tw['WNDSPD'].text.strip.to_i
            if wndspd > 0
              wind_level[judge_level] = wndspd
            else
              print "ZONE_ID=%s WIND_THRLD judge_level=%s WNDSPD=%s\n" % [zone_id,judge_level,wndspd]
            end
          else
            print "ZONE_ID=%s WIND_THRLD judge_level=%s WNDSPD not exist.\n" % [zone_id,judge_level]
          end
        else
          print "ZONE_ID=%s WIND_THRLD judge_level=%s\n" % [zone_id,tw['judge_level'].text] if $verbose
        end
      else
        print "ZONE_ID=%s WIND_THRLD judge_level not exist.\n" % [zone_id]
      end
    }
    points[zone_id]["threshold_wind"] = wind_level
  }
  # 中区間に紐づく全要素
  $save_data["zone_elements"] = points
  print "all zone count=%d\n" % [points.size]
  # asmid代表地点逆引き
  $save_data["asm_zone"] = asm_zone
  # asm地点と日中夜間定義紐づけ
  $save_data["asm_daynight"] = asm_daynight
  # 短期日中夜間全開始時刻
  $save_data["srf_day_night"] = srf_day_night
  # 中期日中夜間最早開始時刻
  $save_data["mrf_day_night"] = mrf_day_night
end

def main()
  if ARGV.size < 1
    print "Usage:#{__FILE__} <config>\n"
    return
  end
  $config = YAML.load_file(ARGV[0])
  pntfile = $config["spool_dir"] + $config["rd_table_winter"]
  if File.exist?(pntfile) == false
    print "xml file not exist %s\n" % $config["rd_table_winter"]
    return
  end
  load_pntfile(pntfile)
  dbdata = PStore.new($config["spool_dir"] + $config["rd_table_winter_spool"])
  dbdata.transaction() do
    dbdata['root'] =  $save_data
  end
  dbdata = PStore.new($config["dewtmp_zone_path"])
  dbdata.transaction() do
    dbdata['root'] =  $save_data["zone_elements"]
  end
end
print "timenow=%s\n" % Time.now.to_s
begin
  main()
rescue => e
  send_mail("Table winter update failure")
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
print "timenow=%s\n" % Time.now.to_s
