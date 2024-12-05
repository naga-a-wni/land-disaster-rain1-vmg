#
# RD短期10V-raw 暖候期用共通ruヘッダを作成する関数
# input -
#   announced  : 発表時間
#   dataid16   : 16桁ID
#   data_name  : データ名
#
# output -
#   rhd   : ruヘッダ
#
def create_ruheader_summer(announced,dataid16,data_name)
  format =
    "announced_date:"                                   +
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "source:INT8,"                                      + # 生成元データ  生:0、夏:1、冬:2
    "created_date:"                                     +
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "send_date:"                                        + # 配信時刻
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "created_by:STR,"                                   + # 配信ユーザ名
    "ZONE_count:INT16,"                                 +
    "ZONE_data:{ZONE_count}"                            +
    "["                                                 +
    "ZONE:STR,"                                         + # 暖候期中区間番号（通行判断予測区間）
    "ASM_ID_daihyo:STR,"                                + # 中区間の代表雨量局ASMID
    "FT:INT16,"                                         +
    "FCAS:{FT}["                                        +
    "FCASD:"                                            +
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "RAIN_VSCAL:INT16,"                                 + # 10V_雨(連続雨量)整数値
    "RAIN_CSCAL:INT16,"                                 + # 10V_雨(暖候期)整数値
    "SOILP_VSCAL:INT16,"                                + # 10V_雨(土壌雨量指数)整数値
    "WIND_VSCAL:INT16"                                  + # 10V_風 整数値
    "],"                                                +
    "small_ZONE_count:INT16,"                           +
    "small_ZONE_data:{small_ZONE_count}["               + # 中区間に紐づく小区間分ループ
    "small_ZONE:STR,"                                   + # 暖候期小区間番号（規制区間）
    "FT:INT16,"                                         +
    "FCAS:{FT}["                                        +
    "FCASD:"                                            +
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "RAIN_VSCAL:INT16,"                                 + # 10V_雨(連続雨量)整数値
    "RAIN_CSCAL:INT16,"                                 + # 10V_雨(暖候期)整数値
    "SOILP_VSCAL:INT16,"                                + # 10V_雨(土壌雨量指数)整数値
    "WIND_VSCAL:INT16,"                                 + # 10V_風  整数値
    "second_flag:INT8,"                                 + # 第２通行止め基準対象期間【0,1】
    "use_second:INT8"                                   + # 第２通行止め基準適用期間【0,1】
    "],"                                                +
    "point_count:INT16,"                                +
    "point_data:{point_count}["                         + # 小区間に紐づく雨量局分ループ
    "daihyo_flg:INT8,"                                  + # 代表雨量局のとき1、その他は0
    "RAIN_POINT_ID:STR,"                                + # 暖候期雨量局ID
    "ASM_ID:STR,"                                       + # 暖候期雨量局ASMID
    "BRG_SIL_flg:INT8,"                                 + # 橋が１、土が２、推定値(路観なし)は３
    "judge_type:INT8,"                                  + # 判定種別【1,2,3】 1：雨2：風3：雨と風
    "observation_time:"                                 + # 連続雨量計算の起算実況日時（実況値の最新観測日時）
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "FT:INT16,"                                         +
    "FCAS:{FT}["                                        +
    "FCASD:"                                            +
    "["                                                 +
    "year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                                +
    "WX:INT16,"                                         + # 天気 整数値
    "PRCRIN_1HOUR_TOTAL:INT16,"                         + # 降水量 mm
    "AIRTMP:FLOAT32,"                                   + # 気温 ℃
    "SNWFLL_1HOUR_TOTAL:INT16,"                         + # 降雪量 cm
    "WNDSPD:FLOAT32,"                                   + # 風速 m/sec
    "WNDDIR:INT8,"                                      + # 風向 16方位  
    "RDCND:INT8,"                                       + # 路面状態 0:乾,1:湿,2:シャ,3:圧,4:凍
    "RDTMP:FLOAT32,"                                    + # 路温 ℃
    "DEWTMP:FLOAT32,"                                   + # 露点温度 ℃
    "SSTMI:INT8,"                                       + # 吹雪指数 0:なし,1:弱,2:中,3強
    "PRCRIN_PRST:INT16,"                                + # 連続雨量 mm
    "GUSTS:FLOAT32,"                                    + # 瞬間風速 m/sec
    "RAIN_VSCAL:INT16,"                                 + # 10V_雨(連続雨量)整数値
    "RAIN_CSCAL:INT16,"                                 + # 10V_雨(暖候期)整数値
    "WIND_VSCAL:INT16,"                                 + # 10V_風 整数値
    "second_flag:INT8,"                                 + # 第２通行止め基準対象期間【0,1】
    "use_second:INT8,"                                  + # 第２通行止め基準適用期間【0,1】
    "s1:FLOAT32,"                                       + # 土壌雨量指数タンク1貯留高
    "s2:FLOAT32,"                                       + # 土壌雨量指数タンク2貯留高
    "s3:FLOAT32,"                                       + # 土壌雨量指数タンク3貯留高
    "s_index:INT32,"                                    + # 土壌雨量指数 整数値 10倍値（0.1mm単位）切り捨て
    "SOILP_VSCAL:INT16,"                                + # 10V_雨(土壌雨量指数)整数値
    "SOILP_SCALE_count:INT16,"                          + # 判定を行ったスケール数
    "SOILP_SCALE_index:{SOILP_SCALE_count}"             +
    "["                                                 + # スケールループ
    "scale:INT16,"                                      + # 判定を行ったスケール（30,50）
    "value:INT32"                                       + # 時間雨量がPRCRIN_1HOUR_TOTAL のときの土壌雨量指数の閾値 整数値
    "]"                                                 + # スケールループ
    "]"                                                 +
    "]"                                                 + # 小区間に紐づく雨量局分ループ
    "]"                                                 + # 中区間に紐づく小区間分ループ
    "]"
  rhd = WniHeader.new
  rhd.validate(true)
  rhd.header_version = '1'
  rhd.data_name      = data_name
  rhd.global_id      = dataid16[0,4]
  rhd.category       = dataid16[4,4]
  rhd.data_id        = dataid16[8,16]
  rhd.created_date   = Time.now
  rhd.announced_date = announced
  rhd.revision       = '1'
  rhd.compress_type  = 'gzip'
  rhd.header_comment = data_name
  rhd.data_size      = 0
  rhd.format         = format
  return rhd
end
