# 中区間小区間最大スケール
# max_scale[ft][zid][szid]["rain"]
#                         ["wind"]
#                         ["flag"]
#                         ["flag2"]
def get_max_scale(max_scale,ft,zone_id,small_zone,rain,wind,flag,flag2)
  if max_scale[ft] == nil
    max_scale[ft] = {}
  end
  if max_scale[ft][zone_id] == nil
    max_scale[ft][zone_id] = {}
  end
  if max_scale[ft][zone_id][small_zone] == nil
    max_scale[ft][zone_id][small_zone] = {}
  end
  if max_scale[ft][zone_id][small_zone]["rain"] == nil || max_scale[ft][zone_id][small_zone]["rain"] < rain
    max_scale[ft][zone_id][small_zone]["rain"] = rain
    max_scale[ft][zone_id][small_zone]["flag"] = flag
    max_scale[ft][zone_id][small_zone]["flag2"] = flag2
  end
  if max_scale[ft][zone_id][small_zone]["wind"] == nil || max_scale[ft][zone_id][small_zone]["wind"] < wind
    max_scale[ft][zone_id][small_zone]["wind"] = wind
  end
end

def set_max_scale(refw,max_scale)
  zone_count = refw["ZONE_count"]
  for i in 0...zone_count
    zone_id = refw["ZONE_data"][i]["ZONE"]
    ft_count = refw["ZONE_data"][i]["FT"]
    for j in 0...ft_count
      fcasd = refw["ZONE_data"][i]["FCAS"][j]["FCASD"].get_value_time
#      fcasd = refw["ZONE_data"][i]["FCAS"][j]["FCASD"]
      if max_scale[fcasd] != nil && max_scale[fcasd][zone_id] != nil
        max_scale[fcasd][zone_id].each_pair{|sz,szval|
          if refw["ZONE_data"][i]["FCAS"][j]["RAIN_VSCAL"] < szval["rain"]
            refw["ZONE_data"][i]["FCAS"][j]["RAIN_VSCAL"] = szval["rain"]
          end
          if refw["ZONE_data"][i]["FCAS"][j]["WIND_VSCAL"] < szval["wind"]
            refw["ZONE_data"][i]["FCAS"][j]["WIND_VSCAL"] = szval["wind"]
          end
        }
      end
    end
    small_zone_count = refw["ZONE_data"][i]["small_ZONE_count"]
    for j in 0...small_zone_count
      small_zone = refw["ZONE_data"][i]["small_ZONE_data"][j]["small_ZONE"]
      ft_count = refw["ZONE_data"][i]["small_ZONE_data"][j]["FT"]
      for k in 0...ft_count
        fcasd = refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["FCASD"].get_value_time
#        fcasd = refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["FCASD"]
        if max_scale[fcasd] != nil && max_scale[fcasd][zone_id] != nil && max_scale[fcasd][zone_id][small_zone] != nil
          refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["RAIN_VSCAL"] = max_scale[fcasd][zone_id][small_zone]["rain"]
          refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["second_flag"] = max_scale[fcasd][zone_id][small_zone]["flag"]
          if refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k].has_member?("use_second")
            refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["use_second"] = max_scale[fcasd][zone_id][small_zone]["flag2"]
          end
          refw["ZONE_data"][i]["small_ZONE_data"][j]["FCAS"][k]["WIND_VSCAL"] = max_scale[fcasd][zone_id][small_zone]["wind"]
        end
      end
    end
  end
end

#
# 雨10Vスケール判定
#
def get_rain_scale(table_ref,prcrin_1hour_total,prcrin_prst,second_flag)
  scale = 0
  if table_ref == nil || table_ref.size < 1
    return scale
  end
  judge_level = table_ref.keys.sort
  judge_level.each{|level|
    if second_flag == 1  # 第２通行止め
      if level == $config["road_closed_level"][0] || level == $config["road_closed_level"][1]
        next
      end
    else
      if level == $config["road_closed_level"][2] || level == $config["road_closed_level"][3]
        next
      end
    end
    option = table_ref[level]["option"]
    # 時間雨量・連続雨量のAND/OR 0：なし 1：AND 2：OR
    judge_and = false
    # 時間雨量のしきい値
    if table_ref[level]["PRCRIN_1hour"] != nil 
      if table_ref[level]["PRCRIN_1hour"] <= prcrin_1hour_total
        if option == 1
          judge_and = true
        else
          scale = level
          next
        end
      else
        if option == 1
          next
        end
      end
    end
    # 連続雨量のしきい値
    if table_ref[level]["PRCRIN_prst"] != nil
      prcrin_prst_threshold = table_ref[level]["PRCRIN_prst"]
      if prcrin_prst_threshold <= prcrin_prst
        if option == 1
          judge_and = true
        else
          scale = level
          next
        end
      else
        if option == 1
          next
        end
      end
    end
    if judge_and
      scale = level
    end
  }
  return scale
