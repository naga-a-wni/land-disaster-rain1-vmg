# 日中夜間判定
def isdaynight(zone_id,ft)
  # RD_ZONE.xmlのDAY_DEFINE/NIGHT_DEFINEのstart/endはstartを含まずendを含む
  localhour = ft.localtime.hour
  daytm_start =  $zone_data[zone_id]["DAYTM"]["start"].to_i
  daytm_end =  $zone_data[zone_id]["DAYTM"]["end"].to_i
  night_start = $zone_data[zone_id]["NIGHT"]["start"].to_i
  night_end = $zone_data[zone_id]["NIGHT"]["end"].to_i
  if daytm_start < localhour && daytm_end >= localhour
#    $log.write( "isdaynight day zone_id=%s localhour=%s DAYTM start=%s end=%s NIGHT start=%s end=%s" % [zone_id,localhour,daytm_start,daytm_end,night_start,night_end] )
    return "day"
  end
  if night_start < localhour || night_end >= localhour
#    $log.write( "isdaynight night zone_id=%s localhour=%s DAYTM start=%s end=%s NIGHT start=%s end=%s" % [zone_id,localhour,daytm_start,daytm_end,night_start,night_end] )
    return "night"
  end
  $log.write( "isdaynight unkown zone_id=%s localhour=%s DAYTM start=%s end=%s NIGHT start=%s end=%s" % [zone_id,localhour,daytm_start,daytm_end,night_start,night_end] )
  return "day"
end

# 無降水凍結を計算して無降水スケールを算出
def calc_rd_freeze(zone_id,ft,rdt,dew)
  if rdt == LACK_VALUE_16 || dew == LACK_VALUE_16
    $log.write( "zone_id=%s dewtmp spool data not exist." % [zone_id] ) if $verbose
    return LACK_VALUE_16
  end
  # 6 警戒  路温0℃（0.4℃）以下、かつ、路温－露点温度0℃以下 
  # 5 注意  路温2℃（2.4℃）以下、かつ、路温－露点温度0℃以下 → 4
  # 4 結露有  路温3℃（2.5℃）以上、かつ、路温－露点温度0℃以下 → 2
  # 3 警戒  路温0℃（0.4℃）以下、かつ、路温－露点温度2℃以下   → 4 → 5
  # 2 注意  路温2℃（2.4℃）以下、かつ、路温－露点温度2℃以下   → 3
  # 1 結露有  路温3℃（2.5℃）以上、かつ、路温－露点温度2℃以下
  # 0 結露無  路温－露点温度2℃以上 
  s = 0
  dft = rdt - dew
  if(dft <= 0)
    if(rdt <= 0.45)
      s = 6
    elsif(rdt <= 2.45)
      s = 4 # 5
    else
      s = 2 # 4
    end
  elsif(dft <= 2)
    if(rdt <= 0.45)
      s = 5 # 3→4
    elsif(rdt <= 2.45)
      s = 3 # 2
    else
      s = 1
    end
  else
    s = 0
  end
  return s
end

# 無降水スケール連続スケール
def get_rd_freeze_renzoku_scale(zone_id,hourscale,rd_freeze_renzoku)
  # テーブルの連続時間が無効値、または１の場合は、
  # 「最大値スケール」はその日中／夜間の無降水スケールとする。
  tempscale = LACK_VALUE_8
  if $zone_data[zone_id]["RDICING_DURATION_HOUR"] > 1
    if hourscale >= $zone_data[zone_id]["RDICING_DURATION_SCALE"]
      $zone_data[zone_id]["RDICING_DURATION_SCALE"].upto(6){|i|
        if rd_freeze_renzoku[i] == nil
          rd_freeze_renzoku[i] = 0
        end
        if i <= hourscale
         rd_freeze_renzoku[i] += 1
         if rd_freeze_renzoku[i] >= $zone_data[zone_id]["RDICING_DURATION_HOUR"]
           tempscale = i
         end
        else
         rd_freeze_renzoku[i] = 0
        end
      }
    else
      $zone_data[zone_id]["RDICING_DURATION_SCALE"].upto(6){|i|
        rd_freeze_renzoku[i] = 0
      }
    end
  end
  return tempscale
