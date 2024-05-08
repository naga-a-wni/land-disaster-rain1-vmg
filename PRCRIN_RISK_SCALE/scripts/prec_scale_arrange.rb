#
# エリア内用乱高下防止処理モジュール
#
# 乱高下防止処理用スケールの過去値のスプール
# [announced][customer_id][area_id][FT]["raw"] = INDEX_rain_raw
# [announced][customer_id][area_id][FT]["out"] = INDEX_rain
$scale_ft_all = nil

# ---------------------
# 60分継続処理 Ver. 1.7
# ---------------------
# 生スケールが前10分で出力されたスケールと比べて下がる場合について、
# FT0またはFT4以上の場合：
#  レベルにかかわらず、前10分で出力されたスケールを60分間維持する。
# FT1～FT3の場合：
#  レベルに応じて、以下の通りに前10分で出力されたスケールを維持する。
#  レベル1の場合前10分で出力されたスケールを90分間維持する
#  レベル2/レベル3/レベル4/レベル5の場合前10分で出力されたスケールを60分間維持する
# ただし、スケールの維持期間中において、スケールが上がる場合は、維持期間を終了し、そのスケールを採用する。
# また、維持期間が終わった後は、どんなスケールでもそのスケールを採用する。
def keep_60min(announcetime,customer_id,area_id,k,ref_ft)
  # 60分間スケールが維持されているか
  prv_scale = -1
  inner_type = 0
  inner_time = 0
  over_60min = true
  keep_count = 0
  keep_1 = $config["ft12_keep_time_1"] / 10
  keep_2 = $config["ft12_keep_time_2"] / 10
  1.upto(keep_1){|i|
    oldtime = announcetime - 600 * i
    if $scale_ft_all[oldtime] == nil
      over_60min = false
      break
    end
    if $scale_ft_all[oldtime][customer_id] == nil
      over_60min = false
      break
    end
    if $scale_ft_all[oldtime][customer_id][area_id] == nil
      over_60min = false
      break
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k] == nil
      over_60min = false
      break
    end
    if !$scale_ft_all[oldtime][customer_id][area_id][k].kind_of?(Hash)
      over_60min = false
      break
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k]["out"] == nil
      over_60min = false
      break
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k]["out"] < 0
      over_60min = false
      break
    end
    if i == 1
      prv_scale = $scale_ft_all[oldtime][customer_id][area_id][k]["out"]
      if k == 0
        begin
          inner_type = $scale_ft0_2[oldtime][customer_id][area_id][k]["inner_type"]
          inner_time = $scale_ft0_2[oldtime][customer_id][area_id][k]["inner_time"]
        rescue
          print "cid=%s aid=%s ft=0 inner_type not exist.\n" % [customer_id,area_id]
        end
      end
    else
      if prv_scale != $scale_ft_all[oldtime][customer_id][area_id][k]["out"]
        over_60min = false
        break
      end
    end
    keep_count = i
    if ( k == 0 || k > 3 || prv_scale > $config["ft12_keep_level_1"] ) && i >= keep_2
      break
    end
  }
#  print "cid=%s aid=%s ft=%d keep_count=%s\n" % [customer_id,area_id,k,keep_count]
  if prv_scale < 0
#    print "keep_60min cid=%s aid=%s ft=%d scale=%s previous scale is lack value.\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
    return nil
  end
  if prv_scale <= ref_ft["INDEX_rain_inner"]
