def road_cond_level(v)
  # 1   => '乾燥',            →  乾燥
  # 501 => '半乾燥',          →  湿潤
  # 502 => '半湿',            →  湿潤
  # 2   => '湿潤',            →  湿潤
  # 503 => '霜',              →  湿潤
  # 4   => '積雪',            →  湿潤
  # 5   => '圧雪',            →  湿潤
  # 6   => '凍結',            →  湿潤  
  # 7   => 'シャーベット黒',  →  湿潤
  # 8   => 'シャーベット白',  →  湿潤
  # 999 => '未発表',          →  入力なし、又は---
  # 990 => '未観測',          →  入力なし、又は---
  # 991 => '入力なし',        →  入力なし、又は---
  
  # 0:入力なし、又は---, 1:乾燥, 2:湿潤
  if v == 1
    return 1
  elsif v >= 990
    return 0
  else
    return 2
  end
end

def salt_residue_level(v)
  # 0:入力なし, 1:不明, 2:無し, 3:有り
  v = v.nil? ? v : v.to_i
  if v == 1
    return 2
  elsif v == 2
    return 3
  elsif v == 991
    return 0
  else
    return 1
  end
end

def road_moisture_level(v)
  # 0:不明, 1:無し, 2:有り
  v = v.nil? ? v : v.to_i
  if v == 0
    return 1
  elsif v == 1
    return 2
  else
    return 0
  end
end

