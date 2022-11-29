#!/usr/local/bin/ruby

require 'pstore'
require 'yaml'
require "rexml/document"

require 'meshkernel'

include REXML    # so that we don’t have to prefix everything
                 # with REXML::...

$config = nil
$north_latitude = 0.0
$south_latitude = 0.0
$west_longitude = 0.0
$east_longitude = 0.0
$ydef = 0.0
$xdef = 0.0
$verbose = false
# 全顧客IDとエリアIDの紐づけ
$customer_id = {}

def initconst(fcd)
  if fcd == "kakuho"
    $ydef = 0.008333
    $xdef = 0.012500
    $north_latitude = 47.995833 + ($ydef / 2.0)
    $south_latitude = 20.004167 - ($ydef / 2.0)
    $west_longitude = 118.006250 - ($xdef / 2.0)
    $east_longitude = 149.993750 + ($xdef / 2.0)
  else
    $ydef = 0.050000
    $xdef = 0.062500
    $north_latitude = 47.600000 + ($ydef / 2.0)
    $south_latitude = 22.400000 - ($ydef / 2.0)
    $west_longitude = 120.000000 - ($xdef / 2.0)
    $east_longitude = 150.000000 + ($xdef / 2.0)
  end
end

# 内外判定
# This algorithm does not care whether the polygon is traced in clockwise or counterclockwise fashion.
def ispointinpolygon(pointTarget, polygondata)
  j = polygondata.size - 1
  oddNodes = false
  for i in 0...polygondata.size
    point0 = polygondata[i]
    point1 = polygondata[j]
    if (point0[1] < pointTarget[1] && point1[1] >= pointTarget[1]) || (point1[1]<pointTarget[1] && point0[1]>=pointTarget[1])
      if (point0[0]+(pointTarget[1]-point0[1])/(point1[1]-point0[1])*(point1[0]-point0[0])) < pointTarget[0]
        oddNodes = !oddNodes
      end
    end
    j = i
  end
  return oddNodes
end

# １つのメッシュが内包（少しでもポリゴンに重なっていれば内包）されているか
def checkonemesh( point, polygondata )
  # メッシュの頂点ポイント
  plt = []
  plt[0] = $west_longitude + point[0].to_f * $xdef
  plt[1] = $north_latitude - point[1].to_f * $ydef
  prt = []
  prt[0] = plt[0] + $xdef
  prt[1] = plt[1]
  plb = []
  plb[0] = plt[0]
  plb[1] = plt[1] - $ydef
  prb = []
  prb[0] = plt[0] + $xdef
  prb[1] = plt[1] - $ydef
  # メッシュの頂点がポリゴンに内包されているかチェック
  if ispointinpolygon(plt, polygondata) == true
    return true
  end
  if ispointinpolygon(prt, polygondata) == true
    return true
  end
  if ispointinpolygon(plb, polygondata) == true
    return true
  end
  if ispointinpolygon(prb, polygondata) == true
    return true
  end
  # ポリゴンの頂点がメッシュに内包されているかチェック
  meshdata = []
  meshdata.push(plt)
  meshdata.push(prt)
  meshdata.push(prb)
  meshdata.push(plb)
  meshdata.push(plt)
  polygondata.each{|ppt|
    if ispointinpolygon(ppt, meshdata) == true
      return true
    end
  }
  return false
end

def onearea(bbox,polygondata)
  oneareamesh = []
  startx = (( bbox["wx"] - $west_longitude) / $xdef).truncate
  endx = (( bbox["ex"] - $west_longitude) / $xdef).truncate
  starty = (( $north_latitude - bbox["ny"] ) / $ydef).truncate
  endy = (( $north_latitude - bbox["sy"] ) / $ydef).truncate
  for y in starty.to_i..endy.to_i
    for x in startx.to_i..endx.to_i
      point = [x,y]
      if checkonemesh( point, polygondata ) == true
        oneareamesh.push(point)
      end
    end
  end
  return oneareamesh
end