#    print "keep_60min up or equal cid=%s aid=%s ft=%d scale=%s prv_scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"],prv_scale]
    return [prv_scale,inner_type,inner_time]
  end
  if over_60min
    print "keep_60min over cid=%s aid=%s ft=%d keep_count=%s scale=%s prv_scale=%s\n" % [customer_id,area_id,k,keep_count,ref_ft["INDEX_rain_inner"],prv_scale]
    if k > 3
      return nil
    end
    if k == 0
      # ft=0について、スケールの60分維持期間が終わった後のレベル維持条件を変更する。
      # スケールの維持期間が終わった後、以下の条件に該当する場合には、レベルを維持する。
      # ・60分雨量でレベルが上がっている場合には、該当レベルの60分雨量の基準値の50%以上の雨量が観測されている場合
      # ・組み合わせ雨量(60分雨量and連続量)でレベルが上がっている場合には、該当レベルの組み合わせ雨量の基準値のうちの60分雨量の50%以上の雨量が観測されている場合
      if inner_type == 1 || inner_type == 2
        print "cid=%s aid=%s ft=%s inner_type=%s\n" % [customer_id,area_id,k,inner_type]
        pid = customer_id + "-" + area_id
        if $threshold_level[pid] == nil || $threshold_level[pid][prv_scale] == nil
          print "threshold data not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
        else
          ref_60min = nil
          ref_combine = nil
          threshold_60min = nil
          threshold_combine_60min = nil
          value_60min = nil
          if $threshold_level[pid][prv_scale]["observation"] != nil
            ref_60min = $threshold_level[pid][prv_scale]["observation"]["micronet"]
            ref_combine = ref_60min
          end
          if ref_60min != nil && ref_60min["PRCRIN_60min"] != nil && ref_60min["PRCRIN_60min"] != ""
            threshold_60min = ref_60min["PRCRIN_60min"] * $config["keep_level_60"]
            print "PRCRIN_60min=%s\n" % [ref_60min["PRCRIN_60min"]]
          end
          if ref_combine != nil && ref_combine["PRCRIN_combine_PRST"] != nil && ref_combine["PRCRIN_combine_PRST"] != "" &&
              ref_combine["PRCRIN_combine_60min"] != nil && ref_combine["PRCRIN_combine_60min"] != ""
            threshold_combine_60min = ref_combine["PRCRIN_combine_60min"] * $config["keep_level_combine_60"]
            print "PRCRIN_combine_60min=%s\n" % [ref_combine["PRCRIN_combine_60min"]]
          end
          if threshold_60min != nil || threshold_combine_60min != nil
            for i in 0...ref_ft["point_count"]
              if ref_ft["POINT"][i]["point_id"] == "compass"
                next
              end
              for j in 0...ref_ft["POINT"][i]["ELM_count"]
                if ref_ft["POINT"][i]["ELM"][j]["name"] == "PRCRIN_60min"
                  if value_60min == nil || value_60min < ref_ft["POINT"][i]["ELM"][j]["value"]
                    value_60min = ref_ft["POINT"][i]["ELM"][j]["value"]
                  end
                end
              end
            end
            print "threshold_60min=%s threshold_combine_60min=%s value_60min=%s\n" % [threshold_60min,threshold_combine_60min,value_60min]
            if value_60min != nil
              if inner_type == 1
                if threshold_60min != nil && threshold_60min <= value_60min
                  ref_ft["INDEX_rain_inner"] = prv_scale
                  print "continue keep scale scale=%s prv_scale=%s\n" % [ref_ft["INDEX_rain_inner"],prv_scale]
                end
              elsif inner_type == 2
                if threshold_combine_60min != nil && threshold_combine_60min <= value_60min
                  ref_ft["INDEX_rain_inner"] = prv_scale
                  print "continue keep scale scale=%s prv_scale=%s\n" % [ref_ft["INDEX_rain_inner"],prv_scale]
                end
              end
            end
          end
        end
      end
    else
      # FT1～FT3の場合で、スケールの維持期間が終わった後、
      #   設定されている地点で観測されている雨量、もしくは予測されている雨量が以下の条件を満たす場合には、出力スケールを維持する。
      #   a）出力されているレベルの基準値として設定されている60分雨量の50%以上の雨量が観測されている場合、もしくは予測されている場合
      #   b）出力されているレベルの基準値として設定されている組み合わせ雨量の60分雨量の50%以上の雨量が観測されている場合、もしくは予測されている場合
      pid = customer_id + "-" + area_id
      if $threshold_level[pid] == nil || $threshold_level[pid][prv_scale] == nil
        print "threshold data not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
      else
        ref_60min = nil
        ref_combine = nil
        threshold_60min = nil
        threshold_combine_60min = nil
        value_60min = nil
        if k == 0
          if $threshold_level[pid][prv_scale]["observation"] != nil
            ref_60min = $threshold_level[pid][prv_scale]["observation"]["micronet"]
            ref_combine = ref_60min
          end
        else
          if $threshold_level[pid][prv_scale]["kakuho"] != nil
            ref_60min = $threshold_level[pid][prv_scale]["kakuho"]["kakuho"]
            ref_combine = $threshold_level[pid][prv_scale]["kakuho"]["micronet"]
          end
        end
        if ref_60min != nil && ref_60min["PRCRIN_60min"] != nil && ref_60min["PRCRIN_60min"] != ""
          threshold_60min = ref_60min["PRCRIN_60min"] * $config["keep_level_60"]
          print "PRCRIN_60min=%s\n" % [ref_60min["PRCRIN_60min"]]
        end
        if ref_combine != nil && ref_combine["PRCRIN_combine_PRST"] != nil && ref_combine["PRCRIN_combine_PRST"] != "" &&
            ref_combine["PRCRIN_combine_60min"] != nil && ref_combine["PRCRIN_combine_60min"] != ""
          threshold_combine_60min = ref_combine["PRCRIN_combine_60min"] * $config["keep_level_combine_60"]
          print "PRCRIN_combine_60min=%s\n" % [ref_combine["PRCRIN_combine_60min"]]
        end
        if threshold_60min != nil || threshold_combine_60min != nil
          for i in 0...ref_ft["point_count"]
            if ref_ft["POINT"][i]["point_id"] == "compass"
              next
            end
            for j in 0...ref_ft["POINT"][i]["ELM_count"]
              if ref_ft["POINT"][i]["ELM"][j]["name"] == "PRCRIN_60min"
                if value_60min == nil || value_60min < ref_ft["POINT"][i]["ELM"][j]["value"]
                  value_60min = ref_ft["POINT"][i]["ELM"][j]["value"]
                end
              end
            end
          end
          print "threshold_60min=%s threshold_combine_60min=%s value_60min=%s\n" % [threshold_60min,threshold_combine_60min,value_60min]
          if value_60min != nil
            if threshold_60min != nil && threshold_60min <= value_60min
              ref_ft["INDEX_rain_inner"] = prv_scale
              print "continue keep scale scale=%s prv_scale=%s\n" % [ref_ft["INDEX_rain_inner"],prv_scale]
            elsif threshold_combine_60min != nil && threshold_combine_60min <= value_60min
              ref_ft["INDEX_rain_inner"] = prv_scale
              print "continue keep scale scale=%s prv_scale=%s\n" % [ref_ft["INDEX_rain_inner"],prv_scale]
            end
          end
        end
      end
    end
    return [prv_scale,inner_type,inner_time]
  end
  ref_ft["INDEX_rain_inner"] = prv_scale