# JB本四スプールデータの読み込み
def read_honsi_spool()
  $log.write("read honsi spool.")
  # 寒候期区間と気象中央観測地点の紐づけ情報スプールファイル
  honsi_winter_obsid = nil
  dbdata = PStore.new($config["spool_dir"] + $config["honsi_winter_obsid_spool"])
  dbdata.transaction() do
    honsi_winter_obsid = dbdata['root']
  end
  if honsi_winter_obsid == nil || honsi_winter_obsid.size < 1
    $log.write("%s data not spooled." % [$config["honsi_winter_obsid"]])
    # なければ本四10V判定はスキップ
    return
  end
  $honsi_obs_data = honsi_winter_obsid
  # 観測情報手入力データスプールファイル
  # jbhonsi_manualentered[obs_time][zone_id]["RDCND"] = 値
  #                                         ["RSLT"] = 値
  jbhonsi_manualentered = nil
  latest_manualentered = {}
  dbdata = PStore.new($config["spool_dir"] + $config["jbhonsi_manualentered_spool"])
  dbdata.transaction() do
    jbhonsi_manualentered = dbdata['root']
  end
  if jbhonsi_manualentered == nil || jbhonsi_manualentered.size < 1
    $log.write("%s data not spooled." % [$config["jbhonsi_manualentered_spool"]])
  else
    # 最新のデータのみ
    otms = jbhonsi_manualentered.keys.sort
    otms.reverse_each{|obs_time|
      if obs_time < Time.now - 3600 * 3
        break
      end
      jbhonsi_manualentered[obs_time].each_pair{|zid,evalue|
        if latest_manualentered[zid] == nil
          latest_manualentered[zid] = {}
        end
        value = salt_residue_level(evalue["RSLT"])
        if latest_manualentered[zid]["RSLT"] == nil
          latest_manualentered[zid]["RSLT"] = value
        else
          if latest_manualentered[zid]["RSLT"] == 2 || latest_manualentered[zid]["RSLT"] == 3
            next
          else
            if value == 2 || value == 3
              latest_manualentered[zid]["RSLT"] = value
            end
          end
        end
        value = road_cond_level(evalue["RDCND"])
        if latest_manualentered[zid]["RDCND"] == nil
          latest_manualentered[zid]["RDCND"] = value
        else
          if latest_manualentered[zid]["RDCND"] == 1 || latest_manualentered[zid]["RDCND"] == 2
            next
          else
            if value == 1 || value == 2
              latest_manualentered[zid]["RDCND"] = value
            end
          end
        end
      }
    }
  end
  # 観測値路面水分
  obs_honsi_rdmsrt = {}
  mkConn = MkConnection.new($host, $port)
  time_list = mkConn.get_time_list($config["mk2_winter_table"], Time.now-3600, Time.now)
  params = []
  time_list.each{|btime|
    params.push(MkDataParam.new(0, '402200485', btime))
  }
  if params.size > 0
    # 最新のデータのみ
    $log.write("honsi mk2 read start.")
    element_list = [ 'Rdmsrt:INT16' ]
    pd = mkConn.read_point($config["mk2_winter_table"], params, [], element_list)
    mk2_rid_list = pd.get_point_list
    params.reverse_each{|prm|
      rdmsrt = pd.get_data(prm, 'Rdmsrt')
      mk2_rid_list.each_index{|i|
        pid = mk2_rid_list[i].id
        value = road_moisture_level(rdmsrt[i])
        if obs_honsi_rdmsrt[pid] == nil
          obs_honsi_rdmsrt[pid] = value
        else
          if obs_honsi_rdmsrt[pid] == 1 || obs_honsi_rdmsrt[pid] == 2
            next
          else
            if value == 1 || value == 2
              obs_honsi_rdmsrt[pid] = value
            end
          end
        end
      }
    }
    mkConn.close_connection
  else
    $log.write("honsi mk2 data not exist.")
    mkConn.close_connection
    return
  end
  # マージ
  # 塩分あり／なし、乾燥／湿潤（観測／目視）情報の値変換
  # 塩分あり／なし、乾燥／湿潤判定
  # $honsi_obs_data[zoneid]['LCLID'] = 値
  #                        ['LNAME'] = 値
  #                        ['E'] = 値
  #                        ['Rdmsrt'] = 値
  #                        ['RDCND'] = 値
  #                        ['RSLT'] = 値
  #                        ['wet'] = 値
  #                        ['solt'] = 値
  $honsi_obs_data.each_key{|zid|
    # 路面水分（観測）
    lclid = $honsi_obs_data[zid]['LCLID']
    if obs_honsi_rdmsrt[lclid] == nil
      $honsi_obs_data[zid]['Rdmsrt'] = 0 # 不明
    else
      $honsi_obs_data[zid]['Rdmsrt'] = obs_honsi_rdmsrt[lclid]
    end
    # 塩分、路面状態（目視）
    if latest_manualentered[zid] == nil
      $honsi_obs_data[zid]['RDCND'] = 0 # 不明
      $honsi_obs_data[zid]['RSLT'] = 0  # 入力なし
    else
      $honsi_obs_data[zid]['RDCND'] = latest_manualentered[zid]['RDCND']
      $honsi_obs_data[zid]['RSLT'] = latest_manualentered[zid]['RSLT']
    end
    # 塩分ありなし
    if $honsi_obs_data[zid]['RSLT'] == 3
      $honsi_obs_data[zid]['solt'] = 1
    else
      $honsi_obs_data[zid]['solt'] = 0
    end
    # 乾燥／湿潤
    if $honsi_obs_data[zid]['Rdmsrt'] == 2 || $honsi_obs_data[zid]['RDCND'] == 2
      $honsi_obs_data[zid]['wet'] = 1
    else
      $honsi_obs_data[zid]['wet'] = 0
    end
  }
  if $config["honsi_obs_data_test"] != nil
    dbdata = PStore.new($config["spool_dir"] + $config["honsi_obs_data_test"])
    dbdata.transaction() do
      dbdata['root'] = $honsi_obs_data
    end
  end
end

# 降雪パターン判定
def get_honsi_snow_rank(zoneid,snow,temp)
  if snow >= 3
    # 多量積雪レベル(昼夜帯積算降雪量3cm以上)
    $honsi_obs_data[zoneid]["scale"] = 20
    $honsi_obs_data[zoneid]["scale_2"] = 80
  elsif snow >= 2
    # 積雪レベル(昼夜帯積算降雪量2cm以上)
    $honsi_obs_data[zoneid]["scale"] = 10
    $honsi_obs_data[zoneid]["scale_2"] = 70
  elsif snow >= 1
    # うっすらレベル(昼夜帯積算降雪量1cm以上)
    $honsi_obs_data[zoneid]["scale"] = 2
    $honsi_obs_data[zoneid]["scale_2"] = 62
  else # snow == 0
    # 湿潤レベル(昼夜帯積算降雪量0cm)
    if temp <= 0
      # 0℃以下（0℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 51
      else
        # 塩分なし
        $honsi_obs_data[zoneid]["scale"] = 2
        $honsi_obs_data[zoneid]["scale_2"] = 52
      end
    elsif temp <= 2
      # 2℃以下（2℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 50
      else
        # 塩分なし
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 51
      end
    else
      # 2℃より上（2℃<）
      $honsi_obs_data[zoneid]["scale"] = 0
      $honsi_obs_data[zoneid]["scale_2"] = 50
    end
  end