end

# 最新レベル3超過時刻更新
# [ZONE_ID][SMALL_ZONE_ID][RAIN_POINT_ID]["latest"] = time
def is_level3(scale, zone_id, small_zone, rain_point, ft)
  if scale >= $config["road_closed_level"][0]
    if $level3_time_list == nil
      $level3_time_list = {}
    end
    if $level3_time_list[zone_id] == nil
      $level3_time_list[zone_id] = {}
    end
    if $level3_time_list[zone_id][small_zone] == nil
      $level3_time_list[zone_id][small_zone] = {}
    end
    if $level3_time_list[zone_id][small_zone][rain_point] == nil
      $level3_time_list[zone_id][small_zone][rain_point] = {}
    end
    $level3_time_list[zone_id][small_zone][rain_point]["latest"] = ft
    $log.write("latest level=%s %s %s" % [scale,rain_point,ft.to_s])
  end
end

# 積算中の連続雨量が時雨量が対象閾値を超えたか
def is_over_60min_thd(point_data,otime)
  starttime = nil
  if point_data["StartTime"] != nil
    starttime = point_data["StartTime"]
  else
    if point_data["ResetStart"] != nil
      starttime = point_data["ResetStart"]
    else
      return false
    end
  end
  secondtime = nil
  if otime
    if point_data["prv_second"] != nil
      secondtime = point_data["prv_second"]
    else
      return false
    end
  else
    if point_data["SecondTime"] != nil
      secondtime = point_data["SecondTime"]
    else
      return false
    end
  end
  if starttime <= secondtime
    return true
  end
  return false
end

def set_apply_time(zid,sid,rid,btime,vdata,rdata)
  begin
    if $level3_time_list[zid][sid][rid] == nil
      return nil
    end
  rescue
    return nil
  end
  #
  # 判定A 連続雨量リセットのタイミングで行う 観測局毎適用期間開始時刻
  #
  if vdata["ResetTime"] != nil && vdata["ResetTime"] > btime - 3600 && vdata["ResetTime"] <= btime
    # 観測時刻で連続雨量がリセットされた リセットカウンタが5になった次のコマ
    if $level3_time_list[zid][sid][rid]["latest"] != nil
      # リセットされた連続雨量がlevel3を超えた
      $level3_time_list[zid][sid][rid]["apply"] = btime  # 観測局毎適用期間開始時刻
      if $level3_time_list[zid][sid][rid]["list"] == nil
        $level3_time_list[zid][sid][rid]["list"] = []
      end
      $level3_time_list[zid][sid][rid]["list"].push(btime)
      $level3_time_list[zid][sid][rid].delete("latest")  # 最新レベル3超過時刻更新をリセット
      $log.write("over level3 %s reset=%s" % [rid,$level3_time_list[zid][sid][rid]["apply"].to_s])
    end
  end
  #
  # 観測局毎適用期間開始時刻リセット判定 毎回行う
  #
  if $level3_time_list[zid][sid][rid]["apply"] != nil && btime > $level3_time_list[zid][sid][rid]["apply"] + 3600 * 24
    if rdata["PRCRIN_PRST"] > 0
      # 連続雨量積算中
      if !is_over_60min_thd(vdata,true)
        # 積算中の連続雨量の時雨量が対象閾値を超えていない
        # 観測局毎適用期間開始時刻をリセット
        $level3_time_list[zid][sid][rid].delete("apply")
      end
    else
      # 連続雨量積算中でない
      # 観測局毎適用期間開始時刻をリセット
      $level3_time_list[zid][sid][rid].delete("apply")
    end
  end
  if $level3_time_list[zid][sid][rid]["apply"] != nil
    $log.write("use_second=1 by own %s,%s" % [rid,btime.to_s])
    return $level3_time_list[zid][sid][rid]["apply"]
  end
  return nil
end

def start_before_apply(point_data,apply_latest)
  starttime = nil
  if point_data["StartTime"] != nil
    starttime = point_data["StartTime"]
  else
    if point_data["ResetStart"] != nil
      starttime = point_data["ResetStart"]
    else
      return false
    end
  end
  if starttime < apply_latest
    return true
  end
  return false
