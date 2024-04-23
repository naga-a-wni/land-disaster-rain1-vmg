#
# 気温/路温スムージング処理 
# input  :  予測列、fcst_count, 固定AIRTMP ft列, 固定RDTMP ft列
# output : 
#
# 温度列の最初と最後は対象外
# 固定ft列に含まれるftは固定
#
#

def smoothing_tmp(fcsts, fcst_count, fix_airtmp_fts, fix_rdtmp_fts)
  # fcsts: refw["ZONE_data"][zone_area_ount]["FCAS"])
  # スムージング前の値をとっておく
  org_airtmp = [] 
  org_rdtmp = [] 
  for j in 0...fcst_count
    org_airtmp.push(fcsts[j]["AIRTMP"])
    org_rdtmp.push(fcsts[j]["RDTMP"])
  end

  for k in 1...fcst_count-1
    ft = fcsts[k]["FCASD"].get_value_time
    # 固定ftはそのまま
    if ! fix_airtmp_fts.include?(ft)
      fcsts[k]["AIRTMP"] = calc_avg(org_airtmp, k)
    end
    if ! fix_rdtmp_fts.include?(ft)
      fcsts[k]["RDTMP"] = calc_avg(org_rdtmp, k)
    end
  end
end

def calc_avg(org_values, k)
  prev_value = org_values[k-1]
  now_value = org_values[k]
  next_value = org_values[k+1]
  # 欠測含みはそのまま
  if prev_value == LACK_VALUE_16 || now_value == LACK_VALUE_16 || next_value == LACK_VALUE_16
    return now_value
  end
  return (prev_value + now_value + next_value)/3.0
end