end

# 降雨パターン判定
def get_honsi_prec_rank(zoneid,prec,temp,prec_ptrn)
  if prec >= 1
    # 剤流出レベル(昼夜帯積算1mm以上)
    if temp <= 0
      # 0℃以下（0℃≧）
      if prec_ptrn
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 41
      else
        $honsi_obs_data[zoneid]["scale"] = 2
        $honsi_obs_data[zoneid]["scale_2"] = 42
      end
    elsif temp <= 2
      # 2℃以下（2℃≧）
      $honsi_obs_data[zoneid]["scale"] = 1
      $honsi_obs_data[zoneid]["scale_2"] = 41
    else
      # 2℃より上（2℃<）
      $honsi_obs_data[zoneid]["scale"] = 0
      $honsi_obs_data[zoneid]["scale_2"] = 40
    end
  else
    # 湿潤レベル(昼夜帯積算0mm)
    if temp <= 0
      # 0℃以下（0℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 31
      else
        # 塩分なし
        if prec_ptrn
          $honsi_obs_data[zoneid]["scale"] = 1
          $honsi_obs_data[zoneid]["scale_2"] = 31
        else
          $honsi_obs_data[zoneid]["scale"] = 2
          $honsi_obs_data[zoneid]["scale_2"] = 32
        end
      end
    elsif temp <= 2
      # 2℃以下（2℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 30
      else
        # 塩分なし
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 31
      end
    else
      # 2℃より上（2℃<）
      $honsi_obs_data[zoneid]["scale"] = 0
      $honsi_obs_data[zoneid]["scale_2"] = 30
    end
  end
end

# 無効水パターン判定
def get_honsi_noprfz_rank(zoneid,frost_dewing,temp)
  if frost_dewing == 0
    # 降霜結露なし(路温-露点温度>0)
    if $honsi_obs_data[zoneid]['E'] == 1
      # Eルートのみ
      if temp <= -2
        # -2℃以下（-2℃≧）
        if $honsi_obs_data[zoneid]['solt'] == 1
          # 塩分あり
          $honsi_obs_data[zoneid]["scale"] = 0
          $honsi_obs_data[zoneid]["scale_2"] = 10
        else
          # 塩分なし
          $honsi_obs_data[zoneid]["scale"] = 2
          $honsi_obs_data[zoneid]["scale_2"] = 12
        end
        return
      end
      if temp <= -0.6
        # -0.6℃以下（-0.6℃≧）
        if $honsi_obs_data[zoneid]['solt'] == 1
          # 塩分あり
          $honsi_obs_data[zoneid]["scale"] = 0
          $honsi_obs_data[zoneid]["scale_2"] = 10
        else
          # 塩分なし
          if $honsi_obs_data[zoneid]['wet'] == 0
            # 乾燥
            $honsi_obs_data[zoneid]["scale"] = 1
            $honsi_obs_data[zoneid]["scale_2"] = 11
          else
            # 湿潤
            $honsi_obs_data[zoneid]["scale"] = 2
            $honsi_obs_data[zoneid]["scale_2"] = 12
          end
        end
        return
      end
    end
    if temp <= 0
      # 0℃以下（0℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 10
      else
        # 塩分なし
        if $honsi_obs_data[zoneid]['wet'] == 0
          # 乾燥
          $honsi_obs_data[zoneid]["scale"] = 0
          $honsi_obs_data[zoneid]["scale_2"] = 10
        else
          # 湿潤
          $honsi_obs_data[zoneid]["scale"] = 2
          $honsi_obs_data[zoneid]["scale_2"] = 12
        end
      end
    elsif temp <= 2
      # 2℃以下（2℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 10
      else
        # 塩分なし
        if $honsi_obs_data[zoneid]['wet'] == 0
          # 乾燥
          $honsi_obs_data[zoneid]["scale"] = 0
          $honsi_obs_data[zoneid]["scale_2"] = 10
        else
          # 湿潤
          $honsi_obs_data[zoneid]["scale"] = 1
          $honsi_obs_data[zoneid]["scale_2"] = 11
        end
      end
    else
      # 2℃より上（2℃<）
      $honsi_obs_data[zoneid]["scale"] = 0
      $honsi_obs_data[zoneid]["scale_2"] = 10
    end
  else
