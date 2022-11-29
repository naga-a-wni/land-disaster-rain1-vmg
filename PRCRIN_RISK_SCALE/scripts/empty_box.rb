# ---------
# 空箱判定 
# ---------
def exist_thd(scale_name,pid,level)
  if level == 0
    return true
  end
#  print "exist_thd scale_name=%s pid=%s level=%s\n" % [scale_name,pid,level]
  if $threshold_level[pid][level] != nil
    if $threshold_level[pid][level]["kakuho"] != nil
      $threshold_level[pid][level]["kakuho"].each_key{|kind|
        if $threshold_level[pid][level]["kakuho"][kind] != nil
          $threshold_level[pid][level]["kakuho"][kind].each_key{|tn|
            if scale_name.index("INDEX_" + tn) != nil
              return true
            end
            if tn =~ /^PRCRIN_combine/ && scale_name.index("INDEX_PRCRIN_combine") != nil
              return true
            end
          }
        end
      }
    end
  end
  return false
end

# ----------------
# 空箱処理(FT1-2) 
# ----------------
# そのスケールの前後のスケールを見て、直前の出力済スケールにより近いスケールを採用する。
# ただし、採用されたスケールがさらに空箱の場合、上記と同様に前後のスケールを見て、
# 直前の出力済スケールにより近いスケールを採用する。（採用されたスケールが空箱でなくなるまで繰り返し行う。）
def empty_box(announcetime, customer_id, area_id, k, ref_ft)
#  print "%s ----- start function -----\n" % [announcetime.to_s]
  if ref_ft["INDEX_rain_inner"] < 1
    return
  end
  # 生スケール判定に使用した要素
  scale_name = []
  point_count = ref_ft["point_count"]
  for i in 0...point_count
    scale_count = ref_ft["POINT"][i]["SCALE_count"]
    for j in 0...scale_count
      if ref_ft["POINT"][i]["SCALE"][j]["value"] == ref_ft["INDEX_rain_raw"] && scale_name.index(ref_ft["POINT"][i]["SCALE"][j]["name"]) == nil
        scale_name.push(ref_ft["POINT"][i]["SCALE"][j]["name"])
      end
    end
  end
  if scale_name.size < 1
    print "scale name not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
    return
  end
#  p scale_name
  # 降水量の閾値
  # [point_id][level][ftrange][kind][name] = value
  # point_id
  # 全顧客ID-エリアID（ハイフン連結）テキスト
  # ftrange
  # observation|kakuho|forecast
  # kind
  # micronet|analysis|kakuho|compass
  # name
  # PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_combine_PRST|PRCRIN_combine_60min
  pid = customer_id + "-" + area_id
  if $threshold_level[pid] == nil
    print "threshold data not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
    return
  end
  # 空箱判定
  if exist_thd(scale_name,pid,ref_ft["INDEX_rain_inner"])
    # 空箱でない
    return
  end
  # 空箱
  empty_level = []
  print "empty box exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
  print "scale_name=[%s]\n" % [scale_name.join(",")]
  empty_level.push(ref_ft["INDEX_rain_inner"])
  # 再空箱判定
  1.upto(6){|i|
    oldtime = announcetime - 600 * i
    if $scale_ft_all[oldtime] == nil
      over_60min = false
      next
    end
    if $scale_ft_all[oldtime][customer_id] == nil
      over_60min = false
      next
    end
    if $scale_ft_all[oldtime][customer_id][area_id] == nil
      over_60min = false
      next
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k] == nil
      over_60min = false
      next
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k]["out"] == nil
      over_60min = false
      next
    end
    if $scale_ft_all[oldtime][customer_id][area_id][k]["out"] < 0
      over_60min = false
      next
    end
    es = ref_ft["INDEX_rain_inner"]
    ps = $scale_ft_all[oldtime][customer_id][area_id][k]["out"]
    print "privious scale=%s cid=%s aid=%s ft=%s time=%s\n" % [ps,customer_id,area_id,k,oldtime.to_s]
    if ps == es
      print "privious scale and empty scale are same scale=%s.\n" % [ps]
      print "It must be result of continue logic.\n" % [ps]
      print "raw scale=%s not changed.\n" % [ref_ft["INDEX_rain_raw"]]
      ref_ft["INDEX_rain_inner"] = ref_ft["INDEX_rain_raw"]
      return
    end
    if !exist_thd(scale_name,pid,ps)
      print "warnnig privious scale also empty box cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ps]
    end
    # 例）「4」が今回スケール判定に使用した要素で空箱の場合、「4」に最も近い値は「3」と「5」、直前の出力済スケール「2」により近い「3」となる。
    #     「3」がさらに空箱の場合、「3」に最も近い値は「2」と「4」、直前の出力済スケール「2」により近い「2」となる。
    loop_time = 0
    down = true
    loop do
      ds = es - 1
      us = es + 1
      if ds < 0
        es = us
        down = false
      elsif us > 5
        es = ds
        down = true
      else
        if (ds - ps).abs > (us - ps).abs
          es = us
          down = false
        else
          es = ds
          down = true
        end
      end
      if empty_level.index(es) != nil
        print "empty box cid=%s aid=%s ft=%s scale=%s already checked.\n" % [customer_id,area_id,k,es]
        if down
          es -= 1
        else
          if es > 5
            es -= 1
            down = true
          else
            es += 1
          end
        end
      end
      print "down=%s\n" % [down.to_s]
      print "loop_time=%s near privious scale=%s cid=%s aid=%s ft=%s\n" % [loop_time,es,customer_id,area_id,k]
      print "exist_thd scale_name=%s pid=%s level=%s\n" % [scale_name,pid,es]
      if exist_thd(scale_name,pid,es)
        print "empty box changed cid=%s aid=%s ft=%s scale=%s to scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"],es]
        ref_ft["INDEX_rain_inner"] = es
        return
      end
      loop_time += 1
      print "%d times empty box cid=%s aid=%s ft=%s scale=%s\n" % [loop_time, customer_id,area_id,k,es]
      if empty_level.index(es) == nil
        empty_level.push(es)
      end
      if loop_time > 5
        print "too many loop. raw scale=%s not changed.\n" % [ref_ft["INDEX_rain_raw"]]
        ref_ft["INDEX_rain_inner"] = ref_ft["INDEX_rain_raw"]
        return
      end
    end
  }
  print "previous scale not exist cid=%s aid=%s ft=%s scale=%s\n" % [customer_id,area_id,k,ref_ft["INDEX_rain_inner"]]
  ref_ft["INDEX_rain_inner"] = ref_ft["INDEX_rain_raw"]
end
