#!/usr/local/bin/ruby

require 'optparse'
require 'pstore'
require 'yaml'

require 'meshkernel'

$myname = File.basename(__FILE__)
$mypath  = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'amdeliver.rb'
require 'create_ruheader.rb'
require 'risk_scale_rain_micronet.rb'
#require 'risk_scale_rain_analysis.rb'
#require 'analysis_add_10minv_ft1.rb'
require 'risk_scale_rain_scale.rb'
require 'empty_box.rb'
require 'arrange_ft_0_2.rb'
require 'prec_scale_arrange.rb'
require 'prec_scale_arrange_fcst.rb'

$verbose = false
$mip    = false

MK2_HOST = "localhost"
MK2_PORT = 11112
LACK_VALUE_32 = -999999999    # 9を9回

# 設定値
$config = nil
#
# ビジネスデータ
#
# 全顧客IDとエリアIDの紐づけ
$customer_id = {}
# 全顧客ID-エリアID（ハイフン連結）テキスト
$point_id = []
# 確報を使用しない
# 顧客毎なので顧客IDの配列
$kakuho_ignore = nil
# 大雨のリスクスケールを使用しない
# エリア毎なので顧客IDとエリアIDの配列のハッシュ
$rain_ignore = {}
# グループid
$groupid = nil
$group_count = nil

# 降水量の閾値
# [point_id][level][ftrange][kind][name] = value
# ftrange
# observation|kakuho|forecast
# kind
# micronet|analysis|kakuho|compass
# name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_combine_PRST|PRCRIN_combine_60min
$threshold_level = {}

# 最終出力データ
# [point_id][][kind][name] = value
# kind
# micronetid|analysis|kakuho|compass
# scale name
# INDEX_PRCRIN_10min|INDEX_PRCRIN_60min|INDEX_PRCRIN_3hour|INDEX_PRCRIN_24hour|INDEX_PRCRIN_combine
# value name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_PRST_reset6hour
$output_data = {}

# 3時間確報計算済データ
# [ft1,ft2,ft3][pid]["add"][足し合わせた雨量配列]
#                   ["max"][最大値]
$kakuho_calc_3ft = nil

# COMPASSスプールデータ
# [ft][pid]=最大値
$compass_prec = nil
# 編集されたスケール
# [latesttime]
# [editdata][customer_id][area_id][FT] = INDEX_rain
$edit_scale = nil
# FT2,FT3の60分雨量
# [pid]
#$ft2_60min = {}
#$ft2_60min[2] = {}
#$ft2_60min[3] = {}
# FT0の判定フラグ  V1.7
# [customer_id][area_id]["inner_type"] = 1|2
# [customer_id][area_id]["near_type"] = 1
$ft0_judge_type = {}
$mk2_point_list = []

# 周辺地域降水量の閾値 V1.7
# レベルの次は配列
# [point_id][level][i][name] = value
# name
# NEAR_PRCRIN_10min|NEAR_PRCRIN_60min
$threshold_level_near = {}
# 地点とmicronet地点の紐付け
# レベルの次は配列
# [point_id][level][i][j] = mnetid
$pointid_mnetid_near = {}

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config> <groupid>
  Available options:
    -v --verbose                         : verbose mode.
    -m --mip                             : mip.
    -d yyyymmddhhMM --debug yyyymmddhhMM : debugtime
    -o OUTPUT --output OUTPUT            : output path
    -h HOST --host HOST                  : mk2 host
    -p PORT --port PORT                  : mk2 port
EOF
  exit
end

# ビジネスデータを読み込む。
def get_business_data(mkConn,debugtime)
  if debugtime == nil
    #
    # 基本情報更新中は待つ
    #
#    mkConn.lock_table($config["mk2_prec_group_table"])
    latesttime = mkConn.get_latest_time( $config["mk2_prec_group_table"] )
    print "latest table=%s\n" % [latesttime.to_s]
