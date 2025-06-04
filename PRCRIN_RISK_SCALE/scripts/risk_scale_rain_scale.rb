# FT1のマイクロネットと解析雨量の大きいほう
$prec_ft1 = {}
# COMPASS地点MkPoint
$mk2_compass_point_list = []
# 地点とCOMPASS地点の紐付け
$pointid_compassid = {}
# COMPASS地点テキスト
$compass_point_list = []
# COMPASS雨量カウンタft
$compass_p60_all = []

#$debug_fs = nil

def make_compass_point()
  # 1kmメッシュ群（緯度経度）紐付けテーブルを読む。
  area_mesh_compass = nil
  dbdata = PStore.new($config["area_mesh_compas_path"])
  dbdata.transaction() do
    area_mesh_compass = dbdata['root']
  end
  if area_mesh_compass == nil || area_mesh_compass.size < 1
    print "table_area spool data not exist\n"
    exit
  end
  pary = area_mesh_compass.keys.sort
  pary.each{|point|
    if $point_id.index(point) == nil
      next
    end
    mesh_point = []
    mesh_list = area_mesh_compass[point]
    mesh_list.each{|mesh|
      pointid = "%s_%s_%s" % [point,mesh[0],mesh[1]]
      mesh_point.push(pointid)
      $compass_point_list.push(pointid)
      $mk2_compass_point_list.push(MkPoint.new( pointid ))
    }
    $pointid_compassid[point] = mesh_point
  }
end

# COMPASSデータをmk2から取得
def get_compass_prec(mkConn,justtime)
  dbdata = PStore.new($config["spool_compass_prec_path"])
  dbdata.transaction() do
    dbdata['root'] = Time.now
    latesttime = mkConn.get_latest_time( $config["mk2_compass_prec_mesh_counter"] )
    print "%s get_compass_prec latesttime=%s\n" % [Time.now.to_s,latesttime.to_s]
    ft_list = mkConn.get_ft_list($config["mk2_compass_prec_mesh_counter"], latesttime, "PrecCounter")
    params = []
    ft_list.each{|ft|
      gettime = latesttime + ft
      if gettime >= justtime
        params.push(MkDataParam.new(ft, '0', latesttime))
#        print "%s get_compass_prec gettime=%s\n" % [Time.now.to_s,gettime.to_s]
      end
    }
    element_list = [ 'PrecCounter:INT32' ]
    pd = mkConn.read_point($config["mk2_compass_prec_mesh_counter"], params, $mk2_compass_point_list, element_list)
    params.each{|prm|
      precc = pd.get_data(prm, 'PrecCounter')
      unitconv(precc)
      p60hash = {}
      $compass_point_list.each_index{|i|
        p60hash[$compass_point_list[i]] = precc[i]
      }
      $compass_p60_all.push(p60hash)
    }
  end
end

# 60分雨量をすべて保存
def save_60min(pid,fti,justtime)
  pointid = pid.split("-")
  customer_id = pointid[0]
  kakuho_invalid = $kakuho_ignore.index(customer_id) != nil
  c_p60 = -1
  p60 = -1
  # COMPASSの値は常に保存する
  if $output_data[pid][fti]["compass"] == nil
    $output_data[pid][fti]["compass"] = {}
  end
  if $compass_prec != nil && $compass_prec[justtime+3600*fti] != nil && $compass_prec[justtime+3600*fti][pid] !=nil
    c_p60 = $compass_prec[justtime+3600*fti][pid]
  end
  if $output_data[pid][fti]["compass"]["PRCRIN_60min"] == nil
    $output_data[pid][fti]["compass"]["PRCRIN_60min"] = c_p60
  end
  if fti <= 3
    if fti == 2 || fti == 3
      if $kakuho_calc_3ft == nil || $kakuho_calc_3ft[fti-1] == nil || $kakuho_calc_3ft[fti-1][pid] == nil || $kakuho_calc_3ft[fti-1][pid]["max"] < 0
        kakuho_invalid = true
      end
    end
    # 確報使用FT1-3
    # 確報
    if $output_data[pid][fti]["kakuho"] == nil
      $output_data[pid][fti]["kakuho"] = {}
    end
    if  fti == 3 || kakuho_invalid
      p60 = c_p60
    else
      if fti == 1
        if $prec_ft1[pid] != nil
          p60 = $prec_ft1[pid]
        else
          print "pid=%s ft1 data not exist.\n" % [pid]
        end
      else
