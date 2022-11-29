#!/usr/local/bin/ruby

require 'optparse'
require 'pstore'
require 'yaml'

require 'meshkernel'

MK2_HOST = "localhost"
MK2_PORT = 11112

$config = nil
$verbose = false
$debug = false

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config>
  Available options:
    -v --verbose                         : verbose mode.
    -d --debug                           : debug
    -h HOST --host HOST                  : mk2 host
    -p PORT --port PORT                  : mk2 port
EOF
  exit
end

#
# area_mesh_compas[pid]=[arymesh]
# "ZUS001-1"
# [[313, 246], [314, 246]]
#
def devide_by_mesh(area_mesh_compas)
  # cidmesh[cid]=meshcount
  cidmesh = {}
  area_mesh_compas.each_pair{|pid,ary|
    ida = pid.split("-")
    if cidmesh[ida[0]] == nil
      cidmesh[ida[0]] = 0
    end
    cidmesh[ida[0]] += ary.size
    # V1.7 add area wait
    cidmesh[ida[0]] += 3
  }
  # sizecid[mesh数]=[arycid]
  sizecid ={}
  cidmesh.each_pair{|cid,value|
    if sizecid[value] == nil
      sizecid[value] = []
    end
    sizecid[value].push(cid)
  }
  msizes = sizecid.keys.sort
  # cidグループ
  # groups[[cid,cid,cid...],[],[],...]
  groups = []
  # グループのメッシュ数合計
  # gsizes[size,size,size...]
  gsizes = []
  $config["rain_group_count"].times{|i|
    groups[i] = []
    gsizes[i] = 0
  }
  # mesh数の大きい順
  msizes.reverse_each{|s|
    ary = sizecid[s]
    ary.each{|cid|
      # メッシュ数合計が最小のグループに追加
      min = gsizes.sort[0]
      idx = gsizes.index(min)
      groups[idx].push(cid)
      # グループのメッシュ数合計加算
      gsizes[idx] += s
    }
  }
#  groups.each_index{|i|
#    p groups[i]
#    p gsizes[i]
#  }
  return groups
end

def main()
  opt = OptionParser.new
  host = MK2_HOST
  port = MK2_PORT
  debugtime = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
    opt.on('-h HOST', '--host HOST'){|v| host = v}
    opt.on('-p PORT', '--port PORT'){|v| port = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 1)
  $config = YAML.load_file(ARGV[0])
  # COMPASS のエリアメッシュのspoolを読む
  dbdata = PStore.new($config["area_mesh_compas_path"])
  area_mesh_compas = {}
  dbdata.transaction() do
    area_mesh_compas = dbdata['root']
  end
  if area_mesh_compas == nil || area_mesh_compas.size < 1
    print "area_mesh_compas spool data not exist\n"
    return
  end
  # 基本情報のspoolを読む
  dbdata = PStore.new($config["table_basic_rain_dump_path"])
  basic_all = {}
  dbdata.transaction() do
    basic_all = dbdata['root']
  end
  if basic_all == nil || basic_all.size < 1
    print "table_basic_dump spool data not exist\n"
    return
  end
  # cid 分割
  cid_groups = devide_by_mesh(area_mesh_compas)
  # 基本情報分割
  save_data = []
  $config["rain_group_count"].times{|i|
    save_data[i] = {}
    save_data[i]
    save_data[i]["customer_id"] = {}
    save_data[i]["point_id"] = []
    save_data[i]["mk2_point_list"] = []  # V1.7
    save_data[i]["kakuho_ignore"] = []
  }
  cid_groups.each_index{|i|
    print "--- group%d ---\n" % [i+1]
    cid_groups[i].each{|cid|
      print "%s\n" % [cid]
      save_data[i]["customer_id"][cid] = basic_all["customer_id"][cid]
      if basic_all["kakuho_ignore"].index(cid) != nil
        save_data[i]["kakuho_ignore"].push(cid)
      end
      basic_all["point_id"].each{|pid|
        ary = pid.split("-")
        if cid == ary[0]
          save_data[i]["point_id"].push(pid)
          save_data[i]["mk2_point_list"].push(MkPoint.new( pid ))  # V1.7
        end
      }
    }
  }
  # mk2データ生成
  pd = MkPointData.new
  point_list = []
  group_list = []
  save_data.each_index{|i|
    save_data[i]["customer_id"].each_key{|cid|
      point_list.push(MkPoint.new(cid))
      group_list.push(i+1)
    }
  }
  pd.set_point_list(point_list)
  param = MkDataParam.new(0, "0", Time.now)
  pd.set_data(param, "GROUP_ID", group_list)
  print "start to save %s\n" % Time.now.to_s
  # 分割数の保存
  dbdata = PStore.new($config["rain_group_count_path"])
  dbdata.transaction() do
    dbdata['root'] = $config["rain_group_count"]
  end
  # mk2接続
  host = MK2_HOST
  port = MK2_PORT
  mkConn = MkConnection.new( host, port )
#  mkConn.lock_table($config["mk2_prec_group_table"])
  $config["rain_group_count"].times{|i|
    savefile = "%s%s_%d.pst" % [$config["table_basic_rain_dump_dir"],$config["table_basic_rain_dump_name"],i+1]
    dbdata = PStore.new(savefile)
    dbdata.transaction() do
      dbdata['root'] = save_data[i]
    end
  }
  mkConn.write_point($config["mk2_prec_group_table"], pd)
#  mkConn.unlock_table($config["mk2_prec_group_table"])
  # mk2切断
  mkConn.close_connection
end

print "proc start %s\n" % Time.now.to_s
main()
print "proc end normally %s\n" % Time.now.to_s