#    mkConn.unlock_table($config["mk2_prec_group_table"])
  end
  #
  # 基本情報
  #
  basefile = "%s%s_%d.pst" % [$config["table_basic_rain_dump_dir"],$config["table_basic_rain_dump_name"],$groupid]
  dbdata = PStore.new(basefile)
  basic_data = {}
  dbdata.transaction() do
    basic_data = dbdata['root']
  end
  if basic_data == nil || basic_data.size < 1
    print "table_basic spool data not exist\n"
    exit
  end
  $customer_id = basic_data["customer_id"] 
  $point_id = basic_data["point_id"]
  $mk2_point_list = basic_data["mk2_point_list"]  # V1.7
  $kakuho_ignore = basic_data["kakuho_ignore"]
  #
  # 基準値
  #
  dbdata = PStore.new($config["table_10vscal_dump_path"])
  scale_data = {}
  dbdata.transaction() do
    scale_data = dbdata['root']
  end
  if scale_data == nil || scale_data.size < 1
    print "table_10vscal spool data not exist\n"
    exit
  end
  # 雨
  $threshold_level = scale_data["rain_threshold_level"]
  $pointid_mnetid = scale_data["pointid_mnetid"]
  $mnet_point_list = scale_data["mnet_point_list"]
  $mk2_mnet_point_list = scale_data["mk2_mnet_point_list"]  # V.17
  $threshold_level_near = scale_data["rain_threshold_level_near"]  # V.17
  $pointid_mnetid_near = scale_data["pointid_mnetid_near"]  # V1.7
#  # 風
#  $wind_pointid_amedasid = scale_data["wind_pointid_amedasid"]
#  $wind_amedas_point_list = scale_data["wind_amedas_point_list"]
#  $wind_threshold_level = scale_data["wind_threshold_level"]
#  $typhoon_level_scale = scale_data["typhoon_level_scale"]
#  $typhoon_pointid_amedasid = scale_data["typhoon_pointid_amedasid"]
#  # 土砂
#  $sabou_level_scale = scale_data["sabou_level_scale"]
#  # 洪水
#  $pointid_mnetwlvlid = scale_data["pointid_mnetwlvlid"]
#  $pointid_indexwlvlid = scale_data["pointid_indexwlvlid"]
#  $mnet_level_scale = scale_data["mnet_level_scale"]
#  $flood_index_level_scale = scale_data["flood_index_level_scale"]
#  # 冠水
#  $kansui_index_level_scale = scale_data["kansui_index_level_scale"]
end

# 3時間降水確報10分雨量をスプールから取得
def get_kakuho_prec_3( savetime, justtime )
  # 遅延なしの開始時刻をセット
  ft1_basetime = justtime
  if savetime.min == 0
    ft1_basetime -= 3600
  end
  kakuho_btime = savetime - 600
  kakuho_spool = $config["spool_kakuho_dir"] + $groupid + "/" + kakuho_btime.strftime("%Y%m%d%H%M_1.pst")
  if !File.exists?(kakuho_spool)
    # 1回目のスプールファイルなし
    kakuho_btime -= 600
    ft1_basetime -= 600
    kakuho_spool = $config["spool_kakuho_dir"] + $groupid + "/" + kakuho_btime.strftime("%Y%m%d%H%M_2.pst")
    if !File.exists?(kakuho_spool)
      # 2回目のスプールファイルなし
      print "KAKUHO_PRCRIN_3HOUR_10MIN spool data %s is not available\n" % [kakuho_spool]
      # 1回目と同じ時刻を設定
      kakuho_btime = savetime - 600
      ft1_basetime += 600
      kakuho_spool = nil
    end
  end
  # スプールファイルができていれば読む
  if kakuho_spool != nil
    print "kakuho_spool=%s\n" % [kakuho_spool]
    dbdata = PStore.new(kakuho_spool)
    dbdata.transaction() do
      $kakuho_calc_3ft = dbdata['root']
    end
  end
  print "ft1_start=%s\n" % [ft1_basetime.to_s]
  print "kakuho_btime=%s\n" % [kakuho_btime.to_s]
  return ft1_basetime, kakuho_btime
end

