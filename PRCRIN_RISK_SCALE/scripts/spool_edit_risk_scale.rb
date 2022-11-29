#!/usr/local/bin/ruby

require 'optparse'
require 'yaml'
require 'pstore'

require 'wlib'

$debug   = false
$verbose = false
$config = nil

def usage()
$stderr.puts <<EOF
  Usage: #{__FILE__} [OPTION] <inputfile> <config>
  Available options:
     -d, --debug   : debug mode
     -v, --verbose : verbose mode.
EOF
  exit 1
end

# 411024202に反映する411024201の編集したスケール値は以下のいずれかまで有効とする。
# ・411024201の編集したスケール値のFTが411024202の発表時刻（FT0）より過去になる
# ・発表時刻が新しい411024201によって編集したスケール値が上書き（再編集）される
# 411024202に反映する411024201の編集したスケール値のvalid_timeは、データが10分間隔、1時間ピッチであるため、同じvalid_timeに反映することはできない。
# 分以下を切り捨てた（正時にまるめた）valid_timeが一致するFTのスケールに反映する。
# 411024202と411024201の発表時刻のhourまでが同じ場合は、FTの同じ連番（FTn）に反映することになる。

# format         =
#  announced_date:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
#  customer_count:INT16,
#  customer_data:{customer_count}[
#    customer_id:STR,
#    area_count:INT8,
#    area_data:{area_count}[
#      area_id:STR,
#      FCST_count:INT16,
#      INDEX:{FCST_count}[
#        valid_time:[year:INT16,month:INT8,day:INT8,hour:INT8,min:INT8],
#        INDEX_rain:INT8
#      ]
#    ]
#  ]

#
# 保存形態
# [latesttime]
# [editdata][customer_id][area_id][FT] = INDEX_rain

def readrudata(rufile,latesttime)
  newdata = {}
  gen = GenRw.open(rufile)
  ref = gen.get_value_ref
  announced_date = ref["announced_date"].get_value_time
  print "announced_date=%s\n" % [announced_date.to_s]
  if latesttime != nil && announced_date < latesttime
    print "input data is older than spool file\n"
    return newdata
  end
  newdata["latesttime"] = announced_date
  editdata = {}
  customer_count = ref["customer_count"]
  print "customer_count=%d\n" % [customer_count]
  for i in 0...customer_count
    customer_id = ref["customer_data"][i]["customer_id"]
    print "customer_id=%s\n" % [customer_id]
    editdata[customer_id] = {}
    area_count = ref["customer_data"][i]["area_count"]
    print "area_count=%d\n" % [area_count]
    for j in 0...area_count
      area_id = ref["customer_data"][i]["area_data"][j]["area_id"]
      print "area_id=%s\n" % [area_id]
      editdata[customer_id][area_id] = {}
      fcst_count = ref["customer_data"][i]["area_data"][j]["FCST_count"]
      print "fcst_count=%d\n" % [fcst_count]
      for k in 0...fcst_count
        valid_time = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["valid_time"].get_value_time
        print "valid_time=%s\n" % [valid_time.to_s]
        ft = Time.at(valid_time.to_i / 3600 * 3600)
        print "ft=%s\n" % [ft.to_s]
        index_rain = ref["customer_data"][i]["area_data"][j]["INDEX"][k]["INDEX_rain"]
        print "index_rain=%d\n" % [index_rain]
        editdata[customer_id][area_id][ft] = index_rain
      end
    end
  end
  newdata["editdata"] = editdata
  return newdata
end

begin
  opt = OptionParser.new
  begin
    opt.on('-d', '--debug',   TrueClass){|v| $debug   = v}
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  if(ARGV.size != 2)
    usage()
  end
  $config = YAML.load_file(ARGV[1])
  # スプールデータをロックしてRUデータをマージする。
  dbdata = PStore.new($config["spool_edit_scale_path"])
  dbdata.transaction() do
    latesttime = nil
    spooldata = dbdata['root']
    if spooldata == nil || spooldata["latesttime"] == nil
      spooldata = {}
      print "spool file is empty\n"
    else
      latesttime = spooldata["latesttime"]
      print "spool latesttime=%s\n" % [latesttime.to_s]
    end
    newdata = readrudata(ARGV[0],latesttime)
    if spooldata["editdata"] == nil
      dbdata['root'] = newdata
    else
      spool_edit_expire = newdata["latesttime"] - $config["spool_edit_expire"] * 3600 * 24
      if newdata["editdata"].size > 0
        newdata["editdata"].each_pair{|cid,adata|
          if spooldata["editdata"][cid] == nil
            spooldata["editdata"][cid] = adata
            next
          end
          adata.each_pair{|aid,ftdata|
            if spooldata["editdata"][cid][aid] == nil
              spooldata["editdata"][cid][aid] = ftdata
              next
            end
            spooldata["editdata"][cid][aid].merge!(ftdata)
            fts = spooldata["editdata"][cid][aid].keys.sort
            fts.each{|ft|
              if ft >= spool_edit_expire
                break
              else
                spooldata["editdata"][cid][aid].delete(ft)
              end
            }
          }
        }
        spooldata["latesttime"] = newdata["latesttime"]
        dbdata['root'] = spooldata
      else
        print "new data is not available\n"
      end
    end
  end
  print "%s ***** proc end normally *****\n" % [Time.now.to_s]
rescue => e
  print "#{e.backtrace[0]}: #{e.message} (#{e.class})\n"
  e.backtrace.each_index{|i|
    print "\tfrom #{e.backtrace[i]}\n" if i != 0
  }
end
