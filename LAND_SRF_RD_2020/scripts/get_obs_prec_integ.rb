# 連続雨量
def get_obs_prec_integ(end_time,just_time,announcetime,mk2_point_list)
  # 取得開始時刻 = 取得終了時刻 - 連続雨量リセット時間の最大値
  start_time = end_time - 3600 * $rd_table_summer["max_reseet_hour"]
  if announcetime - 3600 < start_time
    # 発表時刻が取得開始時刻より小さい場合は発表時刻が取得開始時刻
    start_time = announcetime - 3600
  end
  if end_time > announcetime + 3600 * 96
    # 過去データ
    end_time = announcetime + 3600 * 96
  end
  $log.write("obs_prec_integ start_time=%s end_time=%s" % [start_time.to_s,end_time.to_s])
  obs_prec_integ = {}
  mkConn = MkConnection.new( $host, $port)
  time_list = mkConn.get_time_list($config["mk2_prec_table"], start_time, end_time)
  params = []
  $log.write("obs_prec_integ just_time=%s" % [just_time.to_s])
  time_list.each{|btime|
    if btime > just_time - 3600
      # 現在時刻の正時の１時間前以降は全部取得
      params.push(MkDataParam.new(0, '0', btime))
    else
      if btime.to_i % 3600 == 0
      # 現在時刻の正時以前は正時のみ取得
        params.push(MkDataParam.new(0, '0', btime))
      end
    end
  }
  if params.size > 0
    $log.write("obs_prec_integ read start.")
    element_list = [ 'StartTime:INT32','IntegratedPrecipitation:INT32','Precipitation:INT32','UpdateTime:INT32','ResetTime:INT32','ResetStart:INT32','SecondTime:INT32' ]
    pd = mkConn.read_point($config["mk2_prec_table"], params, mk2_point_list, element_list)
    params.each{|prm|
      obs_prec_integ[prm.time] = {}
      starttime = pd.get_data(prm, 'StartTime')
      presetdata = pd.get_data(prm, 'IntegratedPrecipitation')
      p60data = pd.get_data(prm, 'Precipitation')
      updatetime = pd.get_data(prm, 'UpdateTime')  # 第２通行止め
      resettime = pd.get_data(prm, 'ResetTime')    # 第２通行止め
      resetstart = pd.get_data(prm, 'ResetStart')  # 第２通行止め
      secondtime = pd.get_data(prm, 'SecondTime')  # 新第２
      mk2_point_list.each_index{|i|
        obs_prec_integ[prm.time][mk2_point_list[i].id] = {}
        obs_prec_integ[prm.time][mk2_point_list[i].id]["StartTime"] = starttime[i]
        obs_prec_integ[prm.time][mk2_point_list[i].id]["precinteg"] = presetdata[i]
        obs_prec_integ[prm.time][mk2_point_list[i].id]["prec60"] = p60data[i]
        obs_prec_integ[prm.time][mk2_point_list[i].id]["UpdateTime"] = updatetime[i]  # 第２通行止め
        obs_prec_integ[prm.time][mk2_point_list[i].id]["ResetTime"] = resettime[i]    # 第２通行止め
        obs_prec_integ[prm.time][mk2_point_list[i].id]["ResetStart"] = resetstart[i]  # 第２通行止め
        obs_prec_integ[prm.time][mk2_point_list[i].id]["SecondTime"] = secondtime[i]  # 新第２
      }
    }
    $log.write("obs_prec_integ read end.")
  else
    $log.write("obs_prec_integ data not exist.")
  end
  mkConn.close_connection
  return obs_prec_integ
end