#  print "keep_60min keep cid=%s aid=%s ft=%d scale=%s prv_scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"],prv_scale]
  return [prv_scale,inner_type,inner_time]
end

# -----------------------
# 乱高下防止処理(FT1-3)：
# -----------------------
# ① 生スケールがレベル2以上の場合で、且つ過去20分以内に生スケール2以下がある場合は、
# （直近＋1更新前）/2の四捨五入とする
# ex）レベルX→2→4の場合  (4＋2)/2＝3で「3」となる
# ex）レベルX⇒0⇒2の場合  (2＋0)/2＝1で「1」となる
# ➁直近の生スケールがレベル1の場合で、かつ過去20分以内の生スケールにレベル0がある場合は、レベル0とする。
# ex）レベルX⇒0⇒1の場合  レベル0となる
# ③ 2更新以内の生スケールがレベル3以上で且つ直近の生スケールがレベル2以下の場合は、
# （直近＋1更新前＋2更新前）/3の四捨五入とする
# ex)レベル3→3→2    （2＋3＋3）/3≒2.67で「3」となる
# レベル5→3→0    （0＋3＋5）/3≒2.67で「3」となる
def arrange_ft_1_2(announcetime, annary, customer_id, area_id, k, ref_ft)
  index_rain_raw = ref_ft["INDEX_rain_raw"]
  # 過去値を見る処理
  if annary != nil && annary.size > 0
    arrange = true
    if annary[0] != announcetime - 600
      arrange = false
    end
    # 1つ前のnil、欠測チェック
    if arrange && $scale_ft_all[annary[0]] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[0]][customer_id] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[0]][customer_id][area_id] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[0]][customer_id][area_id][k] == nil
      arrange = false
    end
    if arrange && !$scale_ft_all[annary[0]][customer_id][area_id][k].kind_of?(Hash)
      arrange = false
    end
    if arrange && $scale_ft_all[annary[0]][customer_id][area_id][k]["raw"] == nil
