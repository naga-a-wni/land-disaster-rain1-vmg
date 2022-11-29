#!/usr/local/bin/ruby

require 'pstore'
require 'yaml'

require 'wlib'
require 'meshkernel'

$config = nil
$point_list = []
$calc_data = []
$retry_list = {}

# 受信データを読む
def readrudata(rufile)
  rudata = {}
  pointdata = {}
  gen = GenRw.open(rufile)
  wni = gen.get_header_copy
  rudata["announced_date"] = wni.announced_date
  print "announced_date=%s\n" % [ rudata["announced_date"].to_s ]
  ref = gen.get_value_ref
  cnt = ref["point_count"]
  print "point_count=%d\n" % [ cnt ]
  for i in 0...cnt
    pointno = ref["data"][i]["pointno"]
    pointdata[pointno] = {}
    pointdata[pointno]["Prec_Counter"] = ref["data"][i]["Prec_Counter"]
    pointdata[pointno]["Precipitation_10min"] = ref["data"][i]["Precipitation_10min"]
    pointdata[pointno]["Precipitation_60min"] = ref["data"][i]["Precipitation_60min"]
    pointdata[pointno]["Prec_Integ_Reset6"] = ref["data"][i]["Prec_Integ_Reset6"]
  end
  rudata["data"] = pointdata
  return rudata
end

# mk2データを読んで積算（降水量カウンタを使用しない）
def calcmk2data_retry( host, port, calcdata )
  announced = calcdata["announced_date"]
  mkConn = MkConnection.new(host, port)
  time_list = mkConn.get_time_list($config["mk2_prec_table"], announced - 3600 * 24, announced)
  if $retry_list["PRCRIN_30"] != nil
    #
    # 10min accumulate (30min)
    #
    plist = $retry_list["PRCRIN_30"].values
    params = []
    for i in 1..2
      if time_list.index(announced - 60 * 10 * i) != nil
        params.push(MkDataParam.new(0, '0', announced - 60 * 10 * i))
      end
    end
    if params.size > 0
      element_list = [ 'PRCRIN_10:INT32' ]
      pd = mkConn.read_point($config["mk2_prec_table"], params, plist, element_list)
      params.each{|prm|
        data_list = pd.get_data(prm, 'PRCRIN_10')
        data_list.each_index{|i|
          p10 = data_list[i]
          if p10 < 0 || p10 == 9999
            p10 = 0
          end
          calcdata["data"][plist[i].id]["PRCRIN_30"] += p10
        }
      }
    end
    plist.each_index{|i|
      p10 = calcdata["data"][plist[i].id]["Precipitation_10min"]
      if p10 < 0 || p10 == 9999
        p10 = 0
      end
      calcdata["data"][plist[i].id]["PRCRIN_30"] += p10
    }
  end
  if $retry_list["PRCRIN_180"] != nil
    #
    # 1h accumulate 3h
    #
    plist = $retry_list["PRCRIN_180"].values
    params = []
    for i in 1..2
      if time_list.index(announced - 3600 * i) != nil
        params.push(MkDataParam.new(0, '0', announced - 3600 * i))
      end
    end
    if params.size > 0
      element_list = [ 'PRCRIN_60:INT32' ]
      pd = mkConn.read_point($config["mk2_prec_table"], params, plist, element_list)
      params.each{|prm|
        data_list = pd.get_data(prm, 'PRCRIN_60')
        data_list.each_index{|i|
          p60 = data_list[i]
          if p60 < 0 || p60 == 9999
            p60 = 0
          end
          calcdata["data"][plist[i].id]["PRCRIN_180"] += p60
        }
      }
    end
    plist.each_index{|i|
      p60 = calcdata["data"][plist[i].id]["Precipitation_60min"]
      if p60 < 0 || p60 == 9999
        p60 = 0
      end
      if $calc_data.index("PRCRIN_180") != nil
        calcdata["data"][plist[i].id]["PRCRIN_180"] += p60
      end
    }
  end
  if $retry_list["PRCRIN_24H"] != nil
    #
    # 1h accumulate 24h
    #
    plist = $retry_list["PRCRIN_24H"].values
    params = []
    for i in 1..23
      if time_list.index(announced - 3600 * i) != nil
        params.push(MkDataParam.new(0, '0', announced - 3600 * i))
      end
    end
    if params.size > 0
      element_list = [ 'PRCRIN_60:INT32' ]
      pd = mkConn.read_point($config["mk2_prec_table"], params, plist, element_list)
      params.each{|prm|
        data_list = pd.get_data(prm, 'PRCRIN_60')
        data_list.each_index{|i|
          p60 = data_list[i]
          if p60 < 0 || p60 == 9999
            p60 = 0
          end
          calcdata["data"][plist[i].id]["PRCRIN_24H"] += p60
        }
      }
    end
    plist.each_index{|i|
      p60 = calcdata["data"][plist[i].id]["Precipitation_60min"]
      if p60 < 0 || p60 == 9999
        p60 = 0
      end
      if $calc_data.index("PRCRIN_24H") != nil
        calcdata["data"][plist[i].id]["PRCRIN_24H"] += p60
      end
    }
  end
  mkConn.close_connection
