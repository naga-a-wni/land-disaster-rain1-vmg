#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require "rexml/document"

require 'meshkernel'

include REXML    # so that we don’t have to prefix everything
                 # with REXML::...

$config = nil

#
# ------------------------
# 雨のビジネスデータ基準値
# ------------------------
# 降水量の閾値
# [point_id][level][ftrange][kind][name] = value
# ftrange
# observation|kakuho|forecast
# kind
# micronet|analysis|kakuho|compass
# name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_combine_PRST|PRCRIN_combine_60min|PRCRIN_PRST_reset6hour
$rain_threshold_level = {}
# 地点とmicronet地点の紐付け
$pointid_mnetid = {}
# マイクロネット地点テキスト
$mnet_point_list = []
# マイクロネット地点MkPoint
$mk2_mnet_point_list = []
#
# 周辺地域降水量の閾値 V1.7
# レベルの次は配列
# [point_id][level][i][name] = value
# name
# NEAR_PRCRIN_10min|NEAR_PRCRIN_60min
$rain_threshold_level_near = {}
# 地点とmicronet地点の紐付け
# レベルの次は配列
# [point_id][level][i][j] = mnetid
$pointid_mnetid_near = {}
#
def get_rain_data(area,pointid)
  # 雨の基準値 レベルループ
  area.elements.each("prcrin_part/scale_info"){|level|
    # level
    lno = level.elements["scale"].text.to_i
    if lno == 0
      next
    end
    lvl_data = {}
    # 雨の基準値 point_infoのループ V1.7
    level.elements.each("point_info"){|pinfo|
      # マイクロネット地点
      mnetids = []
      pinfo.elements.each("points/point"){|mnid|
        if mnid.text == nil
          next
        end
        mnetids.push(mnid.text)
        if $mnet_point_list.index(mnid.text) == nil
  #           print "mnetid=%s\n" % mnid.text
          $mnet_point_list.push( mnid.text )
        end
      }
      # V1.7
      if pinfo.elements["observation/micronet/NEAR_PRCRIN_10min"] != nil || pinfo.elements["observation/micronet/NEAR_PRCRIN_60min"] != nil
        print "%s scale=%s has near threshold\n" % [pointid,lno]
        # NEAR付要素があれば周辺地域のpinfoと見なす
        obsmnetdata = {}
        if pinfo.elements["observation/micronet/NEAR_PRCRIN_10min"] != nil && pinfo.elements["observation/micronet/NEAR_PRCRIN_10min"].text.to_i > 0
          obsmnetdata["NEAR_PRCRIN_10min"] = pinfo.elements["observation/micronet/NEAR_PRCRIN_10min"].text.to_i
        end
        if pinfo.elements["observation/micronet/NEAR_PRCRIN_60min"] != nil && pinfo.elements["observation/micronet/NEAR_PRCRIN_60min"].text.to_i > 0
          obsmnetdata["NEAR_PRCRIN_60min"] = pinfo.elements["observation/micronet/NEAR_PRCRIN_60min"].text.to_i
        end
        if $pointid_mnetid_near[pointid] == nil
          $pointid_mnetid_near[pointid] = {}
          $rain_threshold_level_near[pointid] = {}
        end
        if $pointid_mnetid_near[pointid][lno] == nil
          # 周辺地域閾値は1レベルに複数存在する可能性があるので配列
          $pointid_mnetid_near[pointid][lno] = []
          $rain_threshold_level_near[pointid][lno] = []
        end
        $pointid_mnetid_near[pointid][lno].push(mnetids)
        $rain_threshold_level_near[pointid][lno].push(obsmnetdata)
        next
      end
      # 既存処理
      if lvl_data.size > 0
        next
      end
      if $pointid_mnetid[pointid] == nil
        $pointid_mnetid[pointid] = mnetids
      else
        $pointid_mnetid[pointid] = $pointid_mnetid[pointid] | mnetids
      end
      # マイクロネット実況閾値
      obsmnetdata = {}
      if pinfo.elements["observation/micronet/PRCRIN_10min"] != nil && pinfo.elements["observation/micronet/PRCRIN_10min"].text.to_i > 0
        obsmnetdata["PRCRIN_10min"] = pinfo.elements["observation/micronet/PRCRIN_10min"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_60min"] != nil && pinfo.elements["observation/micronet/PRCRIN_60min"].text.to_i > 0
        obsmnetdata["PRCRIN_60min"] = pinfo.elements["observation/micronet/PRCRIN_60min"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_3hour"] != nil && pinfo.elements["observation/micronet/PRCRIN_3hour"].text.to_i > 0
        obsmnetdata["PRCRIN_3hour"] = pinfo.elements["observation/micronet/PRCRIN_3hour"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_24hour"] != nil && pinfo.elements["observation/micronet/PRCRIN_24hour"].text.to_i > 0
        obsmnetdata["PRCRIN_24hour"] = pinfo.elements["observation/micronet/PRCRIN_24hour"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_combine_PRST"] != nil && pinfo.elements["observation/micronet/PRCRIN_combine_PRST"].text.to_i > 0
        obsmnetdata["PRCRIN_combine_PRST"] = pinfo.elements["observation/micronet/PRCRIN_combine_PRST"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_combine_60min"] != nil && pinfo.elements["observation/micronet/PRCRIN_combine_60min"].text.to_i > 0
        obsmnetdata["PRCRIN_combine_60min"] = pinfo.elements["observation/micronet/PRCRIN_combine_60min"].text.to_i
      end
      if pinfo.elements["observation/micronet/PRCRIN_PRST_reset6hour"] != nil && pinfo.elements["observation/micronet/PRCRIN_PRST_reset6hour"].text.to_i > 0
        obsmnetdata["PRCRIN_PRST_reset6hour"] = pinfo.elements["observation/micronet/PRCRIN_PRST_reset6hour"].text.to_i
      end
      if obsmnetdata.size > 0
        if lvl_data["observation"] == nil
          lvl_data["observation"] = {}
        end
        if lvl_data["observation"]["micronet"] == nil
        end
        lvl_data["observation"]["micronet"] = obsmnetdata
      end
      # 解析雨量実況閾値
      obsasisdata = {}
      if pinfo.elements["observation/analysis/PRCRIN_10min"] != nil && pinfo.elements["observation/analysis/PRCRIN_10min"].text.to_i > 0
        obsasisdata["PRCRIN_10min"] = pinfo.elements["observation/analysis/PRCRIN_10min"].text.to_i
      end
      if pinfo.elements["observation/analysis/PRCRIN_60min"] != nil && pinfo.elements["observation/analysis/PRCRIN_60min"].text.to_i > 0
        obsasisdata["PRCRIN_60min"] = pinfo.elements["observation/analysis/PRCRIN_60min"].text.to_i
      end
      if pinfo.elements["observation/analysis/PRCRIN_3hour"] != nil && pinfo.elements["observation/analysis/PRCRIN_3hour"].text.to_i > 0
        obsasisdata["PRCRIN_3hour"] = pinfo.elements["observation/analysis/PRCRIN_3hour"].text.to_i
      end
      if pinfo.elements["observation/analysis/PRCRIN_24hour"] != nil && pinfo.elements["observation/analysis/PRCRIN_24hour"].text.to_i > 0
        obsasisdata["PRCRIN_24hour"] = pinfo.elements["observation/analysis/PRCRIN_24hour"].text.to_i
      end
      if pinfo.elements["observation/analysis/PRCRIN_combine_PRST"] != nil && pinfo.elements["observation/analysis/PRCRIN_combine_PRST"].text.to_i > 0
        obsasisdata["PRCRIN_combine_PRST"] = pinfo.elements["observation/analysis/PRCRIN_combine_PRST"].text.to_i
      end
      if pinfo.elements["observation/analysis/PRCRIN_combine_60min"] != nil && pinfo.elements["observation/analysis/PRCRIN_combine_60min"].text.to_i > 0
        obsasisdata["PRCRIN_combine_60min"] = pinfo.elements["observation/analysis/PRCRIN_combine_60min"].text.to_i
      end
      if obsasisdata.size > 0
        if lvl_data["observation"] == nil
          lvl_data["observation"] = {}
        end
        lvl_data["observation"]["analysis"] = obsasisdata
      end
      # 確報確報閾値
      kakuho_kakuho = {}
      if pinfo.elements["kakuho/PRCRIN_60min"] != nil && pinfo.elements["kakuho/PRCRIN_60min"].text.to_i > 0
        kakuho_kakuho["PRCRIN_60min"] = pinfo.elements["kakuho/PRCRIN_60min"].text.to_i
      end
      if pinfo.elements["kakuho/PRCRIN_3hour"] != nil && pinfo.elements["kakuho/PRCRIN_3hour"].text.to_i > 0
        kakuho_kakuho["PRCRIN_3hour"] = pinfo.elements["kakuho/PRCRIN_3hour"].text.to_i
      end
      if pinfo.elements["kakuho/PRCRIN_24hour"] != nil && pinfo.elements["kakuho/PRCRIN_24hour"].text.to_i > 0
        kakuho_kakuho["PRCRIN_24hour"] = pinfo.elements["kakuho/PRCRIN_24hour"].text.to_i
      end
      if kakuho_kakuho.size > 0
        if lvl_data["kakuho"] == nil
          lvl_data["kakuho"] = {}
        end
        lvl_data["kakuho"]["kakuho"] = kakuho_kakuho
      end
      # 確報マイクロネット閾値
      kakuho_mnet = {}
      if pinfo.elements["kakuho/micronet/PRCRIN_combine_PRST"] != nil && pinfo.elements["kakuho/micronet/PRCRIN_combine_PRST"].text.to_i > 0
        kakuho_mnet["PRCRIN_combine_PRST"] = pinfo.elements["kakuho/micronet/PRCRIN_combine_PRST"].text.to_i
      end
      if pinfo.elements["kakuho/micronet/PRCRIN_combine_60min"] != nil && pinfo.elements["kakuho/micronet/PRCRIN_combine_60min"].text.to_i > 0
        kakuho_mnet["PRCRIN_combine_60min"] = pinfo.elements["kakuho/micronet/PRCRIN_combine_60min"].text.to_i
      end
      if kakuho_mnet.size > 0
        if lvl_data["kakuho"] == nil
          lvl_data["kakuho"] = {}
        end
        lvl_data["kakuho"]["micronet"] = kakuho_mnet
      end
      # 確報解析雨量閾値
      kakuho_asis = {}
      if pinfo.elements["kakuho/analysis/PRCRIN_combine_PRST"] != nil && pinfo.elements["kakuho/analysis/PRCRIN_combine_PRST"].text.to_i > 0
        kakuho_asis["PRCRIN_combine_PRST"] = pinfo.elements["kakuho/analysis/PRCRIN_combine_PRST"].text.to_i
      end
      if pinfo.elements["kakuho/analysis/PRCRIN_combine_60min"] != nil && pinfo.elements["kakuho/analysis/PRCRIN_combine_60min"].text.to_i > 0
        kakuho_asis["PRCRIN_combine_60min"] = pinfo.elements["kakuho/analysis/PRCRIN_combine_60min"].text.to_i
      end
      if kakuho_asis.size > 0
        if lvl_data["kakuho"] == nil
          lvl_data["kakuho"] = {}
        end
        lvl_data["kakuho"]["analysis"] = kakuho_asis
      end
      # 予測閾値
      forecastdata = {}
      if pinfo.elements["forecast/PRCRIN_60min"] != nil && pinfo.elements["forecast/PRCRIN_60min"].text.to_i > 0
        forecastdata["PRCRIN_60min"] = pinfo.elements["forecast/PRCRIN_60min"].text.to_i
      end
      if pinfo.elements["forecast/PRCRIN_3hour"] != nil && pinfo.elements["forecast/PRCRIN_3hour"].text.to_i > 0
        forecastdata["PRCRIN_3hour"] = pinfo.elements["forecast/PRCRIN_3hour"].text.to_i
      end
      if pinfo.elements["forecast/PRCRIN_24hour"] != nil && pinfo.elements["forecast/PRCRIN_24hour"].text.to_i > 0
        forecastdata["PRCRIN_24hour"] = pinfo.elements["forecast/PRCRIN_24hour"].text.to_i
      end
      if forecastdata.size > 0
        if lvl_data["forecast"] == nil
          lvl_data["forecast"] = {}
        end
        lvl_data["forecast"]["compass"] = forecastdata
      end
    } # 雨の基準値 point_infoのループ V1.7
    if lvl_data.size > 0
      if $rain_threshold_level[pointid] == nil
        $rain_threshold_level[pointid] = {}
      end
      $rain_threshold_level[pointid][lno] = lvl_data
    end
  } # 雨の基準値 レベルループ
end

#
# 基準値XMLデータを読み込む。
#
def get_xmldata_threshold()
  # XMLファイルオープン
  dest = open($config["table_srf_10vscal_path"],"r+")
  if !dest.flock( File::LOCK_EX )
    log.write("File [#{destpath}] lock failed.")
  end
  data = dest.read
  dest.flock( File::LOCK_UN )
  dest.close
  doc1 = REXML::Document.new(data)
  # customerループ
  doc1.elements.each("list/CUST"){|customer|
    # customer_id
    customer_id = customer.elements["LCLID"].text
    if $customer_id[customer_id] == nil
      print "customer_id=%s not supported\n" % [customer_id]
      next
    end
    print "customer_id=%s\n" % [customer_id]
    # エリアループ
    customer.elements.each("area_info"){|area|
      # area_id
      area_id = area.elements["LCLID"].text
      # ポイントID
      pointid = customer_id + "-" + area_id
      # 雨の基準値
      get_rain_data(area,pointid)
    } # エリアループ
  } # customerループ
end

def main()
  if ARGV.size < 1
    print "Usage:dump_tables.rb <configfilepath>\n"
    return
  end
  $config = YAML.load_file(ARGV[0])
  if File.exist?($config["table_srf_10vscal_path"]) == false
    print "xml file not exist %s\n" % $config["table_srf_10vscal_path"]
    return
  end
  # 基本情報をスプールから取得
  dbdata = PStore.new($config["table_basic_rain_dump_path"])
  basic_data = {}
  dbdata.transaction() do
    basic_data = dbdata['root']
  end
  if basic_data == nil || basic_data.size < 1
    print "table_basic spool data not exist\n"
    return
  end
  $customer_id = basic_data["customer_id"] 
  get_xmldata_threshold()
  $mnet_point_list.each{|mnid|
    $mk2_mnet_point_list.push(MkPoint.new( mnid ))
  }
  $dbdata = PStore.new($config["table_10vscal_rain_dump_path"])
  marshal_data = {}
  $dbdata.transaction() do
    # 雨
    marshal_data["rain_threshold_level"] = $rain_threshold_level
    marshal_data["pointid_mnetid"] = $pointid_mnetid
    marshal_data["mnet_point_list"] = $mnet_point_list
    marshal_data["mk2_mnet_point_list"] = $mk2_mnet_point_list
    marshal_data["rain_threshold_level_near"] = $rain_threshold_level_near  # V1.7
    marshal_data["pointid_mnetid_near"] = $pointid_mnetid_near  # V1.7
    $dbdata['root'] = marshal_data
  end
end
print "timenow=%s\n" % Time.now.to_s
main()
print "timenow=%s\n" % Time.now.to_s