def get_obs_scale_hour(end_time,announcetime,mk2_rid_list)
  # 取得開始時刻 = 取得終了時刻 - 連続雨量リセット時間の最大値
  start_time = end_time - 3600 * $rd_table_summer["max_reseet_hour"]
  if announcetime - 3600 < start_time
    # 発表時刻が取得開始時刻より小さい場合は発表時刻が取得開始時刻
    start_time = announcetime - 3600
  end
  if end_time > announcetime + 3600 * 96
    # 過去データ
    end_time = announcetime + 3600 * 96
  end
  $log.write("get_obs_scale start_time=%s end_time=%s" % [start_time.to_s,end_time.to_s])
  obs_rain_scale = {}
  mkConn = MkConnection.new( $host, $port)
  time_list = mkConn.get_time_list($config["mk2_scale_table"], start_time, end_time)
  params = []
  time_list.each{|btime|
    if btime.to_i % 3600 == 0
      params.push(MkDataParam.new(0, '0', btime))
    end
  }
  if params.size > 0
    $log.write("get_obs_scale read start.")
    element_list = [ 'second_flg:INT8','use_second:INT8','rain_scale:INT16' ]
    pd = mkConn.read_point($config["mk2_scale_table"], params, mk2_rid_list, element_list)
    params.each{|prm|
      obs_rain_scale[prm.time] = {}
      second_flg = pd.get_data(prm, 'second_flg')
      use_second = pd.get_data(prm, 'use_second')
      rain_scale = pd.get_data(prm, 'rain_scale')
      mk2_rid_list.each_index{|i|
        obs_rain_scale[prm.time][mk2_rid_list[i].id] = {}
        obs_rain_scale[prm.time][mk2_rid_list[i].id]["second_flg"] = second_flg[i]
        obs_rain_scale[prm.time][mk2_rid_list[i].id]["use_second"] = use_second[i]
        obs_rain_scale[prm.time][mk2_rid_list[i].id]["rain_scale"] = rain_scale[i]
      }
    }
    $log.write("get_obs_scale read end.")
  else
    $log.write("get_obs_scale data not exist.")
  end
  mkConn.close_connection
  return obs_rain_scale
end

def get_prcrin_prst_mmm_nhour(prcrin_prst_input)
  vt = prcrin_prst_input[0]
  oid = prcrin_prst_input[1]
  odt = prcrin_prst_input[2]
  fdt = prcrin_prst_input[3]
  prcrin_prst_prev = prcrin_prst_input[4]
  mmm = prcrin_prst_input[5]
  hours = prcrin_prst_input[6]
  reset_t = prcrin_prst_input[7]
  resettime = prcrin_prst_input[8]  # 第２通行止め
  starttime = prcrin_prst_input[9] # 第２通行止め
  rstart = prcrin_prst_input[10]    # 第２通行止め
  a_flag = prcrin_prst_input[11]    # 第２通行止め
  s_time = prcrin_prst_input[12]    # 新第２
  mm = mmm / 10.0
  prcrin = 0
  reset_flag = false
  if fdt[vt] > 0
    prcrin = fdt[vt]      # 時雨量
    if fdt[vt] >= $config["second_thd"]  # 新第２
      s_time = vt
    end
  end
  ret = prcrin_prst_prev  # 連続雨量
  if(prcrin >= mm)
    # 基準値以上
    if(prcrin_prst_prev == 0)
      ret = prcrin
      starttime = vt
    elsif(prcrin_prst_prev != 0)
      ret = prcrin + prcrin_prst_prev
    end
    reset_t = vt
  else
    # 基準値未満
    if (prcrin_prst_prev == 0)
      # 前回連続雨量なし
      ret = prcrin
      if prcrin > 0
        reset_t = vt
        starttime = vt
      end
    else
      # 前回連続雨量あり
      et = vt - (hours-2)*60*60  # FTから継続時間前
      t = vt  # FT
      rain_flag = false
      while(true)
        if a_flag
          rain_flag = true
          break
        end
        break if(t < et)  # FTから継続時間前まで
        if !reset_t.nil?
          if(t < reset_t)
            rain_flag = true
            break 
          end
        end
        v = 0
        if odt.has_key?(t) && odt[t][oid] != nil
          v = odt[t][oid]["prec60"]
          v = (v / 10.0) if v > 0
        end
        v = fdt[t] if(fdt.has_key?(t))
        rain_flag = true if(v >= mm)
        break if(rain_flag)
        t -= 3600  # １時間前へ
      end
      if (rain_flag)
        ret = prcrin_prst_prev + prcrin
      else
        resettime = vt + 3600  # 第２通行止め
        rstart = starttime
        reset_t = nil
        ret = prcrin_prst_prev + prcrin
        reset_flag = true
      end
    end
  end
  prcrin_prst_output = [ret, reset_t, resettime, rstart, starttime, reset_flag, s_time]
  return prcrin_prst_output
end