#      print "arrange_ft_1_2 cid=%s aid=%s ft=%s scale not exist.\n" % [customer_id,area_id,annary[0].to_s]
      arrange = false
    end
    if arrange && $scale_ft_all[annary[0]][customer_id][area_id][k]["raw"] < 0
#      print "arrange_ft_1_2 cid=%s aid=%s ft=%s scale is lack value.\n" % [customer_id,area_id,annary[0].to_s]
      arrange = false
    end
    # 2つ前のnil、欠測チェック
    if arrange && annary[1] != announcetime - 600 * 2
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]][customer_id] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]][customer_id][area_id] == nil
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]][customer_id][area_id][k] == nil
      arrange = false
    end
    if arrange && !$scale_ft_all[annary[1]][customer_id][area_id][k].kind_of?(Hash)
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]][customer_id][area_id][k]["raw"] == nil
#      print "arrange_ft_1_2 cid=%s aid=%s ft=%s scale not exist.\n" % [customer_id,area_id,annary[1].to_s]
      arrange = false
    end
    if arrange && $scale_ft_all[annary[1]][customer_id][area_id][k]["raw"] < 0
#      print "arrange_ft_1_2 cid=%s aid=%s ft=%s scale is lack value.\n" % [customer_id,area_id,annary[1].to_s]
      arrange = false
    end
    if arrange
      bf_2 = $scale_ft_all[annary[1]][customer_id][area_id][k]["raw"]
      bf_1 = $scale_ft_all[annary[0]][customer_id][area_id][k]["raw"]
      if index_rain_raw >= 2 && (bf_1 <= 2 || bf_2 <= 2)
        # ① 生スケールがレベル2以上の場合で、且つ過去20分以内に生スケール2以下がある場合は（直近＋1更新前）/2の四捨五入とする
        avg = (index_rain_raw + bf_1) / 2.0
        ref_ft["INDEX_rain_inner"] = avg.round
        print "cid=%s aid=%s ft=%d org scale=%s\n" % [customer_id,area_id,k,index_rain_raw]
        print "No.1 bf_2=%s bf_1=%s new scale=%s\n" % [bf_2,bf_1,ref_ft["INDEX_rain_inner"]]
        return true
      elsif index_rain_raw == 1 && (bf_1 == 0 || bf_2 == 0)
        # ➁直近の生スケールがレベル1の場合で、かつ過去20分以内の生スケールにレベル0がある場合は、レベル0とする。
        ref_ft["INDEX_rain_inner"] = 0
        print "cid=%s aid=%s ft=%d org scale=%s\n" % [customer_id,area_id,k,index_rain_raw]
        print "No.2 bf_2=%s bf_1=%s new scale=%s\n" % [bf_2,bf_1,ref_ft["INDEX_rain_inner"]]
        return true
      elsif index_rain_raw <= 2 && (bf_1 >= 3 || bf_2 >= 3)
        # ③ 過去20分以内の生スケールにレベル3以上がある場合で、且つ直近の生スケールがレベル2以下の場合は（直近＋1更新前＋2更新前）/3の四捨五入とする
        avg = (index_rain_raw + bf_1 + bf_2) / 3.0
        ref_ft["INDEX_rain_inner"] = avg.round
        print "cid=%s aid=%s ft=%d org scale=%s\n" % [customer_id,area_id,k,index_rain_raw]
        print "No.3 bf_2=%s bf_1=%s new scale=%s\n" % [bf_2,bf_1,ref_ft["INDEX_rain_inner"]]
        return true
      end
    else
#      print "arrange_ft_1_2 cid=%s aid=%s ft=%d skpped.\n" % [customer_id,area_id,k]
    end
  end
  return false
end