# 最終出力データ
# [point_id][][kind][name] = value
# kind
# micronetid|analysis|kakuho|compass
# scale name
# INDEX_PRCRIN_10min|INDEX_PRCRIN_60min|INDEX_PRCRIN_3hour|INDEX_PRCRIN_24hour|INDEX_PRCRIN_combine
# value name
# PRCRIN_10min|PRCRIN_60min|PRCRIN_3hour|PRCRIN_24hour|PRCRIN_PRST_reset6hour
def make_ru_base( announcetime,ref,justtime )
  ref["group_id"] = $groupid.to_i
  ref["group_count"] = $group_count
  ref["announced_date"].set_value_time(announcetime)
  customer_count = 0
  cids = $customer_id.keys.sort
  cids.each{|cid|
    ref["customer_data"].array_resize(customer_count+1)
    ref["customer_data"][customer_count]["customer_id"] = cid
    ref["customer_data"][customer_count]["flag_kakuho"] = 1
    if $kakuho_ignore.index(cid) != nil
      ref["customer_data"][customer_count]["flag_kakuho"] = 0
      print "customer_id=%s kakuho not use.\n" % [cid] if $verbose
    end
    area_count = 0
    $customer_id[cid].each{|aid|
      ref["customer_data"][customer_count]["area_data"].array_resize(area_count+1)
      ref["customer_data"][customer_count]["area_data"][area_count]["area_id"] = aid
      ref["customer_data"][customer_count]["area_data"][area_count]["flag_INDEX_rain"] = 1
      if $rain_ignore[cid] != nil && $rain_ignore[cid].index(aid) != nil
        ref["customer_data"][customer_count]["area_data"][area_count]["flag_INDEX_rain"] = 0
      end
      ref["customer_data"][customer_count]["area_data"][area_count]["rain_scale_0_3"] = -99
      ref["customer_data"][customer_count]["area_data"][area_count]["rain_scale_4_12"] = -99
      ref["customer_data"][customer_count]["area_data"][area_count]["rain_scale_13_24"] = -99
      ref["customer_data"][customer_count]["area_data"][area_count]["rain_scale_4_24"] = -99
      ref["customer_data"][customer_count]["area_data"][area_count]["rain_scale_25_72"] = -99
      # V1.7
      ref["customer_data"][customer_count]["area_data"][area_count]["scale_name_0_3"] = ""
      ref["customer_data"][customer_count]["area_data"][area_count]["scale_name_4_12"] = ""
      ref["customer_data"][customer_count]["area_data"][area_count]["scale_name_13_24"] = ""
      ref["customer_data"][customer_count]["area_data"][area_count]["scale_name_4_24"] = ""
      ref["customer_data"][customer_count]["area_data"][area_count]["scale_name_25_72"] = ""
      fcst_count = 73
      ref["customer_data"][customer_count]["area_data"][area_count]["FCST_count"] = fcst_count
      ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"].array_resize(fcst_count)
      for i in 0...fcst_count
        valid_time = justtime + i * 3600
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["valid_time"].set_value_time(valid_time)
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["flag_INDEX_edit"] = 0
        # ここから判定に使用したデータの情報
        pointid = cid + "-" + aid
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain"] = -99
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name"] = ""       # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_inner"] = "" # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_inner"] = -99     # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_raw"] = -99
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_near"] = -99      # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_near"] = ""  # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_raw_near"] = -99  # V1.7
        ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["point_count"] = 0
        if $output_data[pointid] != nil && $output_data[pointid][i] != nil && $output_data[pointid][i].size > 0
          ref_ft = ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]
          point_count = 0
          kinds = $output_data[pointid][i].keys.sort
          kinds.each{|kind|
            ref_ft["POINT"].array_resize(point_count+1)
            ref_ft["POINT"][point_count]["point_id"] = kind
            scale_count = 0
            elm_count = 0
            savekeys = $output_data[pointid][i][kind].keys.sort
            savekeys.each{|key|
              value = $output_data[pointid][i][kind][key]
              # V1.7
              if key =~ /^INDEX_NEAR_(.+)/
                ref_ft["POINT"][point_count]["SCALE"].array_resize(scale_count+1)
                ref_ft["POINT"][point_count]["SCALE"][scale_count]["name"] = key
                ref_ft["POINT"][point_count]["SCALE"][scale_count]["value"] = value
                if ref_ft["INDEX_rain_near"] < value
                  ref_ft["INDEX_rain_near"] = value
                  if value > 0
                    index_rain_name = "NEAR_" + $1 + "_obs"
                    ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_near"] = index_rain_name
                  end
                end
                scale_count += 1
              elsif key =~ /^INDEX_(.+)/
                ref_ft["POINT"][point_count]["SCALE"].array_resize(scale_count+1)
                ref_ft["POINT"][point_count]["SCALE"][scale_count]["name"] = key
                ref_ft["POINT"][point_count]["SCALE"][scale_count]["value"] = value
                if ref_ft["INDEX_rain_inner"] < value
                  ref_ft["INDEX_rain_inner"] = value
                  if value > 0
                    index_rain_name = $1
                    case i 
                    when 1,2,3
                      index_rain_name += "_kaku"
                    when 0
                      index_rain_name += "_obs"
                    else
                      index_rain_name += "_fcst"
                    end
                    ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_inner"] = index_rain_name
                  end
                end
                scale_count += 1
              else
                ref_ft["POINT"][point_count]["ELM"].array_resize(elm_count+1)
                ref_ft["POINT"][point_count]["ELM"][elm_count]["name"] = key
                if value == nil || value < 0
                  ref_ft["POINT"][point_count]["ELM"][elm_count]["value"] = LACK_VALUE_32
                else
                  ref_ft["POINT"][point_count]["ELM"][elm_count]["value"] = value
                end
                elm_count += 1
              end
            }
            ref_ft["POINT"][point_count]["SCALE_count"] = scale_count
            ref_ft["POINT"][point_count]["ELM_count"] = elm_count
            point_count += 1
          }
          ref_ft["point_count"] = point_count
          ref_ft["INDEX_rain_raw"] = ref_ft["INDEX_rain_inner"]
          # V1.7
          ref_ft["INDEX_rain_raw_near"] = ref_ft["INDEX_rain_near"]
          if i == 0
            if $ft0_judge_type[cid] == nil
              $ft0_judge_type[cid] = {}
            end
            if $ft0_judge_type[cid][aid] == nil
              $ft0_judge_type[cid][aid] = {}
            end
            if ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_inner"].index("combine") != nil
              $ft0_judge_type[cid][aid]["inner_type"] = 2
            end
            if ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_inner"].index("60") != nil
              $ft0_judge_type[cid][aid]["inner_type"] = 1
            end
            if ref["customer_data"][customer_count]["area_data"][area_count]["INDEX"][i]["INDEX_rain_name_near"].index("60") != nil
              $ft0_judge_type[cid][aid]["near_type"] = 1
            end
          end
        else
          print "customer_id=%s area_id=%s FT=%d output data not exist\n" % [cid,aid,i] if $verbose
        end
      end
      area_count += 1
    }
    ref["customer_data"][customer_count]["area_count"] = area_count
    customer_count += 1
  }
  ref["customer_count"] = customer_count
