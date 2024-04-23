#
# 要素間整合
# input  :  降雪量生値、降雪量出力値、気温、路面温度、天気
# output : 
#
# 100 晴
# 200 曇
# 300 雨
# 400 雪
# 430 みぞれ
# 500 快晴
# 600 薄曇り
#
def adjust_elements(t, snwfll_raw, refw_fcst)
  # みぞれの場合に対して修正される量
  if refw_fcst[t]["WX"] == 430
    if refw_fcst[t]["AIRTMP"] >= 3.45
      # 気温3.5℃以上 →3℃へ0.5℃未満 →1℃へその他は、そのまま
      refw_fcst[t]["AIRTMP"] = 3.0
    elsif refw_fcst[t]["AIRTMP"] < 0.45 && refw_fcst[t]["AIRTMP"] > LACK_VALUE_16
      refw_fcst[t]["AIRTMP"] = 1.0
    end
    if refw_fcst[t]["RDTMP"] >= 4.45
      # 路温路面温度が4.5℃以上→5℃路面温度が4.5℃未満→そのまま
      refw_fcst[t]["RDTMP"] = 5.0
    end
  elsif refw_fcst[t]["WX"] == 400
    # 雪の場合に降雪量に対して修正される量
    if snwfll_raw >= 0 && snwfll_raw < 0.5
      # 降雪量 0cm/h以上、0.5cm/h未満
      if refw_fcst[t]["AIRTMP"] >= 1.45
        # 気温1.5℃以上→2℃へ1.5℃未満→そのまま
        refw_fcst[t]["AIRTMP"] = 2.0
      end
      if refw_fcst[t]["RDTMP"] >= 4.45
        # 路温4.5℃以上→5℃ 4.5℃未満→そのまま
        refw_fcst[t]["RDTMP"] = 5.0
      end
    elsif snwfll_raw >= 0.5 && snwfll_raw < 1.5
      # 降雪量 0.5cm/h以上、1.5cm/h未満
      if refw_fcst[t]["AIRTMP"] >= 0.45
        # 気温0.5℃以上→1℃へ0.5℃未満→そのまま
        refw_fcst[t]["AIRTMP"] = 1.0
      end
      if refw_fcst[t]["RDTMP"] >= 0.45
        # 路温0.5℃以上→1℃ 0.5℃未満→そのまま
        refw_fcst[t]["RDTMP"] = 1.0
      end
    elsif snwfll_raw >= 1.5
      # 降雪量 1.5cm/h以上
      if refw_fcst[t]["AIRTMP"] >= 0
        # 気温0℃以上→0℃へ0℃未満→そのまま
        refw_fcst[t]["AIRTMP"] = 0
      end
      if refw_fcst[t]["RDTMP"] >= 0
        # 路温0℃以上→0℃ 0℃未満→そのまま
        refw_fcst[t]["RDTMP"] = 0
      end
    end
  end
  # 上記、降雪量/天気みぞれの場合の気温/路温の関係を修正したのち「雪水比」(3通りに固定)を基に降水量を調整
  # 要素間整合前の四捨五入問題による降雪量調整に対しての降水量調整処理
  # この処理は天気テロップが雪の場合のみ適用する 20220113
  if refw_fcst[t]["WX"] == 400 && refw_fcst[t]["PRCRIN_1HOUR_TOTAL"] >= 0 && refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] >= 0
    # 雪水比（cm/mm）
    srr = 0
    if refw_fcst[t]["PRCRIN_1HOUR_TOTAL"] > 0
      srr = refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] / refw_fcst[t]["PRCRIN_1HOUR_TOTAL"]
    end
    if refw_fcst[t]["AIRTMP"] < -0.55 && refw_fcst[t]["AIRTMP"] > LACK_VALUE_16
      if srr >= 1.0 && srr <= 2.0
        $log.write("srr >= 1.0 && srr <= 2.0") if $verbose
      else
        # 気温 < -0.5 ℃          →  降水量[mm/h]= 四捨五入された整数値の降雪量(cm/h)/1.5
        refw_fcst[t]["PRCRIN_1HOUR_TOTAL"] = (refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] / 1.5).round
      end
    elsif -0.55 <= refw_fcst[t]["AIRTMP"] && refw_fcst[t]["AIRTMP"] < 0.45
      if srr >= 0.6 && srr <= 1.5
        $log.write("srr >= 0.6 && srr <= 1.5") if $verbose
      else
        # -0.5℃ <= 気温 <0.5℃   →  降水量[mm/h]= 四捨五入された整数値の降雪量(cm/h)/1
        refw_fcst[t]["PRCRIN_1HOUR_TOTAL"] = refw_fcst[t]["SNWFLL_1HOUR_TOTAL"]
      end
    elsif 0.45 <= refw_fcst[t]["AIRTMP"]
      if srr >= 0.3 && srr <= 1.0
        $log.write("srr >= 0.3 && srr <= 1.0") if $verbose
      else
        # 0.5℃=  < 気温        →  降水量[mm/h]= 四捨五入された整数値の降雪量(cm/h)/0.5
        refw_fcst[t]["PRCRIN_1HOUR_TOTAL"] = (refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] / 0.5).round
      end
    end
  end
end

#
# 風10Vスケール判定
#
def get_scale_wind(table_ref,wndspd)
  scale = 0
  if table_ref == nil || table_ref.size < 1
    return scale
  end
  wndspd = wndspd.round
  judge_level = table_ref.keys.sort
  judge_level.each{|level|
    if table_ref[level] <= wndspd
      scale = level
    end
  }
  return scale
end


#
# 要素間整合を行い、気温路温に変化があったかのフラグを返す
#
def adjust_elements_and_check_tmp(t, snwfll_raw, refw_fcst)
  # 要素間整合前の気温路温
  airtmp_org = refw_fcst[t]["AIRTMP"]
  rdtmp_org = refw_fcst[t]["RDTMP"]
  # 要素間整合
  adjust_elements(t, snwfll_raw, refw_fcst)
  # 要素間整合後の気温路温
  airtmp_new = refw_fcst[t]["AIRTMP"]
  rdtmp_new = refw_fcst[t]["RDTMP"]
  return airtmp_org != airtmp_new, rdtmp_org != rdtmp_new     
end
