#
# マイクロネット
#
# マイクロネット1時間降水量過去24h [0]がft0で以降[22]までマイナス
# [][areaid]=60分雨量
$micronet_p60_24hour = []
# 最新のマイクロネット降水量
$micronet_prec_latest = {}
# mk2にデータが全くない
$lack_micronet = false
# マイクロネット地点MkPoint
$mk2_mnet_point_list = []
# 地点とmicronet地点の紐付け
$pointid_mnetid = {}
# マイクロネット地点テキスト
$mnet_point_list = []
# マイクロネット+確報
# 足し合わせ元までは記録しない
$micronet_prec_ft1 = {}

# WNIマイクロネット雨量データmk2欠落チェック
def check_micronet_prec( mkConn, time_list, announcetime )
  checktime = announcetime - 3600 * 24
  newtimelist = time_list
  while checktime < announcetime
    if time_list.index(checktime) == nil
      print "mk2 micronet prec data is lack basetime=%s\n" % [ checktime.to_s ]
      newtimelist = nil
      pd = MkPointData.new
      pd.set_point_list([$mk2_mnet_point_list[0]]) # 1個でもデータがあればあとはfill値が取れる
      param = MkDataParam.new(0, '0', checktime)
      pd.set_data(param, "PRCRIN_Counter:INT32", [-1])
      mkConn.write_point($config["mk2_prec_table"], pd)
    end
    checktime = checktime + 600
  end
  if newtimelist == nil
    newtimelist = mkConn.get_time_list($config["mk2_prec_table"], announcetime - 3600 * 24, announcetime)
  end
  return newtimelist
end

def unitconv(data)
  data.each_index{|i|
    if data[i] > 0
      data[i] = data[i] / 10
    end
  }
end

# WNIマイクロネット雨量データをmk2から取得
def get_micronet_prec(mkConn, announcetime, justtime)
  time_list = mkConn.get_time_list($config["mk2_prec_table"], announcetime - 3600 * 24, announcetime)
  latesttime = Time.at(0)
  latesttime = time_list[time_list.size-1] if time_list.size > 0
  print "micronet data in mk2 latesttime=%s\n" % [ latesttime.to_s ]
  if latesttime >= announcetime
    latesttime = time_list[time_list.size-2]
  end
  print "micronet data use latesttime=%s\n" % [ latesttime.to_s ]
  if announcetime - latesttime > 1800
    # データがない
    print "micronet data in mk2 is not available basetime=%s\n" % [ latesttime.to_s ]
    $lack_micronet = true
    # micronetはリターンしない。check_micronet_precでmk2に-1を埋める。
  end
  time_list = check_micronet_prec( mkConn, time_list, announcetime )
  dbdata = PStore.new($config["spool_prec_path"])
  dbdata.transaction() do
    dbdata['root'] = Time.now
    #
    # latest data
    #
    params = [ MkDataParam.new(0, '0', latesttime) ]
    element_list = [ 'PRCRIN_10:INT32','PRCRIN_60:INT32','PRCRIN_180:INT32','PRCRIN_24H:INT32','PRCRIN_Reset6:INT32' ]
    pd = mkConn.read_point($config["mk2_prec_table"], params, $mk2_mnet_point_list, element_list)
    prcrin_10 = pd.get_data(params[0], 'PRCRIN_10')
    prcrin_60 = pd.get_data(params[0], 'PRCRIN_60')
    prcrin_180 = pd.get_data(params[0], 'PRCRIN_180')
    prcrin_24h = pd.get_data(params[0], 'PRCRIN_24H')
    prcrin_reset6 = pd.get_data(params[0], 'PRCRIN_Reset6')
    unitconv(prcrin_10)
    unitconv(prcrin_60)
    unitconv(prcrin_180)
    unitconv(prcrin_24h)
    unitconv(prcrin_reset6)
    $mnet_point_list.each_index{|i|
      pid = $mnet_point_list[i]
      $micronet_prec_latest[pid] = {}
      $micronet_prec_latest[pid]['PRCRIN_10min'] = prcrin_10[i]
      $micronet_prec_latest[pid]['PRCRIN_60min'] = prcrin_60[i]
      $micronet_prec_latest[pid]['PRCRIN_3hour'] = prcrin_180[i]
      $micronet_prec_latest[pid]['PRCRIN_24hour'] = prcrin_24h[i]
      $micronet_prec_latest[pid]['PRCRIN_PRST_reset6hour'] = prcrin_reset6[i]
    }
    #
    # 22h before
    #
    params = []
    for i in 0..22
      params.push(MkDataParam.new(0, '0', latesttime - 3600 * i))
    end
    element_list = [ 'PRCRIN_60:INT32' ]
    pd = mkConn.read_point($config["mk2_prec_table"], params, $mk2_mnet_point_list, element_list)
    params.each{|prm|
      p60data = pd.get_data(prm, 'PRCRIN_60')
      unitconv(p60data)
      p60hash = {}
      $mnet_point_list.each_index{|i|
        p60hash[$mnet_point_list[i]] = p60data[i]
      }
      $micronet_p60_24hour.push(p60hash)
    }
  end
  return latesttime
