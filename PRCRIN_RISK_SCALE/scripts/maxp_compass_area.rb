#!/usr/local/bin/ruby

require 'optparse'
require 'yaml'
require 'pstore'

require 'wlib'
require 'gribrw'

$mypath  = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite'

$debug   = false
$verbose = false
$config = nil
$marshal_data = {}
$announced = nil
$log = nil

def usage()
$stderr.puts <<EOF
  Usage: #{__FILE__} [OPTION] <inputfile> <config>
  Available options:
     -L FILE --logfile FILE : logfile
     -d, --debug   : debug mode
     -v, --verbose : verbose mode.
EOF
  exit 1
end

#
# COMPASSの読み込み
#
def read_compass(compass, pary)
  # savedata[ft][pid]=最大値
  savedata = {}
  $log.write(compass)
  ifp = open(compass)
  buf = ifp.read(4096)
  ihd = WniHeader.new
  ihd.read(buf)
  $announced = ihd.announced_date
  created = ihd.created_date
  # localtimeなので注意
  $log.write("announced=%s" % $announced.to_s)
  $log.write("created=%s" % created.to_s)
  ifp.seek(ihd.header_size)
  g2 = GribV2.new
  buf = ifp.read
  g2.prepare(buf, true)
  ifp.close
  while true
    sec = nil
    begin
    sec = g2.load
    rescue => e
      $log.write("GribV2: #{e.message} #{f}")
      break
    end
    break if(sec < 0)
    sec1 = g2.section(1)
    initime = Time.utc(
                        sec1["year"].value,   sec1["month"].value,
                        sec1["day"].value,    sec1["hour"].value,
                        sec1["minute"].value, sec1["second"].value
                      )
    sec3 = g2.section(3)
    xsize = sec3["number_of_points_of_i"].value
    ysize = sec3["number_of_points_of_j"].value
    y_first = sec3["latitude_of_first_grid_point"].value  / 1000000.0
    y_last  = sec3["latitude_of_last_grid_point"].value   / 1000000.0
    x_first = sec3["longitude_of_first_grid_point"].value / 1000000.0
    x_last  = sec3["longitude_of_last_grid_point"].value  / 1000000.0
    xgird = sec3["i_direction_increment"].value / 1000000.0
    ygrid = sec3["j_direction_increment"].value / 1000000.0
    sec4 = g2.section(4)
    parameter_category = sec4["parameter_category"].value
    parameter_number = sec4["parameter_number"].value
    $log.write("parameter_category=%s,parameter_number=%s" % [parameter_category.to_s,parameter_number.to_s]) if $verbose
    if parameter_category != 1 || parameter_number != 8
      next
    end
    $log.write("initime = %s" % initime.to_s) if $verbose
    vt = initime + (sec4["forecast_time"].value * 3600)
    vtstr = vt.utc.strftime("%Y-%m-%d %H:%M:%S")
    $log.write("#{vtstr}") if $verbose
    savedata[vt] = {}
    dt = g2.data
    pary.each{|point|
      max = -1
      mesh_list = $marshal_data[point]
      mesh_list.each{|mesh|
        pos = mesh[0] + mesh[1] * xsize
        max = dt[pos] if max < dt[pos]
      }
      savedata[vt][point] = max.truncate
    }
  end
  return savedata
end

begin
  opt = OptionParser.new
  logfile = nil
  begin
    opt.on('-L FILE', '--logfile FILE'){|v| logfile = v}
    opt.on('-d', '--debug',   TrueClass){|v| $debug   = v}
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  if(ARGV.size != 2)
    usage()
  end
  $log = LogWrite.new(logfile)
  $config = YAML.load_file(ARGV[1])
  # 顧客別5kmメッシュ群（緯度経度）紐付けテーブル（Marshal）を読む。
  dbdata = PStore.new($config["area_mesh_compas_path"])
  dbdata.transaction() do
    $marshal_data = dbdata['root']
  end
  if $marshal_data == nil || $marshal_data.size < 1
    print "table_area spool data not exist\n"
    exit
  end
  pary = $marshal_data.keys
  #
  # read GRIB2
  #
  compass = ARGV[0]
  savedata = read_compass(compass, pary)
#  savedata.each_pair{|ft,pointdata|
#    print "%s=[%s]\n" % [ ft.to_s, pointdata.values.join(',') ]
#  }
  dbdata = PStore.new($config["spool_compas_path"])
  dbdata.transaction() do
    dbdata['root'] = savedata
  end
  $log.write("***** proc end normally *****")
rescue => e
  $log.write("#{e.backtrace[0]}: #{e.message} (#{e.class})")
  e.backtrace.each_index{|i|
    $log.write("\tfrom #{e.backtrace[i]}") if i != 0
  }
end