end

# 日中帯、夜間帯、それぞれの期間の降水量（0mm以上＠天気テロップで雨が1コマ以上）及び最低気温/最低路温が閾値以下の場合
def get_prec_and_temp_and_rtmp_rank(zoneid, rd_zone, temp, rtmp, raint, prec0)
  rank = 1
  temp = temp + 0.01 if temp < 0
  rtmp = rtmp + 0.01 if rtmp < 0
  temp = (temp * 10).round
  rtmp = (rtmp * 10).round
  if raint > 0 && prec0 > 0 && temp <= (rd_zone["SCALE_AIRTMP_2"] * 10).round && rtmp <= (rd_zone["SCALE_RDTEMP_2"] * 10).round
#    print "TRH %s,%s,%s,%s,%s,%s,%s\n" % [zoneid, temp.to_s, rtmp.to_s, raint.to_s, prec0.to_s, rd_zone["SCALE_AIRTMP_2"].to_s, rd_zone["SCALE_RDTEMP_2"].to_s]
    rank = 2
  end
  return rank
end

def get_prec_and_temp_rank(zoneid, rd_zone, temp, raint, prec0)
  rank = 1
  temp = temp + 0.01 if temp < 0
  temp = (temp * 10).round
  if raint > 0 && prec0 > 0 && temp <= (rd_zone["SCALE_AIRTMP_2"] * 10).round
#    print "TR %s,%s,%s,%s,%s\n" % [zoneid, temp.to_s, raint.to_s, prec0.to_s, rd_zone["SCALE_AIRTMP_2"].to_s]
    rank = 2
  end
  return rank
end

def get_temp_rank(rd_zone, temp)
  rank = 1
  temp = temp + 0.01 if temp < 0
  temp = (temp * 10).round
  if(temp <=  rd_zone["SCALE_AIRTMP_2"] * 10)
    rank = 2
  end
  return rank
end

def get_prec_and_rtmp_rank(zoneid, rd_zone, rtmp, raint, prec0)
  rank = 1
  rtmp = rtmp + 0.01 if rtmp < 0
  rtmp = (rtmp * 10).round
  if raint > 0 && prec0 > 0 && rtmp <= (rd_zone["SCALE_RDTEMP_2"] * 10).round
#    print "RH %s,%s,%s,%s,%s\n" % [zoneid, rtmp.to_s, raint.to_s, prec0.to_s, rd_zone["SCALE_RDTEMP_2"].to_s]
    rank = 2
  end
  return rank
end

def get_rtmp_rank(rd_zone, rtmp)
  rank = 1
  rtmp = rtmp + 0.01 if rtmp < 0
  rtmp = (rtmp * 10).round
  if rtmp <=  (rd_zone["SCALE_RDTEMP_2"] * 10).round
    rank = 2
  end
  return rank
end

def get_snow_rank(rd_zone, snow, snow0)
  rank = 1
  if(snow > 0.0 || snow0 > 0)
    if(snow >= rd_zone["SCALE_SNWFLL_10"])
      rank = 10
    elsif(snow >= rd_zone["SCALE_SNWFLL_9"])
      rank = 9
    elsif(snow >= rd_zone["SCALE_SNWFLL_8"])
      rank = 8
    elsif(snow >= rd_zone["SCALE_SNWFLL_7"])
      rank = 7
    elsif(snow >= rd_zone["SCALE_SNWFLL_6"])
      rank = 6
    elsif(snow >= rd_zone["SCALE_SNWFLL_5"])
      rank = 5
    elsif(snow >= rd_zone["SCALE_SNWFLL_4"])
      rank = 4
    elsif(snow >= rd_zone["SCALE_SNWFLL_3"])
      rank = 3
    end