end

def mnet_add_10minv_ft1( mkConn, ft1_basetime, kakuho_btime, latesttime )
  # ft1で積算する範囲のマイクロネットの全値
  # mnet_add_all[時刻][マイクロネット地点値配列]
  mnet_add_all = {}
  # ft1で積算するマイクロネット値配列（マイクロネットid）
  # mnet_add_array[マイクロネットid][値配列]
  mnet_add_array = {}
  #
  # マイクロネット雨量を読み出す。起動時刻によって使用量が違うが取得量は一定とする
  #
#  fsname = "%sadd_10minv_ft1_%s.txt" % [$config["test_output_dir"],Time.now.strftime("%H%M")]
#  fs = File.open(fsname,'a')
  add_start = ft1_basetime - 1800
  params = []
  for i in 0..9
    gettime = add_start + 600 * i
    if gettime > latesttime
      break
    end
    params.push(MkDataParam.new(0, '0', gettime))
  end
  element_list = [ 'PRCRIN_10:INT32' ]
  pd = mkConn.read_point($config["mk2_prec_table"], params, $mk2_mnet_point_list, element_list)
  params.each{|prm|
    p10data = pd.get_data(prm, 'PRCRIN_10')
    unitconv(p10data)
    mnet_add_all[prm.time] = p10data
  }
#  mnet_spool = "%smnetadd_%d.pst" % [$config["test_output_dir"],Time.now.min]
#  dbdata = PStore.new(mnet_spool)
#  dbdata.transaction() do
#    dbdata['root'] = mnet_add_all
#  end
  #
  # 取得したデータから積算に使用する配列を作成する
  #
  print "micronet add_start=%s\n" % [add_start.to_s]
  if mnet_add_all[ft1_basetime] == nil
    if mnet_add_all[ft1_basetime-600] != nil
      mnet_add_all[ft1_basetime] = mnet_add_all[ft1_basetime-600]
      print "max micronet ft1_basetime=%s replaced by 10min before\n" % [ft1_basetime.to_s]
    elsif mnet_add_all[ft1_basetime-600*2] != nil
      mnet_add_all[ft1_basetime][i] = mnet_add_all[ft1_basetime-600*2][i]
      print "max micronet ft1_basetime=%s replaced by 20min before\n" % [ft1_basetime.to_s]
    end
  end
  $mnet_point_list.each_index{|i|
    mid = $mnet_point_list[i]
    # 開始時刻の値を補完
    if mnet_add_all[ft1_basetime] == nil
      mnet_add_all[ft1_basetime] = []
    end
    if mnet_add_all[ft1_basetime][i] == nil
      mnet_add_all[ft1_basetime][i] = -1
    end
    if mnet_add_all[ft1_basetime][i] < 0
      if mnet_add_all[ft1_basetime-600] != nil && mnet_add_all[ft1_basetime-600][i] >= 0
        mnet_add_all[ft1_basetime][i] = mnet_add_all[ft1_basetime-600][i]
        print "%s %s max micronet value=%d replaced by 10min before\n" % [mid,ft1_basetime.to_s,mnet_add_all[ft1_basetime][i]] if $verbose
      elsif mnet_add_all[ft1_basetime-600*2] != nil && mnet_add_all[ft1_basetime-600*2][i] >= 0
        mnet_add_all[ft1_basetime][i] = mnet_add_all[ft1_basetime-600*2][i]
        print "%s %s max micronet value=%d replaced by 20min before\n" % [mid,ft1_basetime.to_s,mnet_add_all[ft1_basetime][i]]
      end
    end
    p60a = []
    # 開始時刻から確報のbasetimeまでを配列に入れる
    for j in 0..6
      addtime = ft1_basetime + 600 * j
      if addtime > kakuho_btime
        break
      end
      if mnet_add_all[addtime] == nil
#        fs.print "%s data not exist\n" % addtime.to_s
        p60a.push(-1)
        next
      end
      if mnet_add_all[addtime][i] == nil
#        fs.print "%s %s data not exist\n" % [addtime.to_s,pid]
        p60a.push(-1)
        next
      end
      p60a.push(mnet_add_all[addtime][i])
    end
    mnet_add_array[mid] = p60a
  }
  #
  # ft1足し合わせ
  #
  $point_id.each_index{|i|
    pid = $point_id[i]
#    fs.print pid + "\n"
    # マイクロネットを足し合わせて最大値まで求める
    mnetids = $pointid_mnetid[pid]
    maxv = -1
    maxa = nil
    if mnetids != nil
      mnetids.each{|mid|
        # 足し合わせ
        p60a = mnet_add_array[mid]
        p60 = 0
        if p60a != nil
#          fs.print "%s[%s]\n" % [mid,p60a.join(",")]
          p60a.each_index{|j|
            if j == 0  # basetimeはskip
              next
            end
            if p60a[j] < 0
              if p60a[j-1] < 0
                p60 = -1
                break
              else
                p60 += p60a[j-1]
                p60a[j] = p60a[j-1]
              end
            else
              p60 += p60a[j]
            end
          }
        else
          p60 = -1
        end
        # 最大値
        if maxv < p60
          maxv = p60
          maxa = p60a
        end
      }
    end
    if maxv < 0 || maxa == nil
      # マイクロネットデータなし
#      print "point-id=%s PRCRIN_10 micronet value max not exist\n" % [ pid ]
      $micronet_prec_ft1[pid] = -1
      next
    end
    # 確報の計算結果を足す
    p60 = maxv
    if $kakuho_calc_3ft == nil || $kakuho_calc_3ft[0] == nil || $kakuho_calc_3ft[0][pid] == nil || $kakuho_calc_3ft[0][pid]["max"] < 0
#      fs.print "kakuho data not exist\n"
      # 確報がない場合はマイクロネットを足す
      for j in maxa.size..6
        p60 += maxa.last
      end
      $micronet_prec_ft1[pid] = p60
    else
      # 確報あり
      $micronet_prec_ft1[pid] = p60
      $micronet_prec_ft1[pid] += $kakuho_calc_3ft[0][pid]["max"] * $config["kakuho_filter"]
    end
#    fs.print "ft1=%d\n" % $micronet_prec_ft1[pid]
  }