#        p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter"]
        if $kakuho_calc_3ft[fti-1][pid]["max"] <= $config["kakuho_filter_4"]
          p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter"]
        else
          p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter_2"] + $config["kakuho_filter_3"]
        end
      end
      p60 = p60 >= 0 ? p60 : c_p60
    end
    if $output_data[pid][fti]["kakuho"]["PRCRIN_60min"] == nil
      $output_data[pid][fti]["kakuho"]["PRCRIN_60min"] = p60
    end
  end
end

# 60分雨量による判定
def get_scale_60min(pid,lvl,fti,justtime)
  pointid = pid.split("-")
  customer_id = pointid[0]
  kakuho_invalid = $kakuho_ignore.index(customer_id) != nil
  if fti > 3
    # COMPASS使用←データではなく閾値
    threshold = $threshold_level[pid][lvl]["forecast"]["compass"]
    if threshold["PRCRIN_60min"] != nil && threshold["PRCRIN_60min"] != ""
      if $output_data[pid][fti]["compass"] == nil
        $output_data[pid][fti]["compass"] = {}
      end
      if $output_data[pid][fti]["compass"]["INDEX_PRCRIN_60min"] == nil
        if $output_data[pid][fti]["compass"]["PRCRIN_60min"] == nil
          p60 = -1
          if $compass_prec != nil && $compass_prec[justtime+3600*fti] != nil && $compass_prec[justtime+3600*fti][pid] !=nil
            p60 = $compass_prec[justtime+3600*fti][pid]
          end
          $output_data[pid][fti]["compass"]["PRCRIN_60min"] = p60
        end
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_60min"] = $output_data[pid][fti]["compass"]["PRCRIN_60min"] < 0 ? -99 : 0
      end
      if threshold["PRCRIN_60min"] <= $output_data[pid][fti]["compass"]["PRCRIN_60min"]
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_60min"] = lvl
      end
    end
  else
    if fti == 2 || fti == 3
      if $kakuho_calc_3ft == nil || $kakuho_calc_3ft[fti-1] == nil || $kakuho_calc_3ft[fti-1][pid] == nil || $kakuho_calc_3ft[fti-1][pid]["max"] < 0
        print "pid=%s ft=%d kakuho data not exist.\n" % [pid,fti]
        kakuho_invalid = true
      end
    end
    # 確報使用FT1-3
    combine_flag = 0
    c_p60 = -1
    p60 = -1
    threshold_combine = $threshold_level[pid][lvl]["kakuho"]["micronet"]
    if threshold_combine != nil && threshold_combine["PRCRIN_combine_PRST"] != nil && threshold_combine["PRCRIN_combine_PRST"] != "" &&
        threshold_combine["PRCRIN_combine_60min"] != nil && threshold_combine["PRCRIN_combine_60min"] != ""
      combine_flag = 1
    end
    threshold = $threshold_level[pid][lvl]["kakuho"]["kakuho"]
    if threshold != nil && threshold["PRCRIN_60min"] != nil && threshold["PRCRIN_60min"] != ""
      combine_flag = 2
    end
    if combine_flag > 0
      # COMPASSの値は常に保存する
      if $output_data[pid][fti]["compass"] == nil
        $output_data[pid][fti]["compass"] = {}
      end
      if $compass_prec != nil && $compass_prec[justtime+3600*fti] != nil && $compass_prec[justtime+3600*fti][pid] !=nil
        c_p60 = $compass_prec[justtime+3600*fti][pid]
      end
      if $output_data[pid][fti]["compass"]["PRCRIN_60min"] == nil
        $output_data[pid][fti]["compass"]["PRCRIN_60min"] = c_p60
      end
      # 確報
      if $output_data[pid][fti]["kakuho"] == nil
        $output_data[pid][fti]["kakuho"] = {}
      end
      if fti == 3 || kakuho_invalid
        p60 = c_p60
      else
        if fti == 1
          if $prec_ft1[pid] != nil
            p60 = $prec_ft1[pid]
          else
            print "pid=%s ft1 data not exist.\n" % [pid]
          end
        else
