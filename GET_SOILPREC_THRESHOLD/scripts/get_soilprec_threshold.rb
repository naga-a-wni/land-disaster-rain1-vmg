#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require 'optparse'
require 'fileutils'
require 'json'

$mypath = File.dirname(__FILE__)
$LOAD_PATH.push($mypath)

require 'logwrite.rb'

$config = nil
$log = nil
$verbose = false
$debug = false
# 入力データ
$input = nil
# 雨量局とCL基準値の紐づけ情報
# $soilprec_threshold_info[支社][小区間][雨量局][level][[x,y],[x,y],[x,y],...]
$soilprec_threshold_info = {}
# 小区間とASMIDの組み合わせと雨量局の紐づけ
# $szid_asmid_rain_pid[small_zid][asm_id_rp] = []
$szid_asmid_rain_pid = {}
# CLバージョン（トークン）
$cl_version = nil

def usage
puts <<EOF
  Usage: #{__FILE__} [OPTION] <config>
  Available options:
    -v --verbose                : verbose mode.
    -d --debug                  : debug
    -i INPUT --input INPUT      : input tar.gz
EOF
  exit
end

def delete_old_dir(work_dir)
  spool_path = work_dir + "/*"
  fnams = Dir.glob(spool_path)
  fnams.each{|fnam|
    bname = File::basename(fnam)
    if bname =~ /^(\d{4})(\d{2})(\d{2})/
      spoolday = Time.local($1.to_i, $2.to_i, $3.to_i, 0, 0, 0)
      if spoolday < Time.now - 3600 * 24 * $config["input_expire"]
        $log.write("delete %s" % [fnam])
        FileUtils.rm_r(fnam)
      end
    end
  }
end

#
# ポリライン情報の作成
# save_data[[x,y],[x,y],[x,y],...]
#
def make_polyline_info(jikan_uryo, dojo_uryo)
  # ポリラインの左右端を取得
  # ポリラインデータ
  polyline = {}
  dojo_uryo.each_index{|i|
    # x=土壌雨量 y=時雨量
    x = dojo_uryo[i].to_f
    y = jikan_uryo[i].to_f
    if polyline[x] == nil
      polyline[x] = []
    end
    polyline[x].push(y)
  }
  # 判定用ポリライン作成
  save_data = []
  # 左→右ポリライン作成
  xary = polyline.keys.sort
  xary.each_index{|j|
    x = xary[j]
    yary = polyline[x].sort.reverse
    if j == 0
      # 最小y
      save_data.push([x,yary.last])
    elsif j == xary.size - 1
      # 最大y
      save_data.push([x,yary.first])
    else
      # y全部
      yary.each{|y|
        save_data.push([x,y])
      }
    end
  }
  # 時間雨量の重複を削除
  retdata = []
  save_data.each_index{|i|
    if i > 0
     if save_data[i-1][1] != save_data[i][1]
       retdata.push(save_data[i])
     end
    else
      retdata.push(save_data[i])
    end
  }
  return retdata
end