# 乱高下防止処理用スケールの過去値をmk2から取得
def get_mk2_scale(mkConn, announcetime)
  $scale_ft_all = {}
  time_list = mkConn.get_time_list($config["mk2_scale_table"], announcetime - $config["ft12_keep_time_1"] * 60, announcetime - 600)
  if time_list.size < 1
    return time_list
  end
  params = []
  time_list.each{|btime|
    # FT0-FT3だけ
    for ft in 0..$config["scale_arrange_nowcast"]
      params.push(MkDataParam.new(ft, '0', btime))
    end
  }
  element_list = [ 'INDEX_rain:INT8','INDEX_rain_raw:INT8' ]
  print "%s ----- start read_point  -----\n" % [Time.now.to_s]
  pd = mkConn.read_point($config["mk2_scale_table"], params, $mk2_point_list, element_list)
  print "%s ----- end read_point -----\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの過去値のスプール
  # [announced][customer_id][area_id][FT]["raw"] = INDEX_rain_raw
  # [announced][customer_id][area_id][FT]["out"] = INDEX_rain
  params.each{|pm|
    index_rain = pd.get_data(pm, 'INDEX_rain')
    index_rain_raw = pd.get_data(pm, 'INDEX_rain_raw')
    if $scale_ft_all[pm.time] == nil
      $scale_ft_all[pm.time] = {}
    end
    $point_id.each_index{|i|
      pointid = $point_id[i].split("-")
      if $scale_ft_all[pm.time][pointid[0]] == nil
        $scale_ft_all[pm.time][pointid[0]] = {}
      end
      if $scale_ft_all[pm.time][pointid[0]][pointid[1]] == nil
        $scale_ft_all[pm.time][pointid[0]][pointid[1]] = {}
      end
      if $scale_ft_all[pm.time][pointid[0]][pointid[1]][pm.ft] == nil
        $scale_ft_all[pm.time][pointid[0]][pointid[1]][pm.ft] = {}
      end
      $scale_ft_all[pm.time][pointid[0]][pointid[1]][pm.ft]["out"] = index_rain[i]
      $scale_ft_all[pm.time][pointid[0]][pointid[1]][pm.ft]["raw"] = index_rain_raw[i]
    }
  }
#  p $scale_ft_all
  print "%s ----- end get_mk2_scale -----\n" % [Time.now.to_s]
  return time_list
end

# 乱高下防止処理用スケールの現在値をmk2に保存
def set_mk2_scale(mkConn, announcetime, new_ft_scale)
  pd = MkPointData.new
#  p new_ft_scale
  pd.set_point_list($mk2_point_list)
  # 保存用新データ
  # new_ft_scale[FT][pointid]["raw"]
  # new_ft_scale[FT][pointid]["out"]
  new_ft_scale.each_key{|ft|
    index_rain = []
    index_rain_raw = []
    $point_id.each{|pid|
      if new_ft_scale[ft][pid] != nil
        index_rain.push(new_ft_scale[ft][pid]["out"])
        index_rain_raw.push(new_ft_scale[ft][pid]["raw"])
      else
        print "%s ft=%s new data notexist.\n" % [pid,ft]
        index_rain.push(-1)
        index_rain_raw.push(-1)
      end
    }
    param = MkDataParam.new(ft, '0', announcetime)
    pd.set_data(param, "INDEX_rain:INT8", index_rain)
    pd.set_data(param, "INDEX_rain_raw:INT8", index_rain_raw)
  }
  mkConn.write_point($config["mk2_scale_table"], pd)
  pdn = MkPointData.new
  pdn.set_point_list($mk2_point_list)
  # FT0の判定フラグ
  # new_ft_scale[0][pointid]["inner_type"]
  # new_ft_scale[0][pointid]["inner_time"]
  inner_type = []
  inner_time = []
  $point_id.each{|pid|
    if new_ft_scale[0][pid] != nil
      inner_type.push(new_ft_scale[0][pid]["inner_type"])
      inner_time.push(new_ft_scale[0][pid]["inner_time"])
    else
      print "%s ft=0 new inner flag data not exist.\n" % [pid]
      inner_type.push(-1)
      inner_time.push(-1)
    end
  }
  # FT0だけ
  param = MkDataParam.new(0, '0', announcetime)
  pdn.set_data(param, "inner_type:INT8", inner_type)
  pdn.set_data(param, "inner_time:INT32", inner_time)
  mkConn.write_point($config["mk2_scale_near_table"], pdn)
end

# ---------------------
# 乱高下防止処理メイン 
# ---------------------
def scale_arrange(announcetime,ref,mkConn)
#  print "scale_arrange 1 %s\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの過去値をmk2から取得
  time_list = get_mk2_scale(mkConn, announcetime)
  annary = nil
  if time_list.size < 1
    print "scale spool data not exist.\n"
    $scale_ft_all = {}
  else
    annary = time_list.reverse
  end