#          p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter"]
          if $kakuho_calc_3ft[fti-1][pid]["max"] <= $config["kakuho_filter_4"]
            p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter"]
          else
            p60 = $kakuho_calc_3ft[fti-1][pid]["max"] * $config["kakuho_filter_2"] + $config["kakuho_filter_3"]
          end
        end
        p60 = p60 >= 0 ? p60 : c_p60
      end
      if $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_60min"] == nil
        if $output_data[pid][fti]["kakuho"]["PRCRIN_60min"] == nil
          $output_data[pid][fti]["kakuho"]["PRCRIN_60min"] = p60
        end
        if combine_flag == 2
          $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_60min"] = p60 < 0 ? -99 : 0
        end
      end
      if combine_flag == 2 && threshold["PRCRIN_60min"] <= $output_data[pid][fti]["kakuho"]["PRCRIN_60min"]
        $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_60min"] = lvl
      end
    end
  end
end

# 3時間、24時間雨量を計算
def calc_p3h_p24h(pid,fti)
  p3h = 0
  p24h = 0
  p3hm = {}
  p24hm = {}
  p_start_fti = -1
  f_end_fti = -1
  for i in 0...24
    ftri = fti - i
    if ftri > 0
      # 予報値
      if ftri > 2
        if f_end_fti < 0
          f_end_fti = ftri
        end
      else
        if $output_data[pid][ftri] == nil
          next
        end
        if $output_data[pid][ftri]["kakuho"] != nil
          if $output_data[pid][ftri]["kakuho"]["PRCRIN_60min"] != nil && $output_data[pid][ftri]["kakuho"]["PRCRIN_60min"] > 0
            p24h += $output_data[pid][ftri]["kakuho"]["PRCRIN_60min"]
            p3h += $output_data[pid][ftri]["kakuho"]["PRCRIN_60min"] if i < 3
          end
        elsif $output_data[pid][ftri]["compass"] != nil
          if $output_data[pid][ftri]["compass"]["PRCRIN_60min"] != nil && $output_data[pid][ftri]["compass"]["PRCRIN_60min"] > 0
            p24h += $output_data[pid][ftri]["compass"]["PRCRIN_60min"]
            p3h += $output_data[pid][ftri]["compass"]["PRCRIN_60min"] if i < 3
          end
        end
      end
    else
      # 過去値
      ftri = 0 - ftri
      p_start_fti = ftri
      # マイクロネット
      mnetids = $pointid_mnetid[pid]
      if mnetids != nil
        mnetids.each{|mid|
          if p3hm[mid] == nil
            p3hm[mid] = 0
          end 
          if p24hm[mid] == nil
            p24hm[mid] = 0
          end 
          if $micronet_p60_24hour[ftri][mid] != nil && $micronet_p60_24hour[ftri][mid] > 0
            p24hm[mid] += $micronet_p60_24hour[ftri][mid]
            p3hm[mid] += $micronet_p60_24hour[ftri][mid] if i < 3
          end
        }
      end
    end
  end
  # COMPASS最大値
  p3hc_max = 0
  p24hc_max = 0
  if f_end_fti > 2
    fti_24 = f_end_fti - 24 > 2 ? f_end_fti - 24 : 2
    fti_3 = f_end_fti - 3 > 2 ? f_end_fti - 3 : 2
    cmpsids = $pointid_compassid[pid]
    if cmpsids != nil && $compass_p60_all[f_end_fti] != nil
      cmpsids.each{|cid|
        if $compass_p60_all[fti_3] != nil && $compass_p60_all[f_end_fti][cid] != nil && $compass_p60_all[fti_3][cid] != nil
          if $compass_p60_all[f_end_fti][cid] >= 0 && $compass_p60_all[fti_3][cid] >= 0
            if $compass_p60_all[f_end_fti][cid] - $compass_p60_all[fti_3][cid] > p3hc_max
              p3hc_max = $compass_p60_all[f_end_fti][cid] - $compass_p60_all[fti_3][cid]
            end
          end
        end
        if $compass_p60_all[fti_24] != nil && $compass_p60_all[f_end_fti][cid] != nil && $compass_p60_all[fti_24][cid] != nil
          if $compass_p60_all[f_end_fti][cid] >= 0 && $compass_p60_all[fti_24][cid] >= 0
            if $compass_p60_all[f_end_fti][cid] - $compass_p60_all[fti_24][cid] > p24hc_max
              p24hc_max = $compass_p60_all[f_end_fti][cid] - $compass_p60_all[fti_24][cid]
            end
          end
        end
      }
    end
  end