#  fs.close
end

#
# WNIマイクロネット雨量データによるFT0判定
#
# 降水量の閾値
# [point_id][level][ftrange][kind][name] = value
# ftrange
# observation|kakuho|forecast
# kind
# micronet|analysis|kakuho|forecast
# name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_combine_PRST|PRCRIN_combine_60min|PRCRIN_PRST_reset6hour
#
# 最終出力データ
# [point_id][][kind][name] = value
# kind
# micronetid|analysis|kakuho|compass
# scale name
# INDEX_PRCRIN_10min|INDEX_PRCRIN_60min|INDEX_PRCRIN_3hour|INDEX_PRCRIN_24hour|INDEX_PRCRIN_combine|INDEX_PRCRIN_PRST_reset6hour
# value name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_PRST_reset6hour
#
def mnet_get_index_prec_ft0()
  elmvalue = ["PRCRIN_10min","PRCRIN_60min","PRCRIN_3hour","PRCRIN_24hour","PRCRIN_PRST_reset6hour"]
  if $micronet_prec_latest.size < 1
    print "micronet latst data not exist.\n"
    return
  end
  # エリアループ
  $point_id.each{|pid|
    if $threshold_level[pid] == nil
      next
    end
    mnetids = $pointid_mnetid[pid]
    if mnetids != nil
      # マイクロネット地点ループ
      mnetids.each{|mid|
        if $output_data[pid][0][mid] == nil
          $output_data[pid][0][mid] = {}
        end
        $output_data[pid][0][mid]["PRCRIN_60min"] = $micronet_prec_latest[mid]["PRCRIN_60min"]
        $output_data[pid][0][mid]["PRCRIN_24hour"] = $micronet_prec_latest[mid]["PRCRIN_24hour"]  # V1.7
        levels = $threshold_level[pid].keys.sort
        # スケールループ
        levels.each{|lvl|
          if $threshold_level[pid][lvl]["observation"] == nil ||
              $threshold_level[pid][lvl]["observation"]["micronet"] == nil ||
              $threshold_level[pid][lvl]["observation"]["micronet"].size < 1
            next
          end
          threshold = $threshold_level[pid][lvl]["observation"]["micronet"]
          # 10分、60分、3時間、24時間雨量、連続雨量による判定
          elmvalue.each{|elm|
            indexelm = "INDEX_" + elm
            if threshold[elm] != nil && threshold[elm] != ""
              if $output_data[pid][0][mid] == nil
                $output_data[pid][0][mid] = {}
              end
              if $output_data[pid][0][mid][elm] == nil
                $output_data[pid][0][mid][elm] = $micronet_prec_latest[mid][elm]
              end
              if $output_data[pid][0][mid][indexelm] == nil
                $output_data[pid][0][mid][indexelm] = $output_data[pid][0][mid][elm] < 0 ? -99 : 0
              end
              if threshold[elm] <= $output_data[pid][0][mid][elm]
                $output_data[pid][0][mid][indexelm] = lvl
              end
            end
          }
          # 組み合わせ雨量による判定
          if threshold["PRCRIN_combine_PRST"] != nil && threshold["PRCRIN_combine_PRST"] != "" &&
              threshold["PRCRIN_combine_60min"] != nil && threshold["PRCRIN_combine_60min"] != ""
            if $output_data[pid][0][mid] == nil
              $output_data[pid][0][mid] = {}
            end
            if $output_data[pid][0][mid]["INDEX_PRCRIN_combine"] == nil
              r6h = $micronet_prec_latest[mid]["PRCRIN_PRST_reset6hour"]
              $output_data[pid][0][mid]["PRCRIN_PRST_reset6hour"] = r6h
              $output_data[pid][0][mid]["INDEX_PRCRIN_combine"] = r6h < 0 ? -99 : 0
            end
            if $output_data[pid][0][mid]["PRCRIN_60min"] == nil
              $output_data[pid][0][mid]["PRCRIN_60min"] = $micronet_prec_latest[mid]["PRCRIN_60min"]
            end
            if threshold["PRCRIN_combine_60min"] <= $output_data[pid][0][mid]["PRCRIN_60min"] && 
                threshold["PRCRIN_combine_PRST"] <= $output_data[pid][0][mid]["PRCRIN_PRST_reset6hour"]
              $output_data[pid][0][mid]["INDEX_PRCRIN_combine"] = lvl
            end
          end
        }  # スケールループ
      }  # マイクロネット地点ループ
    end
  }  # エリアループ