#  p $ft0_judge_type
#  print "scale_arrange 2 %s\n" % [Time.now.to_s]
  # 保存用新データ
  # new_ft_scale[FT][pointid]["raw"]
  # new_ft_scale[FT][pointid]["out"]
  # new_ft_scale[FT][pointid]["inner_type"]
  # new_ft_scale[FT][pointid]["inner_time"]
  new_ft_scale = {}
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      pointid = customer_id + "-" + area_id
      for k in 0..$config["scale_arrange_nowcast"]
        if new_ft_scale[k] == nil
          new_ft_scale[k] = {}
        end
        new_ft_scale[k][pointid] = {}
        index_rain_raw = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw"]
        new_ft_scale[k][pointid]["raw"] = index_rain_raw
        new_ft_scale[k][pointid]["out"] = index_rain_raw
        # 現在値が欠測の場合は乱高下防止処理はスキップ
        if index_rain_raw == nil || index_rain_raw < 0
#          print "FT=%d raw scale=%s\n" % [k,index_rain_raw]
#          print "input scale invalid\n"
          next
        end
#        print "%s FT=%d raw scale=%s\n" % [announcetime.to_s,k,index_rain_raw]
        if k > 0 && k < 4
          # ----------------------
          # 乱高下防止処理(FT1-3) 
          # ----------------------
          arrange = arrange_ft_1_2(announcetime, annary, customer_id, area_id, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
          if arrange
            # ----------------
            # 空箱処理(FT1-3) 
            # ----------------
            empty_box(announcetime, customer_id, area_id, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
          end
        end
        # 60分継続処理
#        print "FT%d before keep_60min scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]]
        prv_data = keep_60min(announcetime, customer_id, area_id, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
        new_ft_scale[k][pointid]["out"] = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]
#        print "FT%d output scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]]
        # FT0の判定フラグ
        if k == 0
          if prv_data != nil
#            p 1
            # 前回データあり
            if new_ft_scale[k][pointid]["out"] > prv_data[0]
#              p 3
              # 今回スケールが前回スケールよりアップした
              if $ft0_judge_type[customer_id] != nil &&  $ft0_judge_type[customer_id][area_id] != nil
                # 今回判定フラグあり
#                p 4
                new_ft_scale[k][pointid]["inner_type"] = $ft0_judge_type[customer_id][area_id]["inner_type"]
                new_ft_scale[k][pointid]["inner_time"] = announcetime.to_i
              else
                # 今回のフラグがない→上がった原因不明→フラグは0
#                p 5
                new_ft_scale[k][pointid]["inner_type"] = 0
                new_ft_scale[k][pointid]["inner_time"] = announcetime.to_i
              end
            else
#              p 6
              # 今回スケールが前回スケールより上がらない→前回値引継ぎ
              new_ft_scale[k][pointid]["inner_type"] = prv_data[1]
              new_ft_scale[k][pointid]["inner_time"] = prv_data[2]
            end
          else
#            p 2
            # 前回データなし
            if new_ft_scale[k][pointid]["out"] > 0
#              p 7
              # 今回スケールが前回スケールよりアップしたとみなす
              if $ft0_judge_type[customer_id] != nil &&  $ft0_judge_type[customer_id][area_id] != nil
                # 今回判定フラグあり
#                p 8
                new_ft_scale[k][pointid]["inner_type"] = $ft0_judge_type[customer_id][area_id]["inner_type"]
                new_ft_scale[k][pointid]["inner_time"] = announcetime.to_i
              else
                # 今回のフラグがない→上がった原因不明→フラグは0
#                p 9
                new_ft_scale[k][pointid]["inner_type"] = 0
                new_ft_scale[k][pointid]["inner_time"] = announcetime.to_i
              end
            else
#              p 10
              # 今回スケールが前回スケールより上がらない→リセット
              new_ft_scale[k][pointid]["inner_type"] = 0
              new_ft_scale[k][pointid]["inner_time"] = 0
            end
          end
        end
      end
    end
  end
#  print "scale_arrange 3 %s\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの現在値をmk2に保存
  set_mk2_scale(mkConn, announcetime, new_ft_scale)
#  print "scale_arrange 4 %s\n" % [Time.now.to_s]
end