#  if pid == "MYZK001-1"
#    $debug_fs.print "pid=%s fti=%s p3hc_max=%s p24hc_max=%s\n" % [pid,fti,p3hc_max,p24hc_max]
#  end
  p3h += p3hc_max
  p24h += p24hc_max
  # マイクロネット最大値
  p3hm_max = 0
  p3hm.each_value{|v|
    if p3hm_max < v
      p3hm_max = v
    end
  }
  p24hm_max = 0
  p24hm.each_value{|v|
    if p24hm_max < v
      p24hm_max = v
    end
  }
  # 解析雨量最大値
  p3ha_max = 0
  p24ha_max = 0
#  if p_start_fti == 0
#    if $analysis_prec_latest[pid]['PRCRIN_3hour'] != nil && $analysis_prec_latest[pid]['PRCRIN_3hour'] > 0
#      p3ha_max = $analysis_prec_latest[pid]['PRCRIN_3hour']
#    end
#    if $analysis_prec_latest[pid]['PRCRIN_24hour'] != nil && $analysis_prec_latest[pid]['PRCRIN_24hour'] > 0
#      p24ha_max = $analysis_prec_latest[pid]['PRCRIN_24hour']
#    end
#  elsif p_start_fti > 0
#    if $analysis_p60_24hour[p_start_fti][pid] != nil && $analysis_p60_24hour[p_start_fti][pid] > 0
#      p24ha_max = $analysis_p60_24hour[p_start_fti][pid]
#      if p_start_fti < 3
#        p3ha_max = $analysis_p60_24hour[p_start_fti][pid]
#      end
#    end
#    if pid == "TSIMZ001-1"
#      $debug_fs.print "pid=%s fti=%s p_start_fti=%d p3ha_max=%s p24ha_max=%s\n" % [pid,fti,p_start_fti,p3ha_max,p24ha_max]
#    end
#  end
  # マイクロネットと解析雨量の最大値比較
  if p3hm_max > p3ha_max
    p3h += p3hm_max
  else
    p3h += p3ha_max
  end
  if p24hm_max > p24ha_max
    p24h += p24hm_max
  else
    p24h += p24ha_max
  end
  return p3h,p24h
end