end

# rain_scale_0_3    実況＋3時間先までの最大スケール値
# rain_scale_4_12   4-12時間先までの最大スケール値
# rain_scale_13_24  13-24時間先までの最大スケール値
# rain_scale_4_24   4-24時間先までの最大スケール値
# rain_scale_25_72  25時間先以降の最大スケール値
# V1.7
# scale_name_0_3
# scale_name_4_12
# scale_name_13_24
# scale_name_4_24
# scale_name_25_72
def get_max_scale(ref)
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      for k in 0...fcst_count
        # V1.7 ->
        index_rain = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_inner"]
        index_rain_name = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_name_inner"]
        if index_rain > 0 && index_rain > ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw"]
          index_rain_name = "UpDown"
        end
        if k == 0 && index_rain < ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_near"]
          index_rain = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_near"]
          index_rain_name = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_name_near"]
          if index_rain > 0 && index_rain > ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_raw_near"]
            index_rain_name = "UpDown"
          end
        end
        ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain"] = index_rain
        ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain_name"] = index_rain_name
        # V1.7 <-
        if k < 4
          if ref["customer_data"][i]["area_data"][j]["rain_scale_0_3"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_0_3"] = index_rain
            ref["customer_data"][i]["area_data"][j]["scale_name_0_3"] = index_rain_name  # V1.7
          end
        end
        if k > 3 && k <13
          if ref["customer_data"][i]["area_data"][j]["rain_scale_4_12"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_4_12"] = index_rain
            ref["customer_data"][i]["area_data"][j]["scale_name_4_12"] = index_rain_name  # V1.7
          end
        end
        if k > 12 && k <25
          if ref["customer_data"][i]["area_data"][j]["rain_scale_13_24"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_13_24"] = index_rain
            ref["customer_data"][i]["area_data"][j]["scale_name_13_24"] = index_rain_name  # V1.7
          end
        end
        if k > 3 && k <25
          if ref["customer_data"][i]["area_data"][j]["rain_scale_4_24"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_4_24"] = index_rain
            ref["customer_data"][i]["area_data"][j]["scale_name_4_24"] = index_rain_name  # V1.7
          end
        end
        if k > 24
          if ref["customer_data"][i]["area_data"][j]["rain_scale_25_72"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_25_72"] = index_rain
            ref["customer_data"][i]["area_data"][j]["scale_name_25_72"] = index_rain_name  # V1.7
          end
        end
      end
    end
  end
end

# 編集スケールをマージ
# [latesttime]
# [editdata][customer_id][area_id][FT] = INDEX_rain

def merge_edit_scale(justtime,ref)
  if $edit_scale == nil || $edit_scale["editdata"] == nil
    print "edit scale spool data not exist.\n"
    return
  end
  editdata = $edit_scale["editdata"]
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    if editdata[customer_id] == nil
      next
    end
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      if editdata[customer_id][area_id] == nil
        next
      end
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      for k in 0...fcst_count
        editft = justtime + k * 3600
        if editdata[customer_id][area_id][editft] == nil
          next
        end
        index_rain = editdata[customer_id][area_id][editft]
        print "customer_id=%s area_id=%s  editft=%s index_rain=%s\n" % [customer_id,area_id,editft.to_s,index_rain.to_s]
        ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain"] = index_rain
        ref["customer_data"][i]["area_data"][j]["INDEX"][k]["flag_INDEX_edit"] = 1
        if k < 4
          if ref["customer_data"][i]["area_data"][j]["rain_scale_0_3"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_0_3"] = index_rain
          end
        end
        if k > 3 && k <13
          if ref["customer_data"][i]["area_data"][j]["rain_scale_4_12"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_4_12"] = index_rain
          end
        end
        if k > 12 && k <25
          if ref["customer_data"][i]["area_data"][j]["rain_scale_13_24"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_13_24"] = index_rain
          end
        end
        if k > 3 && k <25
          if ref["customer_data"][i]["area_data"][j]["rain_scale_4_24"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_4_24"] = index_rain
          end
        end
        if k > 24
          if ref["customer_data"][i]["area_data"][j]["rain_scale_25_72"] < index_rain
            ref["customer_data"][i]["area_data"][j]["rain_scale_25_72"] = index_rain
          end
        end
      end
    end
  end
end

def deliver_ru(gen,am,tagid,output_path)
  # deliver to amdistserv
  if output_path == nil
    begin
      ret = am.buf_deliver_with_career($config["deliver_host"], gen.dump, tagid, $myname, $config["deliver_port"])
      raise("Amdeliver Error") if(ret[1] != "done")
    rescue
      print "Error : " + $@[0].to_s + " : " + $!.to_s
      print "Amdeliver Retry."
      ret = am.buf_deliver_with_career($config["deliver_host"], gen.dump, tagid, $myname, $config["deliver_port"])
      raise("Amdeliver Error") if(ret[1] != "done")
    end
    print "%s %d Deliver\n" % [Time.now.to_s,tagid]
  else
    output = ""
    if File.directory?(output_path)
      output = output_path + tagid.to_s
    else
      output = output_path
    end
    gen.save(output)
    print "saved to: %s\n" % [output]
  end
end

def spool_output_data(ref,created_date,announcetime)
  spool_data = {}
  spool_data["announcetime"] = announcetime
  spool_data["created_date"] = created_date
  spool_data["customer_data"] = {}
  customer_count = ref["customer_count"]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    spool_data["customer_data"][customer_id] = {}
    area_count = ref["customer_data"][i]["area_count"]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      spool_data["customer_data"][customer_id][area_id] = {}
      spool_data["customer_data"][customer_id][area_id]["rain_scale_0_3"] = ref["customer_data"][i]["area_data"][j]["rain_scale_0_3"]
      spool_data["customer_data"][customer_id][area_id]["rain_scale_4_12"] = ref["customer_data"][i]["area_data"][j]["rain_scale_4_12"]
      spool_data["customer_data"][customer_id][area_id]["rain_scale_13_24"] = ref["customer_data"][i]["area_data"][j]["rain_scale_13_24"]
      spool_data["customer_data"][customer_id][area_id]["rain_scale_4_24"] = ref["customer_data"][i]["area_data"][j]["rain_scale_4_24"]
      spool_data["customer_data"][customer_id][area_id]["rain_scale_25_72"] = ref["customer_data"][i]["area_data"][j]["rain_scale_25_72"]
      spool_data["customer_data"][customer_id][area_id]["INDEX"] = []
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      for k in 0...fcst_count
        spool_data["customer_data"][customer_id][area_id]["INDEX"][k] = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain"]
      end
    end
  end
  dbdata = PStore.new($config["output_spool_file"])
  dbdata.transaction() do
    dbdata['root'] = spool_data
  end
end

def make_rufile( announcetime, justtime, output_path, mkConn )
  gen = GenRw.new
  # create header(WniHeader)
  gen.create(create_ruheader(announcetime))
  ref = gen.get_value_ref
  # ベースになるRUを生成
  make_ru_base(announcetime,ref,justtime)
  print "%s ----- start updown near -----\n" % [Time.now.to_s]
  # 乱高下防止処理(周辺地域) V1.7
  arrange_ft_0_2(announcetime,ref,mkConn)
  print "%s ----- start updown kaku -----\n" % [Time.now.to_s]
  # 乱高下防止処理 FT0-FT3 V1.7
  scale_arrange(announcetime,ref,mkConn)
  print "%s ----- start updown fcst -----\n" % [Time.now.to_s]
  # 乱高下防止処理 FT4-FT72 V1.7
  scale_arrange_fcst(announcetime,ref,mkConn)
  print "%s ----- end updown -----\n" % [Time.now.to_s]
  # 全FTの最大スケールを取得
  get_max_scale(ref)
  # 411024200配信
  raw_tagid = $mip ? 411024551 : 411024200
  am = Amdeliver.new()
  deliver_ru(gen,am,raw_tagid,output_path)
  if $config["edit_data"] == 1
  # 編集スケールをマージ
    edit_tagid = $mip ? 411024551 : 411024202
    edit_data_name = $mip ? "WNI_SRF_VSCAL_MIP_PRCRIN" : "WNI_SRF_10V_SCAL_DIM_PRCRIN"
    merge_edit_scale(justtime,ref)
    # RUヘッダ書き換え
    dataid16 = $mip ? "0200600011024551" : "0200600011024202"
    gen.header.data_name =    edit_data_name
    gen.header.global_id      = dataid16[0,4]
    gen.header.category       = dataid16[4,4]
    gen.header.data_id        = dataid16[8,16]
    gen.header.created_date   = Time.now
    # 411024202配信
    deliver_ru(gen,am,edit_tagid,output_path)
  end
  # 災害リスクスケールで使用するデータを保存
#  spool_output_data(ref,gen.header.created_date,announcetime)
end

def main()
  opt = OptionParser.new
  host = MK2_HOST
  port = MK2_PORT
  debugtime = nil
  output_path = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-m', '--mip', TrueClass){|v| $mip = v}
    opt.on('-d yyyymmddhhMM', '--debug yyyymmddhhMM'){|v| debugtime = v}
    opt.on('-o OUTPUT', '--output OUTPUT'){|v| output_path = v}
    opt.on('-h HOST', '--host HOST'){|v| host = v}
    opt.on('-p PORT', '--port PORT'){|v| port = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 2)
  $config = YAML.load_file( ARGV[0] )
  $groupid = ARGV[1]
  # 現在時刻を取得
  curtime = nil
  if debugtime != nil && debugtime.size == 12
    curtime = Time.gm(debugtime[0..3].to_i, debugtime[4..5].to_i, debugtime[6..7].to_i, debugtime[8..9].to_i, debugtime[10..11].to_i,0)
    curtime = curtime.getlocal
    print "timenow=%s\n" % [Time.now.to_s]
    print "debugtime=%s\n" % [curtime.to_s]
  else
    curtime = Time.now
    print "timenow=%s\n" % [curtime.to_s]
  end
  # 現在時刻の正時
  justtime = Time.local(curtime.year, curtime.month, curtime.day, curtime.hour, 0, 0)
  # 現在時刻を10分単位に変換→mk2に結果を保存するときのbasetime→発表時刻
  min = curtime.min - (curtime.min % 10)
  savetime = Time.local(curtime.year, curtime.month, curtime.day, curtime.hour, min, 0)
  print "announcetime=%s\n" % [savetime.to_s]
  # mk2接続
  mkConn = MkConnection.new( host, port )
  #
  # スプールデータの読み込み
  #
  # ビジネスデータのスプールを読む
  get_business_data(mkConn,debugtime)
  # 3時間降水確報10分雨量をスプールから取得
  ft1_basetime, kakuho_btime = get_kakuho_prec_3( savetime, justtime )
  # COMPASS降水予測をスプールから取得
  dbdata = PStore.new($config["spool_compas_path"])
  dbdata.transaction() do
    $compass_prec = dbdata['root']
  end
  if $compass_prec == nil || $compass_prec.size < 1
    print "compass prec spool data not exist.\n"
  end
  # 編集されたスケールをスプールから取得
  dbdata = PStore.new($config["spool_edit_scale_path"])
  dbdata.transaction() do
    $edit_scale = dbdata['root']
  end
  # 大雨グループ分割数をスプールから取得
  dbdata = PStore.new($config["rain_group_count"])
  dbdata.transaction() do
    $group_count = dbdata['root']
  end
  #
  # mk2データの参照
  #
  # WNIマイクロネット雨量データ（全ft共用）をmk2から取得
  mnet_latesttime = get_micronet_prec(mkConn, savetime, justtime)
  # マイクロネット+確報のft1初期化
  mnet_add_10minv_ft1( mkConn, ft1_basetime, kakuho_btime, mnet_latesttime )
  # 解析雨量積算情報の初期化
#  make_analysis_point()
  # 解析雨量データをmk2から取得
#  asis_latesttime = get_analysis_prec(mkConn, savetime, justtime)
  # 解析雨量+確報のft1初期化
#  asis_add_10minv_ft1( mkConn, ft1_basetime, kakuho_btime, asis_latesttime )
  #
  # 判定
  #
  $point_id.each{|pid|
    if $threshold_level[pid] == nil
      print "pid=%s threshold data not exist.\n" % [pid] if $verbose
    end
    $output_data[pid] = []
    for i in 0..72
      $output_data[pid][i] = {}
    end
    # FT1の解析雨量とマイクロネットの大きいほう
#    $prec_ft1[pid] = $micronet_prec_ft1[pid] > $analysis_prec_ft1[pid] ? $micronet_prec_ft1[pid] : $analysis_prec_ft1[pid]
    $prec_ft1[pid] = $micronet_prec_ft1[pid]
  }
  # 実況  ft=0 WNIマイクロネット雨量データによる判定
  mnet_get_index_prec_ft0()
  # 実況  ft=0 WNIマイクロネット雨量データ周辺地域雨量実況値基準値による判定 V1.7
  mnet_get_index_prec_ft0_near()
  # 実況  ft=0 解析雨量データによる判定
#  asis_get_index_prec_ft0()
  # COMPASS積算情報の初期化
  make_compass_point()
  # COMPASSデータをmk2から取得
  get_compass_prec(mkConn,justtime)
  # 予測  ft=1～72まで
#  debug_file = "test_3h_24h_%s.txt" % [Time.now.strftime("%Y%m%d%H%M")]
#  $debug_fs = File.open(debug_file,"w")
  for i in 1..72
    make_one_ft(i,justtime)
  end
#  $debug_fs.close
  #
  # 出力
  #
  make_rufile( savetime, justtime, output_path, mkConn )
  # mk2切断
  mkConn.close_connection
  print "%s ***** proc end normally *****\n" % [Time.now.to_s]
end
main()
