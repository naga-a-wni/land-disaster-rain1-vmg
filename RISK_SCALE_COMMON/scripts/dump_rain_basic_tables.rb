#!/usr/local/bin/ruby22
# -*- coding: utf-8 -*-

require 'pstore'
require 'yaml'
require "rexml/document"

include REXML    # so that we don’t have to prefix everything
                 # with REXML::...

$config = nil

#
# 基本情報XMLデータを読み込む。
# ----------------------
# ビジネスデータ基本情報
# ----------------------
# 全顧客IDとエリアIDの紐づけ
$customer_id = {}
# 全顧客ID-エリアID（ハイフン連結）テキスト
$point_id = []
# 確報を使用しない
# 顧客毎なので顧客IDの配列
$kakuho_ignore = []
# 大雨のリスクスケールを使用しない
#
def get_xmldata_basic()
  # XMLファイルオープン
  dest = open($config["table_basic_info_path"],"r+")
  if !dest.flock( File::LOCK_EX )
    log.write("File [#{destpath}] lock failed.")
  end
  data = dest.read
  dest.flock( File::LOCK_UN )
  dest.close
  doc1 = REXML::Document.new(data)
  # customerループ
  doc1.elements.each("list/CUST"){|customer|
    # customer_id
    customer_id = customer.elements["LCLID"].text
    # サービスステータス
    if customer.elements["service_status"].text.to_i != 1
      print "customer_id=%s not supported\n" % [customer_id]
      next
    end
    # 確報を使用しない
    if customer.elements["needs_kakuho_prcrin"].text.to_i != 1
      $kakuho_ignore.push(customer_id)
    end
    # エリアループ
    customer.elements.each("area_info"){|area|
      if area.elements["announce_type/prcrin"].text.to_i == 1
        # area_id
        area_id = area.elements["LCLID"].text
        # ポイントID
        pointid = customer_id + "-" + area_id
        $point_id.push(pointid)
        if $customer_id[customer_id] == nil
          $customer_id[customer_id] = []
        end
        $customer_id[customer_id].push(area_id)
      end
    } # エリアループ
  } # customerループ
end

def main()
  if ARGV.size < 1
    print "Usage:dump_tables.rb <configfilepath>\n"
    return
  end
  $config = YAML.load_file(ARGV[0])
  if File.exist?($config["table_basic_info_path"]) == false
    print "xml file not exist %s\n" % $config["table_basic_info_path"]
    return
  end
  get_xmldata_basic()
  kakuho_ignore_cid = []
  $kakuho_ignore.each{|cid|
    if $customer_id[cid] != nil
      kakuho_ignore_cid.push(cid)
    end
  }
  $dbdata = PStore.new($config["table_basic_rain_dump_path"])
  marshal_data = {}
  $dbdata.transaction() do
    marshal_data["customer_id"] = $customer_id
    marshal_data["point_id"] = $point_id
    marshal_data["kakuho_ignore"] = kakuho_ignore_cid
    $dbdata['root'] = marshal_data
  end
  
end
print "timenow=%s\n" % Time.now.to_s
main()
print "timenow=%s\n" % Time.now.to_s