#    if rank < 3 && snow == 0.0 && snow0 > 0
#      # 0雪
#      rank = 3
#    end
  end
  return rank
end

# 7v スケール計算
def get_7v_scale(daynight,zoneid)
  prcrin = daynight["PRCRIN_TOTAL"]
  airtmp = daynight["AIRTMP_MIN"]
  rdtemp = daynight["RDTMP_MIN"]
  raint =  daynight["RAIN_TELOP"]
  prec0 =  daynight["RAIN_HOURS"]
  snow0 =  daynight["SNOW_HOURS"]
  snwfll = daynight["SNWFLL_TOTAL"]["raw"]
  freeze_rank = -1
  zonedata = $zone_data[zoneid]
  if zonedata == nil
    return freeze_rank
  end
  if airtmp == nil || rdtemp == nil
    return freeze_rank
  end
  judge_and = zonedata['JUDGE_PAIR_AND']
  if(judge_and.include?("T") && judge_and.include?("R") &&
     judge_and.include?("H"))
    freeze_rank = get_prec_and_temp_and_rtmp_rank(zoneid, zonedata, airtmp, rdtemp, raint, prec0)
  elsif(judge_and.include?("T") && judge_and.include?("R"))
    freeze_rank = get_prec_and_temp_rank(zoneid, zonedata, airtmp, raint, prec0)
  elsif(judge_and.include?("R") && judge_and.include?("H"))
    freeze_rank = get_prec_and_rtmp_rank(zoneid, zonedata, rdtemp, raint, prec0)
  elsif(judge_and.include?("T"))
    freeze_rank = get_temp_rank(zonedata, airtmp)
  else
    $log.write( "zone_id=%s judge not found." % [zoneid] ) if $verbose
  end
  judge_or = zonedata['JUDGE_PAIR_OR']
  if(judge_or.include?("R") && judge_or.include?("H"))
    rtmp_rank = 1
    rtmp_rank = get_prec_and_rtmp_rank(zoneid, zonedata, rdtemp, raint, prec0)
    freeze_rank = rtmp_rank if(freeze_rank < rtmp_rank)
  elsif(judge_or.include?("H"))
    rtmp_rank = 1
    rtmp_rank = get_rtmp_rank(zonedata, rdtemp) if(rdtemp != LACK_VALUE_16)
    freeze_rank = rtmp_rank if(freeze_rank < rtmp_rank)
  end
  snow_rank = get_snow_rank(zonedata, snwfll, snow0)
  rank = freeze_rank
  rank = snow_rank if(rank < snow_rank)
  return rank
end

# 7vスケールと無降水凍結スケールを10vに変換して比較
# 大きい方を返す
def sevenv2tenv(rank, zoneid, rd_freeze_scale, term, prec0)
  zonedata = $zone_data[zoneid]
  # 7v10変換
  table = zonedata["SCALE_10V_7V"]
  scale10v = 0
  if table != nil && table[rank] != nil
    scale10v = table[rank]
  end
  # 無降水凍結スケール10変換
  mukousui_scale10v = 0
  if term == "day" || prec0 <= 0
    table = zonedata["SCALE_10V_RDICING"]
    if table != nil && table[rd_freeze_scale] != nil
      mukousui_scale10v = table[rd_freeze_scale]
    end
  end
  if scale10v < mukousui_scale10v
    print "mukousui 10v scale is bigger than 7v-10v scale.\n" if $verbose
    print "zoneid=%s term=%s 7v-10v scale=%d mukousui 10v scale=%d.\n" % [ zoneid, term, scale10v, mukousui_scale10v ] if $verbose
    scale10v = mukousui_scale10v
  end
  return scale10v
end

def dew_file_available(fname)
  if File.exist?(fname)
    s = File::stat(fname)
      if s.size > 0
        return true
      end
      return false
  end
  return false
end