end

#
# 新第２通行止め
#
def road_close_2(refw_smallz,small_zone_save,max_scale,fcst_count,point_count,zone_id,small_zone)
  if small_zone_save == nil
    return
  end
  for sj in 0...fcst_count  # FTループ
    apply_latest = nil  # 最新観測局毎適用期間開始時刻
    for si in 0...point_count  # 雨量局ループ1
      rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
      if  small_zone_save[rid] == nil
        next
      end
      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
      apply_time = set_apply_time(zone_id,small_zone,rid,ft,small_zone_save[rid][ft],refw_smallz["point_data"][si]["FCAS"][sj])
      if apply_time != nil
        refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
        if apply_latest == nil || apply_latest < apply_time
          apply_latest = apply_time
        end
      end
    end  # 雨量局ループ1
    if apply_latest != nil
      #
      # 判定B 観測局毎適用期間フラグの設定
      #
      for si in 0...point_count  # 雨量局ループ2
        rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
        if  small_zone_save[rid] == nil
          next
        end
        ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#        ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
        if refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] == 0
          # 2.自観測局の「観測局毎適用期間開始時刻」がリセット中の場合
          # 2-2.同一降雨規制区間内の他の観測局に「観測局毎適用期間開始時刻」が設定中の観測局が存在する場合
          if refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"] <= 0
            # 2-2-1.連続雨量リセット中
            # フラグをON
            refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
            $log.write("use_second=1 by other %s,%s" % [rid,ft.to_s])
          else
            # 2-2-2.連続雨量継続中
            if start_before_apply(small_zone_save[rid][ft],apply_latest)
              # 2-2-2-1.設定中の「観測局毎適用期間開始時刻」のいずれかより前に連続雨量積算が開始している。
              $log.write("use_second=0 by other %s,%s" % [rid,ft.to_s])
            else
              # 2-2-2-2.設定中の「観測局毎適用期間開始時刻」のいずれか以後に連続雨量積算が開始している。
              # フラグをON
              $log.write("use_second=1 by other %s,%s" % [rid,ft.to_s])
              refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
            end
          end
        end
        #
        # 判定C 観測局毎対象期間フラグの設定
        #
        if refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] == 1 && refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"] > 0
          # 観測局毎適用期間フラグがON かつ 連続雨量積算中
          $log.write("use_second=1 %s,%s" % [rid,ft.to_s])
          if is_over_60min_thd(small_zone_save[rid][ft],false)
            refw_smallz["point_data"][si]["FCAS"][sj]["second_flag"] = 1
            $log.write("second_flag=1")
          end
        end
      end  # 観測局ループ2
    end
    for si in 0...point_count  # 雨量局ループ3
      rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
      if  small_zone_save[rid] == nil
        next
      end
      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
      flag = refw_smallz["point_data"][si]["FCAS"][sj]["second_flag"]
      flag2 = refw_smallz["point_data"][si]["FCAS"][sj]["use_second"]
      table_rain_point = $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"][rid]
      prcrin_1hour_total = refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_1HOUR_TOTAL"]
      prcrin_prst = refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"]
      scale = get_rain_scale(table_rain_point["threshold_rain"],prcrin_1hour_total,prcrin_prst,flag)
      refw_smallz["point_data"][si]["FCAS"][sj]["RAIN_VSCAL"] = scale
      # 最新レベル3超過時刻更新
      is_level3(scale, zone_id, small_zone, rid, ft)
      # 中区間小区間最大スケール
      if max_scale != nil
        wind_vscal = refw_smallz["point_data"][si]["FCAS"][sj]["WIND_VSCAL"]
        get_max_scale(max_scale,ft,zone_id,small_zone,scale,wind_vscal,flag,flag2)
      end
    end  # 雨量局ループ3
  end  # FTループ
end