# 3時間、24時間雨量による判定
def get_scale_3h_24h(pid,lvl,fti,justtime,p3h,p24h)
  if fti > 3
    # COMPASS使用
    threshold = $threshold_level[pid][lvl]["forecast"]["compass"]
    if threshold["PRCRIN_3hour"] != nil && threshold["PRCRIN_3hour"] != ""
      if $output_data[pid][fti]["compass"] == nil
        $output_data[pid][fti]["compass"] = {}
      end
      if $output_data[pid][fti]["compass"]["PRCRIN_3hour"] == nil
        $output_data[pid][fti]["compass"]["PRCRIN_3hour"] = p3h
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_3hour"] = 0
      end
      if threshold["PRCRIN_3hour"] <= $output_data[pid][fti]["compass"]["PRCRIN_3hour"]
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_3hour"] = lvl
      end
    end
    if threshold["PRCRIN_24hour"] != nil && threshold["PRCRIN_24hour"] != ""
      if $output_data[pid][fti]["compass"] == nil
        $output_data[pid][fti]["compass"] = {}
      end
      if $output_data[pid][fti]["compass"]["INDEX_PRCRIN_24hour"] == nil  # V1.7
        if $output_data[pid][fti]["compass"]["PRCRIN_24hour"] == nil
          $output_data[pid][fti]["compass"]["PRCRIN_24hour"] = p24h
        end
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_24hour"] = 0
      end
      if threshold["PRCRIN_24hour"] <= $output_data[pid][fti]["compass"]["PRCRIN_24hour"]
        $output_data[pid][fti]["compass"]["INDEX_PRCRIN_24hour"] = lvl
      end
    end
  else
    # 確報使用FT1-3
    threshold = $threshold_level[pid][lvl]["kakuho"]["kakuho"]
    if threshold != nil
      if threshold["PRCRIN_3hour"] != nil && threshold["PRCRIN_3hour"] != ""
        if $output_data[pid][fti]["kakuho"] == nil
          $output_data[pid][fti]["kakuho"] = {}
        end
        if $output_data[pid][fti]["kakuho"]["PRCRIN_3hour"] == nil
          $output_data[pid][fti]["kakuho"]["PRCRIN_3hour"] = p3h
          $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_3hour"] = 0
        end
        if threshold["PRCRIN_3hour"] <= $output_data[pid][fti]["kakuho"]["PRCRIN_3hour"]
          $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_3hour"] = lvl
        end
      end
      if threshold["PRCRIN_24hour"] != nil && threshold["PRCRIN_24hour"] != ""
        if $output_data[pid][fti]["kakuho"] == nil
          $output_data[pid][fti]["kakuho"] = {}
        end
        if $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_24hour"] == nil  # V1.7
          if $output_data[pid][fti]["kakuho"]["PRCRIN_24hour"] == nil
            $output_data[pid][fti]["kakuho"]["PRCRIN_24hour"] = p24h
          end
          $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_24hour"] = 0
        end
        if threshold["PRCRIN_24hour"] <= $output_data[pid][fti]["kakuho"]["PRCRIN_24hour"]
          $output_data[pid][fti]["kakuho"]["INDEX_PRCRIN_24hour"] = lvl
        end
      end
    end
  end
end

#
# 組み合わせ雨量による判定
# ft1～ft3まではft=0のPI6の閾値による判定とP60の閾値による判定のAND条件により判定を行う。
# ft0のPI6とftxのP60による組み合わせ判定。ft1～ft3の組み合わせ判定でもft0のPI6を使用する。
#
def get_scale_r6h(pid,lvl,fti,justtime)
  p60 = -1
  if $output_data[pid][fti]["kakuho"] != nil
    if $output_data[pid][fti]["kakuho"]["PRCRIN_60min"] != nil
      p60 = $output_data[pid][fti]["kakuho"]["PRCRIN_60min"]
    end
  elsif $output_data[pid][fti]["compass"] != nil
    if $output_data[pid][fti]["compass"]["PRCRIN_60min"] != nil
      p60 = $output_data[pid][fti]["compass"]["PRCRIN_60min"]
    end
  end
  threshold = $threshold_level[pid][lvl]["kakuho"]["micronet"]
  if threshold != nil
    # 組み合わせ雨量による判定
    if threshold["PRCRIN_combine_PRST"] != nil && threshold["PRCRIN_combine_PRST"] != "" &&
        threshold["PRCRIN_combine_60min"] != nil && threshold["PRCRIN_combine_60min"] != ""
      mnetids = $pointid_mnetid[pid]
      mnetids.each{|mid|
        if $output_data[pid][fti][mid] == nil
          $output_data[pid][fti][mid] = {}
        end
        if $output_data[pid][fti][mid]["PRCRIN_PRST_reset6hour"] == nil
          r6h = $micronet_prec_latest[mid]["PRCRIN_PRST_reset6hour"]
          $output_data[pid][fti][mid]["PRCRIN_PRST_reset6hour"] = r6h
          $output_data[pid][fti][mid]["INDEX_PRCRIN_combine"] = r6h < 0 ? -99 : 0
        end
        if threshold["PRCRIN_combine_60min"] <= p60 && 
            threshold["PRCRIN_combine_PRST"] <= $output_data[pid][fti][mid]["PRCRIN_PRST_reset6hour"]
          $output_data[pid][fti][mid]["INDEX_PRCRIN_combine"] = lvl
        end
      }
    end
  end