def main()
  if ARGV.size < 2
    print "Usage:mesh_polygon_map.rb <configfilepath> <compas|kakuho>\n"
    return
  end
  $config = YAML.load_file(ARGV[0])
  if File.exist?($config["area_polygon_path"]) == false
    print "xml file not exist %s\n" % $config["area_polygon_path"]
    return
  end
  # 基本情報をスプールから取得
  dbdata = PStore.new($config["table_basic_rain_dump_path"])
  basic_data = {}
  dbdata.transaction() do
    basic_data = dbdata['root']
  end
  if basic_data == nil || basic_data.size < 1
    print "table_basic spool data not exist : %s\n" % [$config["table_basic_rain_dump_path"]]
    return
  end
  $customer_id = basic_data["customer_id"] 
  lock = File.open($config["area_mesh_lock_path"], "w")
  if(!lock.flock(File::LOCK_EX|File::LOCK_NB))
    print "run another process.\n"
    return
  end
  initconst(ARGV[1])
  marshal_data = {}
  # XMLファイルオープン
  dest = open($config["area_polygon_path"],"r+")
  if !dest.flock( File::LOCK_EX )
    log.write("File [#{destpath}] lock failed.")
  end
  data = dest.read
  dest.flock( File::LOCK_UN )
  dest.close
  doc1 = REXML::Document.new(data)
  # custmorループ
  doc1.elements.each("list/CUST"){|customer|
    # custmor_id
    customer_id = customer.elements["LCLID"].text
    if $customer_id[customer_id] == nil
      print "customer_id=%s not supported\n" % [customer_id]
      next
    end
    print "customer_id=%s\n" % [customer_id]
#    if customer_id == "11520" || customer_id == "11163"
#      print "%s is skipped.\n" % [customer_id]
#      next
#    end
    # エリアループ
    customer.elements.each("area_info"){|area|
      # area_id
      area_id = area.elements["LCLID"].text
      if $customer_id[customer_id].index(area_id) == nil
        print "area_id=%s not supported\n" % [customer_id]
        next
      end
      print "area_id=%s\n" % [area_id] if $verbose
      # 地名
      print "%s\n" % area.elements["LNAME"].text if $verbose
      polygondata = []
      vcnt = 0
      # ポリゴンのバウンダリボックスを取得
      bbox = {}
      bbox["ny"] = $south_latitude
      bbox["sy"] = $north_latitude
      bbox["ex"] = $west_longitude
      bbox["wx"] = $east_longitude
      if area.elements["polygon_data"] == nil || area.elements["polygon_data"].text == nil || area.elements["polygon_data"].text == ""
        print "%s polygon_data not defined\n" % area.elements["LNAME"].text
        next
      end
      print "start %s\n" % [Time.now.to_s] if $verbose
      polygon_data = area.elements["polygon_data"].text.split("/")
      polygon_data.each{|point|
        polygondata[vcnt] = []
        latlon = point.split("+")
        latvalue = latlon[1].to_f
        lonvalue = latlon[2].to_f
        # lon
        if bbox["wx"] > lonvalue
          bbox["wx"] = lonvalue
        end
        if bbox["ex"] < lonvalue
          bbox["ex"] = lonvalue
        end
        polygondata[vcnt][0] = lonvalue
        # lat
        if bbox["ny"] < latvalue
          bbox["ny"] = latvalue
        end
        if bbox["sy"] > latvalue
          bbox["sy"] = latvalue
        end
        polygondata[vcnt][1] = latvalue
        vcnt += 1
      }
      pointid = customer_id + "-" + area_id
      marshal_data[pointid] = onearea(bbox,polygondata)
    } # エリアループ
  } # custmorループ
  print "start to save %s\n" % Time.now.to_s
  if ARGV[1] == "kakuho"
    # marshal_data[pid]=[arymesh]
    # "ZUS001-1"
    # [[313, 246], [314, 246]]
    $config["rain_group_count"].times{|i|
      basefile = "%s%s_%d.pst" % [$config["table_basic_rain_dump_dir"],$config["table_basic_rain_dump_name"],i+1]
      basic_group = {}
      dbdata = PStore.new(basefile)
      dbdata.transaction() do
        basic_group = dbdata['root']
      end
      if basic_group == nil || basic_group.size < 1
        print "table_basic group spool data not exist : %s\n" % [basefile]
        return
      end
      save_data = {}
      basic_group["point_id"].each{|pid|
        save_data[pid] = marshal_data[pid]
      }
      savefile = "%s%s_%d.pst" % [$config["area_mesh_kakuho_dir"],$config["area_mesh_kakuho_name"],i+1]
      dbdata = PStore.new(savefile)
      dbdata.transaction() do
        dbdata['root'] = save_data
      end
    }
  else
    dbdata = PStore.new($config["area_mesh_compas_path"])
    dbdata.transaction() do
      dbdata['root'] = marshal_data
    end
  end
  lock = File.open($config["area_mesh_lock_path"], "w")
  if(!lock.flock(File::LOCK_UN))
    "File unlock failed."
  end
end
print "proc start %s\n" % Time.now.to_s
main()
print "proc end normally %s\n" % Time.now.to_s