end

#
# 実況  ft=0 WNIマイクロネット雨量データ周辺地域雨量実況値基準値による判定 V1.7
#
# 周辺地域降水量の閾値 V1.7
# レベルの次は配列
# [point_id][level][i][name] = value
# name
# NEAR_PRCRIN_10min|NEAR_PRCRIN_60min
#
# 地点とmicronet地点の紐付け
# レベルの次は配列
# [point_id][level][i][j] = mnetid
#
# 最終出力データ
# [point_id][][kind][name] = value
# kind
# micronetid
# scale name
# INDEX_NEAR_PRCRIN_10min|INDEX_NEAR_PRCRIN_60min 
# value name
# PRCRIN_10min|PRCRIN_60min
#
def mnet_get_index_prec_ft0_near()
  elmvalue = ["NEAR_PRCRIN_10min","NEAR_PRCRIN_60min"]
  if $micronet_prec_latest.size < 1
    print "micronet latst data not exist.\n"
    return
  end
  # エリアループ
  $point_id.each{|pid|
    if $threshold_level_near[pid] == nil
      next
    end
    if $pointid_mnetid_near[pid] == nil
      next
    end
    levels = $pointid_mnetid_near[pid].keys.sort
    # スケールループ
    levels.each{|lvl|
      if $pointid_mnetid_near[pid][lvl] == nil
        next
      end
      # レベルの次は配列
      $pointid_mnetid_near[pid][lvl].each_index{|i|
        if $threshold_level_near[pid][lvl] == nil
          next
        end
        mnetids = $pointid_mnetid_near[pid][lvl][i]
        if mnetids != nil
          # マイクロネット地点ループ
          mnetids.each{|mid|
            if $output_data[pid][0][mid] == nil
              $output_data[pid][0][mid] = {}
            end
            $output_data[pid][0][mid]["NEAR_PRCRIN_60min"] = $micronet_prec_latest[mid]["PRCRIN_60min"]
            # レベルの次は配列
            if $threshold_level_near[pid][lvl][i] == nil || $threshold_level_near[pid][lvl][i].size < 1
              next
            end
            threshold = $threshold_level_near[pid][lvl][i]
            # 10分、60分雨量による判定
            elmvalue.each{|elm|
              indexelm = "INDEX_" + elm
              if threshold[elm] != nil && threshold[elm] != ""
                if $output_data[pid][0][mid] == nil
                  $output_data[pid][0][mid] = {}
                end
                if $output_data[pid][0][mid][elm] == nil
                  if elm =~ /^NEAR_(.+)/
                    $output_data[pid][0][mid][elm] = $micronet_prec_latest[mid][$1]
                  end
                end
                if $output_data[pid][0][mid][indexelm] == nil
                  $output_data[pid][0][mid][indexelm] = $output_data[pid][0][mid][elm] < 0 ? -99 : 0
                end
                if threshold[elm] <= $output_data[pid][0][mid][elm]
                  $output_data[pid][0][mid][indexelm] = lvl
                end
              end
            }
          }  # マイクロネット地点ループ
        end
      }  # 配列ループ
    }  # スケールループ
  }  # エリアループ
end