#
# 新第２通行止め
#
def road_close_2_2(refw_smallz,small_zone_save,max_scale,fcst_count,point_count,zone_id,small_zone,obs_rain_scale)
  if small_zone_save == nil
    return
  end
  for sj in 0...fcst_count  # FTループ
    apply_latest = nil  # 最新観測局毎適用期間開始時刻
    for si in 0...point_count  # 雨量局ループ1
      rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
      if  small_zone_save[rid] == nil
        next
      end
      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
      if small_zone_save[rid][ft]["obs_flag"]
        next
      end
      apply_time = set_apply_time(zone_id,small_zone,rid,ft,small_zone_save[rid][ft],refw_smallz["point_data"][si]["FCAS"][sj])
      if apply_time != nil
        refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
        if apply_latest == nil || apply_latest < apply_time
          apply_latest = apply_time
        end
      end
    end  # 雨量局ループ1
    if apply_latest != nil
      #
      # 判定B 観測局毎適用期間フラグの設定
      #
      for si in 0...point_count  # 雨量局ループ2
        rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
        if  small_zone_save[rid] == nil
          next
        end
        ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#        ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
        if small_zone_save[rid][ft]["obs_flag"]
          next
        end
        if refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] == 0
          # 2.自観測局の「観測局毎適用期間開始時刻」がリセット中の場合
          # 2-2.同一降雨規制区間内の他の観測局に「観測局毎適用期間開始時刻」が設定中の観測局が存在する場合
          if refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"] <= 0
            # 2-2-1.連続雨量リセット中
            # フラグをON
            refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
            $log.write("use_second=1 by other %s,%s" % [rid,ft.to_s])
          else
            # 2-2-2.連続雨量継続中
            if start_before_apply(small_zone_save[rid][ft],apply_latest)
              # 2-2-2-1.設定中の「観測局毎適用期間開始時刻」のいずれかより前に連続雨量積算が開始している。
              $log.write("use_second=0 by other %s,%s" % [rid,ft.to_s])
            else
              # 2-2-2-2.設定中の「観測局毎適用期間開始時刻」のいずれか以後に連続雨量積算が開始している。
              # フラグをON
              $log.write("use_second=1 by other %s,%s" % [rid,ft.to_s])
              refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = 1
            end
          end
        end
        #
        # 判定C 観測局毎対象期間フラグの設定
        #
        if refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] == 1 && refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"] > 0
          # 観測局毎適用期間フラグがON かつ 連続雨量積算中
          $log.write("use_second=1 %s,%s" % [rid,ft.to_s])
          if is_over_60min_thd(small_zone_save[rid][ft],false)
            refw_smallz["point_data"][si]["FCAS"][sj]["second_flag"] = 1
            $log.write("second_flag=1")
          end
        end
      end  # 雨量局ループ2
    end
    for si in 0...point_count  # 雨量局ループ3
      rid = refw_smallz["point_data"][si]["RAIN_POINT_ID"]
      if  small_zone_save[rid] == nil
        next
      end
      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"].get_value_time
#      ft = refw_smallz["point_data"][si]["FCAS"][sj]["FCASD"]
      flag = 0
      flag2 = 0
      scale = 0
      if small_zone_save[rid][ft]["obs_flag"]
        if obs_rain_scale[ft] != nil && obs_rain_scale[ft][rid] != nil
          flag = obs_rain_scale[ft][rid]["second_flg"]  # 第２通行止め基準対象期間【0,1】
          flag2 = obs_rain_scale[ft][rid]["use_second"] # 第２通行止め基準適用期間【0,1】
          scale = obs_rain_scale[ft][rid]["rain_scale"] # 10V_雨 整数値
        end
        refw_smallz["point_data"][si]["FCAS"][sj]["second_flag"] = flag
        refw_smallz["point_data"][si]["FCAS"][sj]["use_second"] = flag2
        refw_smallz["point_data"][si]["FCAS"][sj]["RAIN_VSCAL"] = scale
      else
        flag = refw_smallz["point_data"][si]["FCAS"][sj]["second_flag"]
        flag2 = refw_smallz["point_data"][si]["FCAS"][sj]["use_second"]
        table_rain_point = $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"][rid]
        prcrin_1hour_total = refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_1HOUR_TOTAL"]
        prcrin_prst = refw_smallz["point_data"][si]["FCAS"][sj]["PRCRIN_PRST"]
        scale = get_rain_scale(table_rain_point["threshold_rain"],prcrin_1hour_total,prcrin_prst,flag)
        refw_smallz["point_data"][si]["FCAS"][sj]["RAIN_VSCAL"] = scale
        # 最新レベル3超過時刻更新
        is_level3(scale, zone_id, small_zone, rid, ft)
      end
      # 中区間小区間最大スケール
      if max_scale != nil
        wind_vscal = refw_smallz["point_data"][si]["FCAS"][sj]["WIND_VSCAL"]
        get_max_scale(max_scale,ft,zone_id,small_zone,scale,wind_vscal,flag,flag2)
      end
    end  # 雨量局ループ3
  end  # FTループ
end
