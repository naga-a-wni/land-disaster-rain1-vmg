# データ無し
EMPTY_VALUE_8 = -111
EMPTY_VALUE_16 = -11111       # 1を5回
EMPTY_VALUE_32 = -1111111111  # 1を10回

def deliver(grw,tagid)
  am = Amdeliver.new()
  begin
    ret = am.buf_deliver_with_career($config["disthost"], grw.dump, tagid, $myname, $config["distport"])
    raise("Amdeliver Error") if(ret[1] != "done")
  rescue
    print "Error : " + $@[0].to_s + " : " + $!.to_s + "\n"
    print "Amdeliver Retry.\n"
    ret = am.buf_deliver_with_career($config["disthost"], grw.dump, tagid, $myname, $config["distport"])
    raise("Amdeliver Error") if(ret[1] != "done")
  end
  print tagid.to_s + " ru deliverd\n"
end

#
# 無降水凍結スケールruヘッダを作成する関数
# input -
#   dataname   : データ名。
#   dataid16   : 16桁ID。
#   datacmnt   : ヘッダコメント。
#   announced  : 発表時間。
#
# output -
#   rhd   : ruヘッダ
#
def create_ruheader_rdferrze(dataname, dataid16, datacmnt, announced)
  format =
    "announced_date:"                                 +
    "["                                               +
    "year:INT16,mon:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                              +
    "zone_count:INT16,"                               +
    "zone:{zone_count}"                               +
    "["                                               +
    "ZONE_ID:STR,"                                    +
    "ZONE_NAME:STR,"                                  +
    "FCAS_count:INT16,"                               +
    "FCAS:{FCAS_count}"                               +
    "["                                               +
    "FCAS_date:"                                      +
    "["                                               +
    "year:INT16,mon:INT8,day:INT8,hour:INT8,min:INT8" +
    "],"                                              +
    "AIRTMP:INT32,"                                   + # 気温
    "RDTEMP:INT32,"                                   + # 路温
    "DEWTMP:INT32,"                                   + # 露点温度
    "SCAL:INT8"                                       + # 無降水スケール
    "]"                                               +
    "]"
  rhd = WniHeader.new
  rhd.validate(true)
  rhd.header_version = '1'
  rhd.data_name      = dataname
  rhd.global_id      = dataid16[0,4]
  rhd.category       = dataid16[4,4]
  rhd.data_id        = dataid16[8,16]
  rhd.created_date   = Time.now
  rhd.announced_date = announced
  rhd.revision       = '1'
  rhd.compress_type  = 'gzip'
  rhd.header_comment = datacmnt
  rhd.data_size      = 0
  rhd.format         = format
  return rhd
end

def make_rdferrze_ru(srf_ref)
  announced = srf_ref["announced_date"].get_value_time
  grw_rfs = GenRw.new()
  # dataname, dataid16, datacmnt, announced
  rhd_rfs = create_ruheader_rdferrze($output_ids["rdfreeze_dataname"], $output_ids["rdfreeze_dataid16"],
                                                    $output_ids["rdfreeze_dataname"], announced)
  grw_rfs.create(rhd_rfs)
  ref_rfs = grw_rfs.get_value_ref
  begin
    ref_rfs['announced_date'].set_value_time(announced)
  rescue
    $log.write("announced_date is invalid.")
  end
  # ZONE loop
  zone_count = srf_ref["ZONE_count"]
  ref_rfs['zone_count'] = zone_count
  ref_rfs['zone'].array_resize(zone_count)
  for i in 0...zone_count
    zone_id = srf_ref["ZONE_data"][i]["ZONE"]  # RD中区間番号
    ref_rfs['zone'][i]["ZONE_ID"] = zone_id
    if $zone_data[zone_id] != nil
      ref_rfs['zone'][i]["ZONE_NAME"] = $zone_data[zone_id]["NAME"]
    end
    fcas_count = srf_ref["ZONE_data"][i]["FT"]
    ref_rfs['zone'][i]["FCAS_count"] = fcas_count
    ref_rfs['zone'][i]["FCAS"].array_resize(fcas_count)
    for j in 0...fcas_count
      ft = srf_ref["ZONE_data"][i]["FCAS"][j]["FCASD"].get_value_time
      begin
        ref_rfs['zone'][i]["FCAS"][j]['FCAS_date'].set_value_time(ft)
      rescue
        $log.write("ZONE_ID=%s FT=%s is invalid." % [zone_id,j])
      end
      ref_rfs['zone'][i]["FCAS"][j]['AIRTMP'] = EMPTY_VALUE_32
      ref_rfs['zone'][i]["FCAS"][j]['RDTEMP'] = EMPTY_VALUE_32
      ref_rfs['zone'][i]["FCAS"][j]['DEWTMP'] = EMPTY_VALUE_32
      ref_rfs['zone'][i]["FCAS"][j]['SCAL'] = EMPTY_VALUE_8
      if srf_ref["ZONE_data"][i]["FCAS"][j]["AIRTMP"] != LACK_VALUE_16
        ref_rfs['zone'][i]["FCAS"][j]['AIRTMP'] = (srf_ref["ZONE_data"][i]["FCAS"][j]["AIRTMP"] * 10).round
      end
      if srf_ref["ZONE_data"][i]["FCAS"][j]["RDTMP"] != LACK_VALUE_16
        ref_rfs['zone'][i]["FCAS"][j]['RDTEMP'] = (srf_ref["ZONE_data"][i]["FCAS"][j]["RDTMP"] * 10).round
      end
      if srf_ref["ZONE_data"][i]["FCAS"][j]["DEWTMP"] != LACK_VALUE_16
        ref_rfs['zone'][i]["FCAS"][j]['DEWTMP'] = (srf_ref["ZONE_data"][i]["FCAS"][j]["DEWTMP"] * 10).round
      end
      if $rd_freeze[zone_id] != nil && $rd_freeze[zone_id][ft] != nil &&  $rd_freeze[zone_id][ft] >= 0
        ref_rfs['zone'][i]["FCAS"][j]['SCAL'] = $rd_freeze[zone_id][ft]
      end
    end
  end
  # ファイル出力
  if $savedir != nil
    savefilename = "%s/%s.ru" % [$savedir, $output_ids["rdfreeze_tagid"]]
    grw_rfs.save(savefilename)
    $log.write("save to file : %s" % [savefilename])
  end
  if $output_ids["rdfreeze_deliver"] == 1
    deliver(grw_rfs,$output_ids["rdfreeze_tagid"])
    $log.write("deliver %s" % [$output_ids["rdfreeze_tagid"]])
  end
end
