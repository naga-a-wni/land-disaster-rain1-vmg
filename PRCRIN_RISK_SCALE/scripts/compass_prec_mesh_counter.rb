#!/usr/local/bin/ruby

require 'pstore'
require 'yaml'
require 'optparse'

require 'meshkernel'

$verbose = false
$config = nil
$point_list = []
$marshal_data = {}

MK2_HOST = "localhost"
MK2_PORT = 11112

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config>
  Available options:
    -v --verbose                : verbose mode.
    -d yyyymmddhhmm --debug yyyymmddhhmm : debugtime
    -h HOST --host HOST         : mk2 host
    -p PORT --port PORT         : mk2 port
EOF
  exit
end

# メッシュ座標をポイント化
def get_mesh_counter( ft, xsz, pary, mk2data )
  mesh_counter = []
  pary.each{|point|
    mesh_list = $marshal_data[point]
    mesh_list.each{|mesh|
      if ft == 0
        pointid = "%s_%s_%s" % [point,mesh[0],mesh[1]]
        $point_list.push(MkPoint.new( pointid ))
      end
      index = mesh[0] + mesh[1] * xsz
      value = mk2data[index]
      if mk2data[index] > 0
        value = (value * 10).truncate # 10倍値に変換
      end
      mesh_counter.push(value)
    }
  }
  return mesh_counter
end

def city_hour( mkConn, pary, debugtime )
  # COMPASS雨量カウンタmk2テーブルの最新時刻を取得する
  btime = nil
  if debugtime != nil && debugtime.size == 12
    btime = Time.gm(debugtime[0..3].to_i, debugtime[4..5].to_i, debugtime[6..7].to_i, debugtime[8..9].to_i, debugtime[10..11].to_i, 0)
  else
    btime = mkConn.get_latest_time( $config["mk2_compass_prec_table"] )
  end
  print "basetime=%s\n" % [ btime.to_s ]
  ft_list = mkConn.get_ft_list($config["mk2_compass_prec_table"], btime, "PrecCounter")
  p ft_list
  # 最大値の保存用pointデータ
  pdpoint = MkPointData.new
  # mk2に保存した 面展開データを読む
  # 積算イベントに続けて処理を行うので排他などタイミング調整は不要
  area_param = mkConn.get_area_info( $config["mk2_compass_prec_table"] )
  areas = area_param.get_area_list
  area_desc = area_param.get_area_desc( areas[0] )
  xsz = area_desc.get_wesize
  ysz = area_desc.get_nssize
  area_frag = MkAreaFragment.new( areas[0], 0, 0, xsz, ysz )
  params = []
  ft_list.each{|ft|
    params.push(MkDataParam.new(ft, '0', btime))
  }
  # COMPASS雨量カウンタmk2テーブル
  elem_type_list = ["PrecCounter"]
  pd = mkConn.read_grid_raw( $config["mk2_compass_prec_table"], params, [ area_frag ], elem_type_list )
  params.each{|prm|
    mk2data = pd.get_data( prm, area_frag, "PrecCounter" )
    mesh_counter = get_mesh_counter( prm.ft, xsz, pary, mk2data )
    pdpoint.set_data(prm, "PrecCounter:INT32", mesh_counter)
  }
  # mk2に保存
  $dbdata = PStore.new($config["spool_compass_prec_path"])  # 排他処理用
  $dbdata.transaction() do
    $dbdata['root'] = Time.now
    # COMPASS雨量前処理出力mk2テーブル
    pdpoint.set_point_list($point_list)
    mkConn.write_point($config["mk2_compass_prec_mesh_counter"], pdpoint)
  end
end

def main()
  opt = OptionParser.new
  host = MK2_HOST
  port = MK2_PORT
  debugtime = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d yyyymmddhhmm', '--debug yyyymmddhhmm'){|v| debugtime = v}
    opt.on('-h HOST', '--host HOST'){|v| host = v}
    opt.on('-p PORT', '--port PORT'){|v| port = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 1)
  print "timenow=%s\n" % [Time.now.to_s]
  $config = YAML.load_file(ARGV[0])
  # 5kmメッシュ群（緯度経度）紐付けテーブル（Marshal）を読む。
  dbdata = PStore.new($config["area_mesh_compas_path"])
  dbdata.transaction() do
    $marshal_data = dbdata['root']
  end
  if $marshal_data == nil || $marshal_data.size < 1
    print "table_area spool data not exist\n"
    exit
  end
  if $config["created_compas_path"] != nil
    dbdata = PStore.new($config["created_compas_path"])
    dbdata.transaction() do
      created_data = dbdata['root']
      if created_data != nil
        if created_data["start"] -Time.now < 60 * 5
          created_data["latest"] = created_data["created"]
          dbdata['root'] = created_data
        end
      end
    end
  end
  pary = $marshal_data.keys.sort
  mkConn = MkConnection.new( host, port )
  city_hour( mkConn, pary, debugtime )
  mkConn.close_connection
  print "%s ***** proc end normally *****\n" % [Time.now.to_s]
end
main()