# 最新の実況値連続雨量
def get_latest_prec_integ(just_time,oft,mk2_pointid,obs_prec_integ,prcrin_prst_nmm,prcrin_prst_nhour)
  reset_flag = false
  if obs_prec_integ[just_time] != nil && obs_prec_integ[just_time][mk2_pointid] != nil
    if obs_prec_integ[just_time][mk2_pointid]["precinteg"] > 0 && obs_prec_integ[just_time][mk2_pointid]["prec60"] < prcrin_prst_nmm
      # 前回連続雨量あり
      et = just_time - (prcrin_prst_nhour-2)*60*60  # FTから継続時間前
      t = just_time  # FT
      reset_t = nil
      if obs_prec_integ[just_time][mk2_pointid]["UpdateTime"] > 0
        reset_t = Time.at(obs_prec_integ[just_time][mk2_pointid]["UpdateTime"])
      end
      rain_flag = false
      while(true)
        break if(t < et)  # FTから継続時間前まで
        if !reset_t.nil?
          if(t < reset_t)
            rain_flag = true
            break 
          end
        end
        if obs_prec_integ[t] != nil && obs_prec_integ[t][mk2_pointid] != nil
          if obs_prec_integ[t][mk2_pointid]["prec60"] >= prcrin_prst_nmm
            rain_flag = true
          end
        end
        break if(rain_flag)
        t -= 3600  # １時間前へ
      end
      if rain_flag == false
        reset_flag = true
        $log.write("obs reset 60min pitch %s" % [mk2_pointid])
      end
    end
  end
  ift = oft
  # latestからlatest正時まで5分間隔で最初にヒットした値
  while just_time <= ift
    if obs_prec_integ[ift] != nil && obs_prec_integ[ift][mk2_pointid] != nil
      if obs_prec_integ[ift][mk2_pointid]["prec60"] >= 0 && obs_prec_integ[ift][mk2_pointid]["precinteg"] >= 0
        # 実況値連続雨量あり
        $log.write("%s %s %s precinteg=%s" % [oft.to_s,mk2_pointid,ift.to_s,obs_prec_integ[ift][mk2_pointid]["precinteg"]]) if $verbose
        prcrin_prst = (obs_prec_integ[ift][mk2_pointid]["precinteg"] / 10.0).truncate
        prcrin_prst_update_t = nil
        prcrin_prst_reset_t = nil
        prcrin_prst_start_t = nil
        prcrin_prst_rstart_t = nil
        prcrin_prst_second_t = nil
        if obs_prec_integ[ift][mk2_pointid]["UpdateTime"] > 0
          prcrin_prst_update_t = Time.at(obs_prec_integ[ift][mk2_pointid]["UpdateTime"])
        end
        if obs_prec_integ[ift][mk2_pointid]["StartTime"] > 0
          prcrin_prst_start_t = Time.at(obs_prec_integ[ift][mk2_pointid]["StartTime"])
        end
        if obs_prec_integ[ift][mk2_pointid]["ResetTime"] > 0
          prcrin_prst_reset_t = Time.at(obs_prec_integ[ift][mk2_pointid]["ResetTime"])
        end
        if obs_prec_integ[ift][mk2_pointid]["ResetStart"] > 0
          prcrin_prst_rstart_t = Time.at(obs_prec_integ[ift][mk2_pointid]["ResetStart"])
        end
        if obs_prec_integ[ift][mk2_pointid]["SecondTime"] > 0
          prcrin_prst_second_t = Time.at(obs_prec_integ[ift][mk2_pointid]["SecondTime"])
        end
        if reset_flag
          lft = ift
          while just_time < lft
            if obs_prec_integ[lft] != nil && obs_prec_integ[lft][mk2_pointid] != nil
              if obs_prec_integ[lft][mk2_pointid]["prec60"] >= 0 && obs_prec_integ[lft][mk2_pointid]["precinteg"] >= 0
                if obs_prec_integ[lft][mk2_pointid]["prec60"] >= prcrin_prst_nmm
                  reset_flag = false
                  break
                end
              end
            end
            lft = lft - 300
          end
        end
        ret = [prcrin_prst,ift,prcrin_prst_update_t,prcrin_prst_reset_t,prcrin_prst_start_t,prcrin_prst_rstart_t,prcrin_prst_second_t,reset_flag]
        return ret
      end
    end
    $log.write("%s latest value not available." % [mk2_pointid]) if $verbose
    ift = ift - 300
  end
  return nil
end
