#
# 周辺地域用乱高下防止処理モジュール
#
# FT0の乱高下防止処理用の過去値のスプール
# [announced][customer_id][area_id][FT]["raw"] = INDEX_rain_raw_near
# [announced][customer_id][area_id][FT]["out"] = INDEX_rain_near
# [announced][customer_id][area_id][FT]["near_type"] = 1 1:60分雨量
# [announced][customer_id][area_id][FT]["near_time"] = up time
# [announced][customer_id][area_id][FT]["inner_type"] = 1|2 1:60分雨量 2:組み合わせ雨量
# [announced][customer_id][area_id][FT]["inner_time"] = up time
$scale_ft0_2 = nil

# ---------------------
# 60分継続処理 Ver. 1.7
# ---------------------
# 生スケールが前10分で出力されたスケールと比べて下がる場合について、
# レベルにかかわらず、前10分で出力されたスケールを60分間維持する。
def keep_60min_0(announcetime,customer_id,area_id,k,ref_ft)
  # 60分間スケールが維持されているか
  prv_scale = -1
  near_type = 0
  near_time = 0
  over_60min = true
  keep_count = 0
  keep_2 = $config["ft12_keep_time_2"] / 10
  1.upto(keep_2){|i|
    oldtime = announcetime - 600 * i
    if $scale_ft0_2[oldtime] == nil
      over_60min = false
      break
    end
    if $scale_ft0_2[oldtime][customer_id] == nil
      over_60min = false
      break
    end
    if $scale_ft0_2[oldtime][customer_id][area_id] == nil
      over_60min = false
      break
    end
    if $scale_ft0_2[oldtime][customer_id][area_id][k] == nil
      over_60min = false
      break
    end
    if !$scale_ft0_2[oldtime][customer_id][area_id][k].kind_of?(Hash)
      over_60min = false
      break
    end
    if $scale_ft0_2[oldtime][customer_id][area_id][k]["out"] == nil
      over_60min = false
      break
    end
    if $scale_ft0_2[oldtime][customer_id][area_id][k]["out"] < 0
      over_60min = false
      break
    end
    if i == 1
      prv_scale = $scale_ft0_2[oldtime][customer_id][area_id][k]["out"]
      near_type = $scale_ft0_2[oldtime][customer_id][area_id][k]["near_type"]
      near_time = $scale_ft0_2[oldtime][customer_id][area_id][k]["near_time"]
    else
      if prv_scale != $scale_ft0_2[oldtime][customer_id][area_id][k]["out"]
        over_60min = false
        break
      end
    end
    keep_count = i
  }
#  print "cid=%s aid=%s ft=%d keep_count=%s\n" % [customer_id,area_id,k,keep_count]
  if prv_scale < 0
#    print "keep_60min cid=%s aid=%s ft=%d scale=%s previous scale is lack value.\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
    return nil
  end
  if prv_scale <= ref_ft["INDEX_rain_near"]
#    print "keep_60min up or equal cid=%s aid=%s ft=%d scale=%s prv_scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"],prv_scale]
    return [prv_scale,near_type,near_time]
  end
  if over_60min
    print "keep_60min over cid=%s aid=%s ft=%d keep_count=%s scale=%s prv_scale=%s\n" % [customer_id,area_id,k,keep_count,ref_ft["INDEX_rain_near"],prv_scale]
    # スケールの維持期間が終わった後、以下の条件に該当する場合には、レベルを維持する。
    # ・60分雨量でレベルが上がっている場合には、該当レベルの60分雨量の基準値の50%以上の雨量が観測されている場合
    if near_type == 1
      print "cid=%s aid=%s ft=%s near_type=%s\n" % [customer_id,area_id,k,near_type]
      pid = customer_id + "-" + area_id
      if $threshold_level_near[pid] == nil || $threshold_level_near[pid][prv_scale] == nil
        print "threshold data not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_near"]]
      else
        # レベルの次は配列
        $threshold_level_near[pid][prv_scale].each_index{|j|
          threshold_60min = nil
          value_60min = nil
          ref_60min = $threshold_level_near[pid][prv_scale][j]
          if ref_60min["NEAR_PRCRIN_60min"] != nil && ref_60min["NEAR_PRCRIN_60min"] != ""
            threshold_60min = ref_60min["NEAR_PRCRIN_60min"] * $config["keep_level_60"]
            print "PRCRIN_60min=%s\n" % [ref_60min["NEAR_PRCRIN_60min"]]
          end
          if threshold_60min != nil
            for i in 0...ref_ft["point_count"]
              if ref_ft["POINT"][i]["point_id"] == "compass" || ref_ft["POINT"][i]["point_id"] == "kakuho"
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
            print "threshold_60min=%s value_60min=%s\n" % [threshold_60min,value_60min]
            if value_60min != nil
              if threshold_60min != nil && threshold_60min <= value_60min
                ref_ft["INDEX_rain_near"] = prv_scale
                print "continue keep scale scale=%s prv_scale=%s\n" % [ref_ft["INDEX_rain_near"],prv_scale]
                break
              end
            end
          end
        }
      end
    end
    return [prv_scale,near_type,near_time]
  end
  ref_ft["INDEX_rain_near"] = prv_scale
  return [prv_scale,near_type,near_time]