#  threshold = $threshold_level[pid][lvl]["kakuho"]["analysis"]
#  if threshold != nil
#    # 組み合わせ雨量による判定
#    if threshold["PRCRIN_combine_PRST"] != nil && threshold["PRCRIN_combine_PRST"] != "" &&
#        threshold["PRCRIN_combine_60min"] != nil && threshold["PRCRIN_combine_60min"] != ""
#      if $output_data[pid][fti]["analysis"] == nil
#        $output_data[pid][fti]["analysis"] = {}
#      end
#      if $output_data[pid][fti]["analysis"]["PRCRIN_PRST_reset6hour"] == nil
#        r6h = $analysis_prec_latest[pid]["PRCRIN_PRST_reset6hour"]
#        $output_data[pid][fti]["analysis"]["PRCRIN_PRST_reset6hour"] = r6h
#        $output_data[pid][fti]["analysis"]["INDEX_PRCRIN_combine"] = r6h < 0 ? -99 : 0
#      end
#      if threshold["PRCRIN_combine_60min"] <= p60 && 
#          threshold["PRCRIN_combine_PRST"] <= $output_data[pid][fti]["analysis"]["PRCRIN_PRST_reset6hour"]
#        $output_data[pid][fti]["analysis"]["INDEX_PRCRIN_combine"] = lvl
#      end
#    end
#  end
end

#
# fti = 1-72
# ＜FP（ft=1）, FP（ft=2）, FP（ft=3）＞
# ［FP］による判定
# ［FP3H］による判定
# ［FP24H］による判定
# ［PI6］と［FP］の組み合わせによる判定
# ［AI6］と［FP］の組み合わせによる判定
# ＜FP（ft=4）～FP（ft=96）＞
# ［FP］による判定
# ［FP3H］による判定
# ［FP24H］による判定
#
# 降水量の閾値
# [point_id][level][ftrange][kind][name] = value
# ftrange
# observation|kakuho|forecast
# kind
# micronet|analysis|kakuho|forecast
# name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_combine_PRST|PRCRIN_combine_60min
#
# 最終出力データ
# [point_id][][kind][name] = value
# kind
# micronetid|analysis|kakuho|compass
# scale name
# INDEX_PRCRIN_10min|INDEX_PRCRIN_60min|INDEX_PRCRIN_3hour|INDEX_PRCRIN_24hour|INDEX_PRCRIN_combine
# value name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_PRST_reset6hour
#
def make_one_ft(fti,justtime)
  # エリアループ
  $point_id.each{|pid|
    if $threshold_level[pid] == nil
      next
    end
    # 60分雨量をすべて保存
    save_60min(pid,fti,justtime)
    levels = $threshold_level[pid].keys.sort
    # 60分雨量による判定を先に行い各FTで使用する60分雨量を確定する
    levels.each{|lvl|
      if fti < 4
        if $threshold_level[pid][lvl]["kakuho"] == nil ||
            $threshold_level[pid][lvl]["kakuho"].size < 1
           next
        end
      else
        if $threshold_level[pid][lvl]["forecast"] == nil ||
            $threshold_level[pid][lvl]["forecast"]["compass"] == nil ||
            $threshold_level[pid][lvl]["forecast"]["compass"].size < 1
           next
        end
      end
      # 60分雨量による判定
      get_scale_60min(pid,lvl,fti,justtime)
    }
    # 3時間、24時間雨量を計算
    p3h,p24h = calc_p3h_p24h(pid,fti)
    # 24時間雨量をすべて保存 V1.7
    if fti > 3
      # COMPASS使用
      $output_data[pid][fti]["compass"]["PRCRIN_24hour"] = p24h
    else
      # 確報使用FT1-3
      $output_data[pid][fti]["kakuho"]["PRCRIN_24hour"] = p24h
    end
    levels.each{|lvl|
      if fti < 4
        if $threshold_level[pid][lvl]["kakuho"] == nil ||
            $threshold_level[pid][lvl]["kakuho"].size < 1
           next
        end
        # 組み合わせ雨量による判定
        get_scale_r6h(pid,lvl,fti,justtime)
      else
        if $threshold_level[pid][lvl]["forecast"] == nil ||
            $threshold_level[pid][lvl]["forecast"]["compass"] == nil ||
            $threshold_level[pid][lvl]["forecast"]["compass"].size < 1
           next
        end
      end
      # 3時間、24時間雨量による判定
      get_scale_3h_24h(pid,lvl,fti,justtime,p3h,p24h)
    }
  }
end