#    print "降霜結露あり\n"
    # 降霜結露あり(路温-露点温度<=0)
    if $honsi_obs_data[zoneid]['E'] == 1
      # Eルートのみ
      if temp <= -0.6
        # -0.6℃以下（-0.6℃≧）
        if $honsi_obs_data[zoneid]['solt'] == 1
          # 塩分あり
          $honsi_obs_data[zoneid]["scale"] = 0
          $honsi_obs_data[zoneid]["scale_2"] = 20
        else
          # 塩分なし
          $honsi_obs_data[zoneid]["scale"] = 2
          $honsi_obs_data[zoneid]["scale_2"] = 22
        end
        return
      end
    end
    if temp <= 0
      # 0℃以下（0℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 20
      else
        # 塩分なし
        $honsi_obs_data[zoneid]["scale"] = 2
        $honsi_obs_data[zoneid]["scale_2"] = 22
      end
    elsif temp <= 2
      # 2℃以下（2℃≧）
      if $honsi_obs_data[zoneid]['solt'] == 1
        # 塩分あり
        $honsi_obs_data[zoneid]["scale"] = 0
        $honsi_obs_data[zoneid]["scale_2"] = 20
      else
        # 塩分なし
        $honsi_obs_data[zoneid]["scale"] = 1
        $honsi_obs_data[zoneid]["scale_2"] = 21
      end
    else
      # 2℃より上（2℃<）
      $honsi_obs_data[zoneid]["scale"] = 0
      $honsi_obs_data[zoneid]["scale_2"] = 20
    end
  end
end

# 日中帯、夜間帯、それぞれの期間の降雨開始以後の最低路温、最低気温
def get_min_temp_after_rain(zoneid,daynight,refw_fcas)
  i = daynight["bftc"]
  temp = nil
#  mintime = nil
  start = false
#  $log.write("%s" % [ zoneid ])
  while refw_fcas[i] != nil
    if !start
      if refw_fcas[i]["WX"] == 300
#        $log.write("%s %s start" % [ zoneid, refw_fcas[i]["FCASD"].get_value_time ])
        start = true
      end
    end
    if start
      if zoneid !~ /^5105/ && refw_fcas[i]["AIRTMP"] != LACK_VALUE_16
        if temp == nil || temp > refw_fcas[i]["AIRTMP"]
          temp = refw_fcas[i]["AIRTMP"]
#          mintime = refw_fcas[i]["FCASD"].get_value_time
#          $log.write("%s %s min_temp_after_rain=%s" % [ zoneid, mintime, temp ])
        end
      end
      if refw_fcas[i]["RDTMP"] != LACK_VALUE_16
        if temp == nil || temp > refw_fcas[i]["RDTMP"]
          temp = refw_fcas[i]["RDTMP"]
#          mintime = refw_fcas[i]["FCASD"].get_value_time
#          $log.write("%s %s min_temp_after_rain=%s" % [ zoneid, mintime, temp ])
        end
      end
    end
    if daynight["end"] <= refw_fcas[i]["FCASD"].get_value_time
      break
    end
    i += 1
  end
#  $log.write("%s %s min_temp_after_rain=%s" % [ zoneid, mintime, temp ])
  return temp
end

# 降霜結露の有無
def get_frost_dewing(zoneid,daynight,refw_fcas)
  i = daynight["bftc"]
  frost_dewing = 0
  while refw_fcas[i] != nil
    if refw_fcas[i]["RDTMP"] != LACK_VALUE_16 && refw_fcas[i]["DEWTMP"] != LACK_VALUE_16
      if refw_fcas[i]["RDTMP"] - refw_fcas[i]["DEWTMP"] <= 0
        # 降霜結露あり(路温-露点温度<=0)
        frost_dewing = 1
