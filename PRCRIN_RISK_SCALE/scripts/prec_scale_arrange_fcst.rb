#
# エリア内用乱高下防止処理モジュール
#
# 乱高下防止処理用スケールの前回値のスプール
# [pointid][FT]["keep_count"] = keep_count
# [pointid][FT]["out"] = INDEX_rain
# [pointid][FT]["index_type"] = index_type
$scale_ft_prev = nil

# ---------------------
# 60分継続処理 Ver. 1.7
# ---------------------
# 生スケールが前10分で出力されたスケールと比べて下がる場合について、
# FT3以上の場合：
# 生スケールが前10分で出力されたスケールから下がる場合は、
# 前10分で出力されたスケールを60分間維持するが、
# 前10分で出力されたスケールが時間雨量、
# もしくは組み合わせ雨量による条件で変化している場合には60分間維持しない。
# （3時間積算雨量/24時間積算雨量による条件でレベルが変化している場合のみに60分間維持を行う）
# ただし、スケールの維持期間中において、スケールが上がる場合は、維持期間を終了し、そのスケールを採用する。
# また、維持期間が終わった後は、どんなスケールでもそのスケールを採用する。
def keep_60min_fcst(pointid,k,ref_ft)
  # 60分間スケールが維持されているか
  prv_scale = -1
  over_60min = true
  keep_count = -1
  index_type = -1
  keep_2 = $config["ft12_keep_time_2"] / 10
  begin
    prv_scale = $scale_ft_prev[pointid][k]["out"]
    keep_count = $scale_ft_prev[pointid][k]["keep_count"]
    index_type = $scale_ft_prev[pointid][k]["index_type"]
#    print "FT%d before keep_60min keep_count=%s\n" % [k,$scale_ft_prev[pointid][k]["keep_count"]]
#    print "FT%d before keep_60min index_type=%s\n" % [k,$scale_ft_prev[pointid][k]["index_type"]]
  rescue
    print "pointid=%s ft=%d preivious data not exist.\n" % [pointid,k]
  end
  if prv_scale <= 0
    # 前回スケールなし
#    print "path 0\n"
    if ref_ft["INDEX_rain_inner"] > 0
      # 今回スケールあり
      # 今回スケールが前回スケールよりアップしたとみなす
      # 条件更新
      if ref_ft["INDEX_rain_name_inner"].index("3hour") != nil
        index_type = 1
      elsif ref_ft["INDEX_rain_name_inner"].index("24hour") != nil
        index_type = 2
      else
        index_type = 0
      end
      # 継続開始
      return 1,index_type
    else
      # 今回スケールなし
      return 0,0
    end
  end
  # 前回スケールあり
  if prv_scale < ref_ft["INDEX_rain_inner"]
    # 今回スケールが前回スケールよりアップ
#    print "path 1\n"
    # 条件更新
    if ref_ft["INDEX_rain_name_inner"].index("3hour") != nil
      index_type = 1
    elsif ref_ft["INDEX_rain_name_inner"].index("24hour") != nil
      index_type = 2
    else
      index_type = 0
    end
    # 継続開始
    return 1,index_type
  end
  # 今回スケールが前回スケールより下がるか同じ
  if keep_count < keep_2
    # 継続期間中
    if index_type > 0
      # 3時間積算雨量/24時間積算雨量による条件でレベルが変化
#      print "path 2\n"
      ref_ft["INDEX_rain_inner"] = prv_scale
      if keep_count < 1
        # 継続開始
        return 1,index_type
      else
        # 継続続行
        return keep_count + 1,index_type
      end
    else
      # 3時間積算雨量/24時間積算雨量以外による条件でレベルが変化
#      print "path 3\n"
      if ref_ft["INDEX_rain_inner"] <= 0
        # 今回スケールなし
        return 0,0
      end
      # 条件更新
      if ref_ft["INDEX_rain_name_inner"].index("3hour") != nil
        index_type = 1
      elsif ref_ft["INDEX_rain_name_inner"].index("24hour") != nil
        index_type = 2
      else
        index_type = 0
      end
      if prv_scale == ref_ft["INDEX_rain_inner"]
        # 今回スケールが前回スケールと同じ
        # 継続続行
        return keep_count + 1,index_type
      else
        # 今回スケールが前回スケールより下がる
        # 継続リセット
        return 1,index_type
      end
    end
  else
    # 継続期間終了