end

# 乱高下防止処理用スケールの過去値をmk2から取得
def get_mk2_scale_0(mkConn, announcetime)
  $scale_ft0_2 = {}
  time_list = mkConn.get_time_list($config["mk2_scale_near_table"], announcetime - $config["ft12_keep_time_2"] * 60, announcetime)
  if time_list.size < 1
    return time_list
  end
  params = []
  time_list.each{|btime|
    # FT0だけ
    params.push(MkDataParam.new(0, '0', btime))
  }
  element_list = [ 'INDEX_rain_near:INT8','INDEX_rain_raw_near:INT8','near_type:INT8','near_time:INT32','inner_type:INT8','inner_time:INT32' ]
  pd = mkConn.read_point($config["mk2_scale_near_table"], params, $mk2_point_list, element_list)
  # FT0の乱高下防止処理用の過去値のスプール
  # [announced][customer_id][area_id][FT]["raw"] = INDEX_rain_raw_near
  # [announced][customer_id][area_id][FT]["out"] = INDEX_rain_near
  # [announced][customer_id][area_id][FT]["near_type"] = 1 1:60分雨量
  # [announced][customer_id][area_id][FT]["near_time"] = up time
  # [announced][customer_id][area_id][FT]["inner_type"] = 1|2 1:60分雨量 2:組み合わせ雨量
  # [announced][customer_id][area_id][FT]["inner_time"] = up time
  params.each{|pm|
    index_rain = pd.get_data(pm, 'INDEX_rain_near')
    index_rain_raw = pd.get_data(pm, 'INDEX_rain_raw_near')
    near_type = pd.get_data(pm, 'near_type')
    near_time = pd.get_data(pm, 'near_time')
    inner_type = pd.get_data(pm, 'inner_type')
    inner_time = pd.get_data(pm, 'inner_time')
    if $scale_ft0_2[pm.time] == nil
      $scale_ft0_2[pm.time] = {}
    end
    $point_id.each_index{|i|
      pointid = $point_id[i].split("-")
      if $scale_ft0_2[pm.time][pointid[0]] == nil
        $scale_ft0_2[pm.time][pointid[0]] = {}
      end
      if $scale_ft0_2[pm.time][pointid[0]][pointid[1]] == nil
        $scale_ft0_2[pm.time][pointid[0]][pointid[1]] = {}
      end
      if $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft] == nil
        $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft] = {}
      end
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["out"] = index_rain[i]
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["raw"] = index_rain_raw[i]
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["near_type"] = near_type[i]
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["near_time"] = near_time[i]
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["inner_type"] = inner_type[i]
      $scale_ft0_2[pm.time][pointid[0]][pointid[1]][pm.ft]["inner_time"] = inner_time[i]
    }
  }
#  p $scale_ft0_2
  return time_list
end

# 乱高下防止処理用スケールの現在値をmk2に保存
def set_mk2_scale_0(mkConn, announcetime, new_ft1_2)
#  p new_ft1_2
  pd = MkPointData.new
  pd.set_point_list($mk2_point_list)
  # 保存用新データ
  # new_ft1_2[k][pointid]["raw"]
  # new_ft1_2[k][pointid]["out"]
  # new_ft1_2[k][pointid]["near_type"]
  # new_ft1_2[k][pointid]["near_time"]
  new_ft1_2.each_key{|ft|
    index_rain = []
    index_rain_raw = []
    near_type = []
    near_time = []
    $point_id.each{|pid|
      if new_ft1_2[ft][pid] != nil
        index_rain.push(new_ft1_2[ft][pid]["out"])
        index_rain_raw.push(new_ft1_2[ft][pid]["raw"])
        near_type.push(new_ft1_2[ft][pid]["near_type"])
        near_time.push(new_ft1_2[ft][pid]["near_time"])
      else
        print "%s ft=%s new near data not exist.\n" % [pid,ft]
        index_rain.push(-1)
        index_rain_raw.push(-1)
        near_type.push(-1)
        near_time.push(-1)
      end
    }
    # FT0だけ
    param = MkDataParam.new(0, '0', announcetime)
    pd.set_data(param, "INDEX_rain_near:INT8", index_rain)
    pd.set_data(param, "INDEX_rain_raw_near:INT8", index_rain_raw)
    pd.set_data(param, "near_type:INT8", near_type)
    pd.set_data(param, "near_time:INT32", near_time)
  }
  mkConn.write_point($config["mk2_scale_near_table"], pd)
