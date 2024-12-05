def read_ft_data(summer_data,refr,elm,asm_id,i,j,k)
  if summer_data[elm][asm_id] == nil  # 先勝ち
    summer_data[elm][asm_id] = {}
    summer_data[elm][asm_id]["BRG_SIL_flg"] = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_data"][k]["BRG_SIL_flg"]
    fcst_count = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_data"][k]["FT"]
    summer_data[elm][asm_id]["FT"] = fcst_count
    summer_data[elm][asm_id]["FCAS"] = []
    refr_ft_data = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_data"][k]["FCAS"]
    for l in 0...fcst_count
      ft_data = {}
      ft_data["FCASD"] = refr_ft_data[l]["FCASD"].get_value_time
      ft_data["WX"] = refr_ft_data[l]["WX"]          # 天気
      ft_data["PRCRIN_1HOUR_TOTAL"] = refr_ft_data[l]["PRCRIN_1HOUR_TOTAL"]  # 時間降水量
      ft_data["AIRTMP"] = refr_ft_data[l]["AIRTMP"]  # 気温
      ft_data["SNWFLL_1HOUR_TOTAL"] = refr_ft_data[l]["SNWFLL_1HOUR_TOTAL"]  # 時間降雪量
      ft_data["WNDSPD"] = refr_ft_data[l]["WNDSPD"]  # 風速
      ft_data["WNDDIR"] = refr_ft_data[l]["WNDDIR"]  # 風向
      ft_data["RDCND"] = refr_ft_data[l]["RDCND"]    # 路面状態
      ft_data["RDTMP"] = refr_ft_data[l]["RDTMP"]    # 路温
      ft_data["DEWTMP"] = refr_ft_data[l]["DEWTMP"]  # 露点温度
      ft_data["SSTMI"] = refr_ft_data[l]["SSTMI"]    # 吹雪指数
      ft_data["PRCRIN_PRST"] = refr_ft_data[l]["PRCRIN_PRST"]  # 連続雨量
      ft_data["GUSTS"] = refr_ft_data[l]["GUSTS"]    # 瞬間風速
      summer_data[elm][asm_id]["FCAS"].push(ft_data)
    end
  end
end

def read_summer_ru(input_data)
  # 夏Bizdataで代表地点<daihyo_flg>が1の地点には、子供<ASM_ID_child>が設定されており、子供にバラマキ
  # <daihyo_flg>0</daihyo_flg>の区間に対しては、<ASM_ID_child>の地点を代表地点
  #（<daihyo_flg>1</daihyo_flg>がつく雨量局に紐づく<ASM_ID>の地点）で上書き実行。
  # 代表地点は同じ中区間の代表地点を優先する。
  # 同じ中区間に代表地点が含まれない場合は、他の中区間に紐づく代表地点で上書きを行う。
  #
  # summer_data["ZONE_data"][zone_id]["ASM_ID_daihyo"][<daihyo_flg>1<ASM_ID>] = data
  summer_data = {}
  summer_data["ZONE_data"] = {}
  # 入力ファイル読み込み
  gr = GenRw.open(input_data)
  rhd = gr.get_header_copy
  if rhd.format.index("SOIL") == nil
    $old_format = true
    $log.write("soil prec not exist in inputdata.")
  end
  refr = gr.get_value_ref
  summer_data["announced_date"] = refr["announced_date"].get_value_time
  summer_data["created_date"] = refr["created_date"].get_value_time
  summer_data["send_date"] = refr["created_date"].get_value_time
  if refr.has_member?("send_date") && refr["send_date"]["year"] > 2000
    summer_data["send_date"] = refr["send_date"].get_value_time
  else
    $log.write("send_date not available. use created_date.")
  end
  $log.write("send_date=%s" % [summer_data["send_date"].to_s])
  summer_data["created_by"] = refr["created_by"]
  zone_count = refr["ZONE_count"]
  for i in 0...zone_count
    zone_id = refr["ZONE_data"][i]["ZONE"]  # RD中区間番号
    summer_data["ZONE_data"][zone_id] = {}
    summer_data["ZONE_data"][zone_id]["ASM_ID_daihyo"] = {}
    if $rd_table_summer["zone_elements"][zone_id] == nil
      $log.write("summer zone_id=%s not in tabel." % [zone_id])
      next
    end
    small_zone_count = refr["ZONE_data"][i]["small_ZONE_count"]
    for j in 0...small_zone_count
      small_zone = refr["ZONE_data"][i]["small_ZONE_data"][j]["small_ZONE"]
      if $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone] == nil
        $log.write("summer zone_id=%s small_zone=%s not in tabel." % [zone_id,small_zone])
        next
      end
      point_count = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_count"]
      for k in 0...point_count
        rain_point = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_data"][k]["RAIN_POINT_ID"]
        if $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"][rain_point] == nil
          $log.write("summer zone_id=%s small_zone=%s rain_point=%s not in tabel." % [zone_id,small_zone,rain_point])
          next
        end
        # 雨量局に紐づくASM地点<ASM_ID>
        asm_id = refr["ZONE_data"][i]["small_ZONE_data"][j]["point_data"][k]["ASM_ID"]
        if $rd_table_summer["zone_elements"][zone_id]["SMALL_ZONE"][small_zone]["RAIN_POINT"][rain_point]["daihyo_flg"] == 1
          # 中区間代表地点
          read_ft_data(summer_data["ZONE_data"][zone_id],refr,"ASM_ID_daihyo",asm_id,i,j,k)
        end
      end
    end
  end
  return summer_data
end