#    print "path 4\n"
    if ref_ft["INDEX_rain_inner"] <= 0
      # 今回スケールなし
      return 0,0
    end
    # 条件更新
    if ref_ft["INDEX_rain_name_inner"].index("3hour") != nil
      index_type = 1
    elsif ref_ft["INDEX_rain_name_inner"].index("24hour") != nil
      index_type = 2
    else
      index_type = 0
    end
    if prv_scale == ref_ft["INDEX_rain_inner"]
      # 今回スケールが前回スケールと同じ
      return keep_count,index_type
    else
      # 今回スケールが前回スケールより下がる
      # 継続リセット
      return 1,index_type
    end
  end
end

# 乱高下防止処理用スケールの過去値をmk2から取得
def get_mk2_scale_fcst(mkConn, announcetime)
  $scale_ft_prev = {}
  time_list = mkConn.get_time_list($config["mk2_scale_fcst_table"], announcetime - 600, announcetime - 60)
  if time_list.size < 1
    return time_list
  end
  params = []
  # FT4-FT72
  stratft = $config["scale_arrange_nowcast"] + 1
  for ft in stratft..72
    params.push(MkDataParam.new(ft, '0', time_list[0]))
  end
  element_list = [ 'INDEX_rain:INT8','keep_count:INT32','index_type:INT8' ]
  print "%s ----- start read_point fcst  -----\n" % [Time.now.to_s]
  pd = mkConn.read_point($config["mk2_scale_fcst_table"], params, $mk2_point_list, element_list)
  print "%s ----- end read_point fcst -----\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの過去値のスプール
  # [pointid][FT]["keep_count"] = keep_count
  # [pointid][FT]["out"] = INDEX_rain
  # [pointid][FT]["index_type"] = index_type
  params.each{|pm|
    index_rain = pd.get_data(pm, 'INDEX_rain')
    keep_count = pd.get_data(pm, 'keep_count')
    index_type = pd.get_data(pm, 'index_type')
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
      $scale_ft_prev[pointid][pm.ft]["index_type"] = index_type[i]
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
  # new_ft_scale[FT][pointid]["index_type"]
  new_ft_scale.each_key{|ft|
    index_rain = []
    keep_count = []
    index_type = []
    $point_id.each{|pid|
      if new_ft_scale[ft][pid] != nil
        index_rain.push(new_ft_scale[ft][pid]["out"])
        keep_count.push(new_ft_scale[ft][pid]["keep_count"])
        index_type.push(new_ft_scale[ft][pid]["index_type"])
      else
        print "%s ft=%s new data notexist.\n" % [pid,ft]
        index_rain.push(-1)
        keep_count.push(-1)
        index_type.push(-1)
      end
    }
    param = MkDataParam.new(ft, '0', announcetime)
    pd.set_data(param, "INDEX_rain:INT8", index_rain)
    pd.set_data(param, "keep_count:INT32", keep_count)
    pd.set_data(param, "index_type:INT8", index_type)
  }
  mkConn.write_point($config["mk2_scale_fcst_table"], pd)
end

# ---------------------
# 乱高下防止処理メイン 
# ---------------------
def scale_arrange_fcst(announcetime,ref,mkConn)
  # 乱高下防止処理用スケールの過去値をmk2から取得
  time_list = get_mk2_scale_fcst(mkConn, announcetime)
  if time_list.size < 1
    print "scale spool data not exist.\n"
    $scale_ft_prev = {}
  end
  # 保存用新データ
  # new_ft_scale[FT][pointid]["keep_count"]
  # new_ft_scale[FT][pointid]["out"]
  # new_ft_scale[FT][pointid]["index_type"]
  new_ft_scale = {}
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      pointid = customer_id + "-" + area_id
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      stratft = $config["scale_arrange_nowcast"] + 1
      for k in stratft...fcst_count
        if new_ft_scale[k] == nil
          new_ft_scale[k] = {}
        end
        new_ft_scale[k][pointid] = {}
        index_rain_raw = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw"]
        new_ft_scale[k][pointid]["keep_count"] = -1
        new_ft_scale[k][pointid]["out"] = index_rain_raw
        new_ft_scale[k][pointid]["index_type"] = -1
        # 現在値が欠測の場合は乱高下防止処理はスキップ
        if index_rain_raw == nil || index_rain_raw < 0
          next
        end
        # 60分継続処理
#        print "FT%d before keep_60min scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]]
        new_ft_scale[k][pointid]["keep_count"], new_ft_scale[k][pointid]["index_type"] = keep_60min_fcst(pointid, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
#        print "FT%d keep_count=%s\n" % [k,new_ft_scale[k][pointid]["keep_count"]]
#        print "FT%d index_type=%s\n" % [k,new_ft_scale[k][pointid]["index_type"]]
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