end

# mk2データを読んで積算
def calcmk2data( host, port, calcdata )
  announced = calcdata["announced_date"]
  mkConn = MkConnection.new(host, port)
  time_list = mkConn.get_time_list($config["mk2_prec_table"], announced - 3600 * 24, announced)
  params = []
  # 10 min
  if time_list.index(announced - 60 * 10) != nil
    params.push(MkDataParam.new(0, '0', announced - 60 * 10))
    $calc_data.push("PRCRIN_10")
  end
  # 30 min
  if time_list.index(announced - 60 * 30) != nil
    params.push(MkDataParam.new(0, '0', announced - 60 * 30))
    $calc_data.push("PRCRIN_30")
  end
  # 60 min
  if time_list.index(announced - 60 * 60) != nil
    params.push(MkDataParam.new(0, '0', announced - 60 * 60))
    $calc_data.push("PRCRIN_60")
  end
  # 3h
  if params.size > 0 && time_list.index(announced - 3600 * 3) != nil
    params.push(MkDataParam.new(0, '0', announced - 3600 * 3))
    $calc_data.push("PRCRIN_180")
  end
  # 24h
  if params.size > 0 && time_list.index(announced - 3600 * 24) != nil
    params.push(MkDataParam.new(0, '0', announced - 3600 * 24))
    $calc_data.push("PRCRIN_24H")
  end
  # 地点
  calcdata["data"].keys.each  {|pointno|
    $point_list.push(MkPoint.new( pointno ))
  }
  if params.size > 0
    element_list = [ 'PRCRIN_Counter:INT32' ]
    pd = mkConn.read_point($config["mk2_prec_table"], params, $point_list, element_list)
    # 10 min
    if $calc_data.index("PRCRIN_10") != nil
      data_list = pd.get_data(params[$calc_data.index("PRCRIN_10")], 'PRCRIN_Counter')
      data_list.each_index{|i|
        ccnt = calcdata["data"][$point_list[i].id]["Prec_Counter"]
        p10 = ccnt - data_list[i]
        if data_list[i] >= 0 && p10 >= 0
          calcdata["data"][$point_list[i].id]["PRCRIN_10"] = p10
        else
          calcdata["data"][$point_list[i].id]["PRCRIN_10"] = -1
        end
      }
    end
    # 30 min
    if $calc_data.index("PRCRIN_30") != nil
      data_list = pd.get_data(params[$calc_data.index("PRCRIN_30")], 'PRCRIN_Counter')
      data_list.each_index{|i|
        ccnt = calcdata["data"][$point_list[i].id]["Prec_Counter"]
        p30 = ccnt - data_list[i]
        if data_list[i] >= 0 && p30 >= 0
          calcdata["data"][$point_list[i].id]["PRCRIN_30"] = p30
        else
          calcdata["data"][$point_list[i].id]["PRCRIN_30"] = 0
          if $retry_list["PRCRIN_30"] == nil
            $retry_list["PRCRIN_30"] = {}
          end
          $retry_list["PRCRIN_30"][$point_list[i].id] = $point_list[i]
          print "id=%s current=%d b30=%d\n" % [ $point_list[i].id, ccnt, data_list[i] ]
        end
      }
    end
    # 60 min
    if $calc_data.index("PRCRIN_60") != nil
      data_list = pd.get_data(params[$calc_data.index("PRCRIN_60")], 'PRCRIN_Counter')
      data_list.each_index{|i|
        ccnt = calcdata["data"][$point_list[i].id]["Prec_Counter"]
        p60 = ccnt - data_list[i]
        if data_list[i] >= 0 && p60 >= 0
          calcdata["data"][$point_list[i].id]["PRCRIN_60"] = p60
        else
          calcdata["data"][$point_list[i].id]["PRCRIN_60"] = -1
        end
      }
    end
    # 3h
    if $calc_data.index("PRCRIN_180") != nil
      data_list = pd.get_data(params[$calc_data.index("PRCRIN_180")], 'PRCRIN_Counter')
      data_list.each_index{|i|
        ccnt = calcdata["data"][$point_list[i].id]["Prec_Counter"]
        p180 = ccnt - data_list[i]
        if data_list[i] >= 0 && p180 >= 0
          calcdata["data"][$point_list[i].id]["PRCRIN_180"] = p180
        else
          calcdata["data"][$point_list[i].id]["PRCRIN_180"] = 0
          if $retry_list["PRCRIN_180"] == nil
            $retry_list["PRCRIN_180"] = {}
          end
          $retry_list["PRCRIN_180"][$point_list[i].id] = $point_list[i]
          print "id=%s current=%d b180=%d\n" % [ $point_list[i].id, ccnt, data_list[i] ]
        end
      }
    end
    # 24h
    if $calc_data.index("PRCRIN_24H") != nil
      data_list = pd.get_data(params[$calc_data.index("PRCRIN_24H")], 'PRCRIN_Counter')
      data_list.each_index{|i|
        ccnt = calcdata["data"][$point_list[i].id]["Prec_Counter"]
        p24h = ccnt - data_list[i]
        if data_list[i] >= 0 && p24h >= 0
          calcdata["data"][$point_list[i].id]["PRCRIN_24H"] = p24h
        else
          calcdata["data"][$point_list[i].id]["PRCRIN_24H"] = 0
          if $retry_list["PRCRIN_24H"] == nil
            $retry_list["PRCRIN_24H"] = {}
          end
          $retry_list["PRCRIN_24H"][$point_list[i].id] = $point_list[i]
          print "id=%s current=%d b24h=%d\n" % [ $point_list[i].id, ccnt, data_list[i] ]
        end
      }
    end
  end
  print "calced elements=[%s]\n" % [ $calc_data.join(',') ]
  mkConn.close_connection