def main()
  opt = OptionParser.new
  logfile = nil
  input_dir = nil
  inputfile = nil
  begin
    opt.on('-v', '--verbose', TrueClass){|v| $verbose = v}
    opt.on('-d', '--debug', TrueClass){|v| $debug = v}
    opt.on('-i INPUT', '--input INPUT'){|v| inputfile = v}
    opt.parse!(ARGV)
  rescue
    usage()
  end
  usage() if(ARGV.size < 1)
  $config = YAML.load_file(ARGV[0])
  $log =  LogWrite.new(logfile)
  # 小区間とASMIDの組み合わせと雨量局の紐づけ
  dbdata = PStore.new($config["spool_dir"] + $config["szid_asmid_rain_pid_spool"])
  dbdata.transaction() do
    $szid_asmid_rain_pid = dbdata['root']
  end
  if $szid_asmid_rain_pid == nil
    $log.write("%s not exist." % [$config["szid_asmid_rain_pid_spool"]])
    return
  end
  # CLバージョン（トークン）
  dbdata = PStore.new($config["spool_dir"] + $config["CL_version"])
  dbdata.transaction() do
    $cl_version = dbdata['root']
  end
  if !$debug && $cl_version == nil
    $log.write("%s not exist." % [$config["CL_version"]])
    return
  end
  $log.write("Version %s" % [$cl_version])
  # ディレクトリチェック
  work_dir = $config["spool_dir"] + "work"
  if !File.exist?(work_dir)
    FileUtils.mkdir(work_dir)
  end
  # 作業ディレクトリの作成
  input_dir = "%s/%s" % [work_dir, Time.now.strftime("%Y%m%d%H%M%S")]
  FileUtils.mkdir(input_dir)
  zipfile = "%s/%s.tar.gz" % [input_dir,$config["cl_info_fnam"]]
  cmd = nil
  if inputfile == nil
    # APIでJOSNファイルをget
    if $config["http_proxy"] != nil
      cmd = "curl -x %s -o %s %s%s/%s.tar.gz" % [$config["http_proxy"],zipfile,$config["cl_api_url"],$cl_version,$config["cl_info_fnam"]]
    else
      cmd = "curl -o %s %s%s/%s.tar.gz" % [zipfile,$config["cl_api_url"],$cl_version,$config["cl_info_fnam"]]
    end
    $log.write(cmd)
    ret = system(cmd)
    if(!ret)
      raise("#{cmd} error.")
    end
  else
    FileUtils.cp(inputfile, zipfile)
  end
  # gzip解凍
  cmd = "tar -zxvf %s -C %s" % [zipfile,input_dir]
  $log.write("%s" % [cmd])
  ret = system(cmd)
  if(!ret)
    raise("#{cmd} error.")
  end
  # JSONを読む
  jsonfile = input_dir + "/" + $config["cl_info_json"]
  File.open(jsonfile) do |f|
    $input = JSON.load(f)
  end
  # CL_versionを読む
  prcrin_ver = $input["rd_token"]
  if !$debug && $cl_version != prcrin_ver
    $log.write("CL_version not match table=%s json=%s" % [$cl_version, prcrin_ver])
    return
  end
  # json_raw_info[支社][小区間][ASMID][scale][[x,y],[x,y],[x,y],...]
  json_raw_info = {}
  $input["infos"].each{|info|  # Infos配列ループ
    szid = nil
    asmid = nil
    lvldata = {}
    info.each_pair{|key,value|  # Infosの１要素Infoのハッシュループ
      if key == "small_ZONE"
        szid = value
      elsif key == "ASMID"
        asmid = value
      elsif key =~ /^(\d+)$/
        # key=レベル値（30,50）
        dojo_uryo = nil
        jikan_uryo = nil
        value.each_pair{|key2,cldata|  # レベルのハッシュループ
          case key2
          when "SWI"
            dojo_uryo = cldata
          when "PRCRIN_1H"
            jikan_uryo = cldata
          end
        } # レベルのハッシュループ
        if jikan_uryo == nil || dojo_uryo == nil
          $log.write("small_ZONE=%s ASMID=%s lvl=%s SWI or PRCRIN_1H not exist" % [szid, asmid, key])
        else
          lvldata[key.to_i] = make_polyline_info(jikan_uryo, dojo_uryo)
        end
      end
    }  # Infosの１要素Infoのハッシュループ
    if szid == nil || asmid == nil
      $log.write("small_ZONE=%s ASMID=%s small_ZONE or ASMID not exist" % [szid, asmid])
      next
    end
    bid = szid[0,2]
    if json_raw_info[bid] == nil
      json_raw_info[bid] = {}
    end
    if json_raw_info[bid][szid] == nil
      json_raw_info[bid][szid] = {}
    end
    json_raw_info[bid][szid][asmid] = lvldata
  }  # Infos配列ループ
#  dbdata = PStore.new("json_raw_info.pst")
#  dbdata.transaction() do
#    dbdata['root'] = json_raw_info
#  end
  #
  # 小区間とASMIDの組み合わせを雨量局に変換
  #
  json_raw_info.each_pair{|bid,szdata|
    if $soilprec_threshold_info[bid] == nil
      $soilprec_threshold_info[bid] = {}
    end
    szdata.each_pair{|szid,asmdata|
      if $szid_asmid_rain_pid[szid] == nil
        $log.write("szid=%s not exist." % [szid])
        next
      end
      if $soilprec_threshold_info[bid][szid] == nil
        $soilprec_threshold_info[bid][szid] = {}
      end
      asmdata.each_pair{|asmid,value|
        if $szid_asmid_rain_pid[szid][asmid] == nil
          $log.write("szid=%s asmid=% snot exist." % [szid,asmid])
          next
        end
        if $szid_asmid_rain_pid[szid][asmid].size > 1
          $log.write("szid=%s asmid=%s rpnt=[%s]" % [szid,asmid,$szid_asmid_rain_pid[szid][asmid].join(",")]) if $verbose
        end
        $szid_asmid_rain_pid[szid][asmid].each{|rid|
          $soilprec_threshold_info[bid][szid][rid] = value
        }
      }
    }
  }
  # ディレクトリチェック
  cl_dir = $config["spool_dir"] + "cl_data"
  if !File.exist?(cl_dir)
    FileUtils.mkdir(cl_dir)
  end
  # 支社毎に保存
  $soilprec_threshold_info.each_pair{|bid,savedata|
    cl_file = "%s/%s.pst" % [cl_dir,bid]
    dbdata = PStore.new(cl_file)
    dbdata.transaction() do
      dbdata['root'] = savedata
    end
  }
  # 古いファイルの削除
  delete_old_dir(work_dir)
  $log.write("***** proc end normally *****")
end
main()
