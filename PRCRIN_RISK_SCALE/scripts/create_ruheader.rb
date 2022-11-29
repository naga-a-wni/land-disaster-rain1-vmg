#
# 411024200,411024202 ruヘッダを作成する関数
# input -
#   announced  : 発表時刻
#
# output -
#   rhd   : ruヘッダ
#
def create_ruheader(announced)
  dataid16 = $mip ? "0200600011024551" : "0200600011024200"
  format =
    "group_id:INT16,"                                   + # グループID
    "group_count:INT16,"                                + # 分割数
    "announced_date:"                                   + # 発表時刻
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "customer_count:INT16,"                             + # 顧客数
    "customer_data:{customer_count}"                    +
    "["                                                 + # 顧客ループ
    "customer_id:STR,"                                  + # 顧客ID
    "flag_kakuho:INT8,"                                 + # 降水確報を使用しない場合には0使用する場合には1
    "area_count:INT8,"                                  + # エリア数
    "area_data:{area_count}"                            +
    "["                                                 + # エリアループ
    "area_id:STR,"                                      + # エリアID
    "flag_INDEX_rain:INT8,"                             + # 大雨に関するリスクスケールを使用しない場合には0使用する場合には1
    "rain_scale_0_3:INT8,"                              + # 実況＋3時間先までの最大スケール値
    "rain_scale_4_12:INT8,"                             + # 4-12時間先までの最大スケール値
    "rain_scale_13_24:INT8,"                            + # 13-24時間先までの最大スケール値
    "rain_scale_4_24:INT8,"                             + # 4-24時間先までの最大スケール値
    "rain_scale_25_72:INT8,"                            + # 25時間先以降の最大スケール値
    "scale_name_0_3:STR,"                               + # 実況＋3時間先までの最大スケール値の判定基準
    "scale_name_4_12:STR,"                              + # 4-12時間先までの最大スケール値の判定基準
    "scale_name_13_24:STR,"                             + # 13-24時間先までの最大スケール値の判定基準
    "scale_name_4_24:STR,"                              + # 4-24時間先までの最大スケール値の判定基準
    "scale_name_25_72:STR,"                             + # 25時間先以降の最大スケール値の判定基準
    "FCST_count:INT16,"                                 + # 予報数
    "INDEX:{FCST_count}"                                +
    "["                                                 + # FTループ
    "valid_time:"                                       + # 予報対象時刻
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "INDEX_rain:INT8,"                                  + # 大雨に関するリスクスケール値（0-5）
    "INDEX_rain_name:STR,"                              + # INDEX_rainの値の判定基準。
    "INDEX_rain_inner:INT8,"                            + # 周辺地域雨量実況値基準値を使用しない大雨に関するリスクスケール値（0-5）FT0以外は常にINDEX_rainと同じ値。
    "INDEX_rain_name_inner:STR,"                        + # INDEX_rain_innerの値の判定基準。
    "INDEX_rain_raw:INT8,"                              + # 乱高下防止処理前の大雨に関するリスクスケール値（0-5）。
    "INDEX_rain_near:INT8,"                             + # 周辺地域雨量実況値基準値を使用した大雨に関するリスクスケール値（0-5）FT0以外は常欠測値。
    "INDEX_rain_name_near:STR,"                         + # INDEX_rain_nearの値の判定基準。
    "INDEX_rain_raw_near:INT8,"                         + # 乱高下防止処理前の周辺地域雨量実況値基準値を使用した大雨に関するリスクスケール値（0-5）FT0以外は常欠測値。
    "flag_INDEX_edit:INT8,"                             + # 大雨に関するリスクスケールを編集していない場合には0 編集した場合には1
    "point_count:INT16,"                                + # 判定に使用した地点数
    "POINT:{point_count}"                               +
    "["                                                 + # 地点ループ
    "point_id:STR,"                                     + # 判定に使用した地点ID
    "SCALE_count:INT16,"                                + # 判定を行ったスケール数
    "SCALE:{SCALE_count}"                               +
    "["                                                 + # リスクスケールループ
    "name:STR,"                                         + # 判定を行ったスケール名
    "value:INT8"                                        + # 判定スケール（-99：判定に使用する値が欠測）
    "],"                                                + # リスクスケールループ
    "ELM_count:INT16,"                                  + # 判定に使用した要素数
    "ELM:{ELM_count}"                                   +
    "["                                                 + # 要素ループ
    "name:STR,"                                         + # 判定に使用した要素名
    "value:INT32"                                       + # 判定に使用した要素の値（-999999999：実況値が欠測、または予測値がない）
    "]"                                                 + # 要素ループ
    "]"                                                 + # 地点ループ
    "]"                                                 + # FTループ
    "]"                                                 + # エリアループ
    "]"                                                   # 顧客ループ
  rhd = WniHeader.new
  rhd.validate(true)
  rhd.header_version = '1'
  if $mip
    rhd.data_name    = "WNI_SRF_VSCAL_MIP_PRCRIN"
  else
    rhd.data_name    = "WNI_SRF_10VSCAL_DIM_RAIN_before_edit"
  end
  rhd.global_id      = dataid16[0,4]
  rhd.category       = dataid16[4,4]
  rhd.data_id        = dataid16[8,16]
  rhd.created_date   = Time.now
  rhd.announced_date = announced
  rhd.revision       = '1'
  rhd.compress_type  = 'gzip'
  rhd.header_comment = $groupid
  rhd.data_size      = 0
  rhd.format         = format
  return rhd
end