end

# ---------------------
# 乱高下防止処理メイン 
# ---------------------
def arrange_ft_0_2(announcetime,ref,mkConn)
#  print "arrange_ft_0_2 1 %s\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの過去値をmk2から取得
  time_list = get_mk2_scale_0(mkConn, announcetime)
  annary = nil
  if time_list.size < 1
    print "scale spool data not exist.\n"
    $scale_ft0_2 = {}
  else
    annary = time_list.reverse
  end
#  print "arrange_ft_0_2 2 %s\n" % [Time.now.to_s]
  # 保存用新データ
  # new_ft1_2[FT][pointid]["raw"]
  # new_ft1_2[FT][pointid]["out"]
  # new_ft1_2[FT][pointid]["near_type"]
  # new_ft1_2[FT][pointid]["near_time"]
  new_ft1_2 = {}
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      pointid = customer_id + "-" + area_id
      k = 0  # FT0だけ
      if new_ft1_2[k] == nil
        new_ft1_2[k] = {}
      end
      new_ft1_2[k][pointid] = {}
      index_rain_raw = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw_near"]
      new_ft1_2[k][pointid]["raw"] = index_rain_raw
      new_ft1_2[k][pointid]["out"] = index_rain_raw
      # 現在値が欠測の場合は乱高下防止処理はスキップ
      if index_rain_raw == nil || index_rain_raw < 0
        next
      end
      # 60分継続処理
#      print "FT%d before keep_60min scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_near"]]
      prv_data = keep_60min_0(announcetime, customer_id, area_id, k, ref["customer_data"][i]["area_data"][j]["INDEX"][k])
      new_ft1_2[k][pointid]["out"] = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_near"]
#      print "FT%d output scale=%s\n" % [k,ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_near"]]
      # FT0の判定フラグ
      if prv_data != nil
#        p 1
        # 前回データあり
        if new_ft1_2[k][pointid]["out"] > prv_data[0]
#          p 3
          # 今回スケールが前回スケールよりアップした
          if $ft0_judge_type[customer_id] != nil &&  $ft0_judge_type[customer_id][area_id] != nil
            # 今回判定フラグあり
#            p 4
            new_ft1_2[k][pointid]["near_type"] = $ft0_judge_type[customer_id][area_id]["near_type"]
            new_ft1_2[k][pointid]["near_time"] = announcetime.to_i
          else
            # 今回のフラグがない→上がった原因不明→フラグは0
#            p 5
            new_ft1_2[k][pointid]["near_type"] = 0
            new_ft1_2[k][pointid]["near_time"] = announcetime.to_i
          end
        else
#          p 6
          # 今回スケールが前回スケールより上がらない→前回値引継ぎ
          new_ft1_2[k][pointid]["near_type"] = prv_data[1]
          new_ft1_2[k][pointid]["near_time"] = prv_data[2]
        end
      else
#        p 2
        # 前回データなし
        if new_ft1_2[k][pointid]["out"] > 0
#          p 7
          # 今回スケールが前回スケールよりアップしたとみなす
          if $ft0_judge_type[customer_id] != nil &&  $ft0_judge_type[customer_id][area_id] != nil
            # 今回判定フラグあり
#            p 8
            new_ft1_2[k][pointid]["near_type"] = $ft0_judge_type[customer_id][area_id]["near_type"]
            new_ft1_2[k][pointid]["near_time"] = announcetime.to_i
          else
            # 今回のフラグがない→上がった原因不明→フラグは0
#            p 9
            new_ft1_2[k][pointid]["near_type"] = 0
            new_ft1_2[k][pointid]["near_time"] = announcetime.to_i
          end
        else
#          p 10
          # 今回スケールが前回スケールより上がらない→リセット
          new_ft1_2[k][pointid]["near_type"] = 0
          new_ft1_2[k][pointid]["near_time"] = 0
        end
      end
    end
  end
#  print "scale_arrange 3 %s\n" % [Time.now.to_s]
  # 乱高下防止処理用スケールの現在値をmk2に保存
  set_mk2_scale_0(mkConn, announcetime, new_ft1_2)
#  print "scale_arrange 4 %s\n" % [Time.now.to_s]
end