end

# mk2に保存
def save_data( host, port, calcdata )
  announced = calcdata["announced_date"]
  mkConn = MkConnection.new(host, port)
  pd = MkPointData.new
  pd.set_point_list($point_list)
  param = MkDataParam.new(0, "0", announced)
  # raw
  data_p10 = []
  data_p60 = []
  data_pi6 = []
  data_cnt = []
  # calc
  data_p30 = []
  data_p180 = []
  data_p24h = []
  $point_list.each_index{|i|
    pdata = calcdata["data"][$point_list[i].id]
    if pdata["Precipitation_10min"] == 9999
      if $calc_data.index("PRCRIN_10") != nil
        data_p10.push(pdata["PRCRIN_10"])
      else
        data_p10.push(-1)
      end
    else
      data_p10.push(pdata["Precipitation_10min"])
    end
    if pdata["Precipitation_60min"] == 9999
      if $calc_data.index("PRCRIN_60") != nil
        data_p60.push(pdata["PRCRIN_60"])
      else
        data_p60.push(-1)
      end
    else
      data_p60.push(pdata["Precipitation_60min"])
    end
    data_pi6.push(pdata["Prec_Integ_Reset6"])
    data_cnt.push(pdata["Prec_Counter"])
    if $calc_data.index("PRCRIN_30") != nil
      data_p30.push(pdata["PRCRIN_30"])
    end
    if $calc_data.index("PRCRIN_180") != nil
      data_p180.push(pdata["PRCRIN_180"])
    end
    if $calc_data.index("PRCRIN_24H") != nil
      data_p24h.push(pdata["PRCRIN_24H"])
    end
  }
  pd.set_data(param, "PRCRIN_10:INT32", data_p10)
  pd.set_data(param, "PRCRIN_60:INT32", data_p60)
  pd.set_data(param, "PRCRIN_Reset6:INT32", data_pi6)
  pd.set_data(param, "PRCRIN_Counter:INT32", data_cnt)
  if $calc_data.index("PRCRIN_30") != nil
    pd.set_data(param, "PRCRIN_30:INT32", data_p30)
  end
  if $calc_data.index("PRCRIN_180") != nil
    pd.set_data(param, "PRCRIN_180:INT32", data_p180)
  end
  if $calc_data.index("PRCRIN_24H") != nil
    pd.set_data(param, "PRCRIN_24H:INT32", data_p24h)
  end
  mkConn.write_point($config["mk2_prec_table"], pd)
  mkConn.close_connection
end

def main()
  if ARGV.size < 4
    print "Usage:recv_mnet_prec.rb <mk2host> <mk2port> <configfilepath> <RUfliepath>\n"
    exit
  end
  $config = YAML.load_file(ARGV[2])
  $dbdata = PStore.new($config["spool_prec_path"])
  $dbdata.transaction() do
    $dbdata['root'] = Time.now
    calcdata = readrudata(ARGV[3])
    calcmk2data(ARGV[0], ARGV[1], calcdata)
    if $retry_list.size > 0
      $retry_list.each_pair{|key,value|
        print "%s points to retry=[%s]\n" % [ key, value.keys.join(',') ]
      }
      calcmk2data_retry( ARGV[0], ARGV[1], calcdata )
    end
    save_data(ARGV[0], ARGV[1], calcdata)
  end
  print "%s\n" % Time.now.to_s
end
main()
