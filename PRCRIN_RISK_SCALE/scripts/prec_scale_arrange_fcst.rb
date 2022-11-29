#
# エリア内用乱高下防止処理モジュール
#
# 乱高下防止処理用スケールの前回値のスプール
# [pointid][FT]["keep_count"] = keep_count
# [pointid][FT]["out"] = INDEX_rain
$scale_ft_prev = nil

# ---------------------
# 60分継続処理 Ver. 1.7
# ---------------------
# 生スケールが前10分で出力されたスケールと比べて下がる場合について、
# FT4以上の場合：
# レベルにかかわらず、前10分で出力されたスケールを60分間維持する。
# ただし、スケールの維持期間中において、スケールが上がる場合は、維持期間を終了し、そのスケールを採用する。
# また、維持期間が終わった後は、どんなスケールでもそのスケールを採用する。
def keep_60min_fcst(pointid,k,ref_ft)
  # 60分間スケールが維持されているか
  prv_scale = -1
  over_60min = true
  keep_count = -1
  keep_2 = $config["ft12_keep_time_2"] / 10
  begin
    prv_scale = $scale_ft_prev[pointid][k]["out"]
    keep_count = $scale_ft_prev[pointid][k]["keep_count"]
  rescue
    print "pointid=%s ft=%d preivious data not exist.\n" % [pointid,k]
  end
#  print "pointid=%s ft=%d keep_count=%s\n" % [pointid,k,keep_count]
  if prv_scale < 0
#    print "keep_60min pointid=%s ft=%d scale=%s previous scale is lack value.\n" % [pointid,k,ref_ft["INDEX_rain_inner"]]
    return 1
  end
  if prv_scale < ref_ft["INDEX_rain_inner"]
#    print "keep_60min up pointid=%s ft=%d scale=%s prv_scale=%s\n" % [pointid,k,ref_ft["INDEX_rain_inner"],prv_scale]
    return 1
  end
  if keep_count < keep_2
#    print "keep_60min keep pointid=%s ft=%d scale=%s prv_scale=%s\n" % [pointid,k,ref_ft["INDEX_rain_inner"],prv_scale]
    ref_ft["INDEX_rain_inner"] = prv_scale
    if keep_count < 1
      return 1
    else
      return keep_count + 1
    end
  end
#  print "keep_60min over 60min pointid=%s ft=%d scale=%s prv_scale=%s\n" % [pointid,k,ref_ft["INDEX_rain_inner"],prv_scale]
  return keep_count
end

# 乱高下防止処理用スケールの過去値をmk2から取得
def get_mk2_scale_fcst(mkConn, announcetime)
  $scale_ft_prev = {}
  time_list = mkConn.get_time_list($config["mk2_scale_fcst_table"], announcetime - 600, announcetime)
  if time_list.size < 1
    return time_list
  end
  params = []
  # FT4-FT72
  for ft in 4..72
    params.push(MkDataParam.new(ft, '0', time_list[0]))
  end
  element_list = [ 'INDEX_rain:INT8','keep_count:INT32' ]
  print "%s ----- start read_point fcst  -----\n" % [Time.now.to_s]
  pd = mkConn.read_point($config["mk2_scale_fcst_table"], params, $mk2_point_list, element_list)
  print "%s ----- end read_point fcst -----\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの過去値のスプール
  # [pointid][FT]["keep_count"] = keep_count
  # [pointid][FT]["out"] = INDEX_rain
  params.each{|pm|
    index_rain = pd.get_data(pm, 'INDEX_rain')
    keep_count = pd.get_data(pm, 'keep_count')
    $point_id.each_index{|i|
      pointid = $point_id[i]
      if $scale_ft_prev[pointid] == nil
        $scale_ft_prev[pointid] = {}
      end
      if $scale_ft_prev[pointid][pm.ft] == nil
        $scale_ft_prev[pointid][pm.ft] = {}
      end
      $scale_ft_prev[pointid][pm.ft]["out"] = index_rain[i]
      $scale_ft_prev[pointid][pm.ft]["keep_count"] = keep_count[i]
    }
  }
#  p $scale_ft_prev
  print "%s ----- end get_mk2_scale_fcst -----\n" % [Time.now.to_s]
  return time_list
end

# 乱高下防止処理用スケールの現在値をmk2に保存
def set_mk2_scale_fcst(mkConn, announcetime, new_ft_scale)
  pd = MkPointData.new
#  p new_ft_scale
  pd.set_point_list($mk2_point_list)
  # 保存用新データ
  # new_ft_scale[FT][pointid]["keep_count"]
  # new_ft_scale[FT][pointid]["out"]
  new_ft_scale.each_key{|ft|
    index_rain = []
    keep_count = []
    $point_id.each{|pid|
      if new_ft_scale[ft][pid] != nil
        index_rain.push(new_ft_scale[ft][pid]["out"])
        keep_count.push(new_ft_scale[ft][pid]["keep_count"])
      else
        print "%s ft=%s new data notexist.\n" % [pid,ft]
        index_rain.push(-1)
        keep_count.push(-1)
      end
    }
    param = MkDataParam.new(ft, '0', announcetime)
    pd.set_data(param, "INDEX_rain:INT8", index_rain)
    pd.set_data(param, "keep_count:INT32", keep_count)
  }
  mkConn.write_point($config["mk2_scale_fcst_table"], pd)
end

# ---------------------
# 乱高下防止処理メイン 
# ---------------------
def scale_arrange_fcst(announcetime,ref,mkConn)
  # 乱高下防止処理用スケールの過去値をmk2から取得
  time_list = get_mk2_scale_fcst(mkConn, announcetime)
  annary = nil
  if time_list.size < 1
    print "scale spool data not exist.\n"
    $scale_ft_prev = {}
  else
    annary = time_list.reverse
  end
  # 保存用新データ
  # new_ft_scale[FT][pointid]["keep_count"]
  # new_ft_scale[FT][pointid]["out"]
  new_ft_scale = {}
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      pointid = customer_id + "-" + area_id
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      for k in 4...fcst_count
        if new_ft_scale[k] == nil
          new_ft_scale[k] = {}
        end
        new_ft_scale[k][pointid] = {}
        index_rain_raw = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw"]
        new_ft_scale[k][pointid]["keep_count"] = -1
        new_ft_scale[k][pointid]["out"] = index_rain_raw
        # 現在値が欠測の場合は乱高下防止処理はスキップ
        if index_rain_raw == nil || index_rain_raw < 0
          next
        end
        # 60分継続処理
#        print "FT%d before keep_60min scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]]
        new_ft_scale[k][pointid]["keep_count"] = keep_60min_fcst(pointid, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
        new_ft_scale[k][pointid]["out"] = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]
#        print "FT%d output scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]]
      end
    end
  end
#  print "scale_arrange 3 %s\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの現在値をmk2に保存
  set_mk2_scale_fcst(mkConn, announcetime, new_ft_scale)
#  print "scale_arrange 4 %s\n" % [Time.now.to_s]
end