#        $log.write("%s %s frost_dewing %s %s" % [ zoneid, refw_fcas[i]["FCASD"].get_value_time, refw_fcas[i]["RDTMP"], refw_fcas[i]["DEWTMP"] ])
        break
      end
    end
    if daynight["end"] <= refw_fcas[i]["FCASD"].get_value_time
      break
    end
    i += 1
  end
  return frost_dewing
end

# JB本四 スケール計算
def get_honsi_scale(daynight,zoneid,refw_fcas,refw_dn)
  if $honsi_obs_data == nil
    # 紐づけ情報がなければ本四10V判定はスキップ
    return
  end
  if refw_dn.has_member?("RSLT")
    refw_dn["RSLT"] = $honsi_obs_data[zoneid]["RSLT"]
    refw_dn["RDMSRT"] = $honsi_obs_data[zoneid]["Rdmsrt"]
  end
  if refw_dn.has_member?("RDCND_2")
    refw_dn["RDCND_2"] = $honsi_obs_data[zoneid]["RDCND"]
  end
  prcrin = daynight["PRCRIN_TOTAL"]
  airtmp = daynight["AIRTMP_MIN"]
  rdtemp = daynight["RDTMP_MIN"]
  snwfll = daynight["SNWFLL_TOTAL"]["raw"]
  prec0 =  daynight["RAIN_HOURS"]
  snow0 =  daynight["SNOW_HOURS"]
  raint =  daynight["RAIN_TELOP"]
  temp = nil
  if zoneid  =~ /^5105/
    # 尾道C
    if rdtemp == nil || rdtemp == LACK_VALUE_16
      # 路温なしはスキップ
      return
    else
      temp = rdtemp
    end
  else
    if (airtmp == nil || airtmp == LACK_VALUE_16) && (rdtemp == nil || rdtemp == LACK_VALUE_16)
      # 気温路温両方なしはスキップ
      return
    else
      if airtmp == LACK_VALUE_16
        temp = rdtemp
      elsif rdtemp == LACK_VALUE_16
        temp = airtmp
      else
        temp = [airtmp,rdtemp].min
      end
    end
  end
  # 判定パターンの判定
  if snwfll > 0.0 || snow0 > 0
    # 昼夜帯積算降雪量が0cm以上（0mm≦）の場合
    # 「総降雪量」が0で、かつ、時間帯内に時間降雪量0が1コマ以上のとき（0雪）
    # 降雪パターン判定
    get_honsi_snow_rank(zoneid,snwfll,temp)
  elsif prcrin > 0.0 || (raint > 0 && prec0 > 0)
    # 昼夜帯積算降水量が0mm以上（0mm≦）の場合
    # 「総雨量」>= 0 で、かつ、時間帯内に天気テロップの雨が1コマ以上、かつ、時間帯内に時間降雪量0が1コマ以上のとき（0雨）
    # 降雨パターン判定
    prec_ptrn = false
    if $honsi_obs_data[zoneid]['solt'] == 1 || $honsi_obs_data[zoneid]['wet'] == 0
      # 塩分あり、または、塩分なし乾燥の場合
      # 日中帯、夜間帯、それぞれの期間の降雨開始以後の最低路温、最低気温を使用する。
      temp2 = get_min_temp_after_rain(zoneid,daynight,refw_fcas)
      if temp2 == nil
        $log.write("%s %s cannot get min temp after rain." % [zoneid,daynight["begin"]])
        return
      end
      # 「降雨開始以降に2以下で0℃より大きい」かつ「塩分なし+乾燥」
      if $honsi_obs_data[zoneid]['solt'] == 0 && $honsi_obs_data[zoneid]['wet'] == 0 && temp2 > 0 && temp2 <= 2
        prec_ptrn = true
      else
        temp = temp2
      end
    end
    get_honsi_prec_rank(zoneid,prcrin,temp,prec_ptrn)
  else
    # 無効水パターン判定
    # 降霜結露の有無
    frost_dewing = get_frost_dewing(zoneid,daynight,refw_fcas)
    get_honsi_noprfz_rank(zoneid,frost_dewing,temp)
  end
  refw_dn["VSCAL"] = $honsi_obs_data[zoneid]["scale"]
  refw_dn["VSCAL_2"] = $honsi_obs_data[zoneid]["scale_2"] if refw_dn.has_member?("VSCAL_2")
end
