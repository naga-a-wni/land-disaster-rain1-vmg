#
# hprec: 時雨量(mm)
# polyline[[x,y],[x,y],[x,y],...]
# x=土壌雨量 y=時間雨量
#
class GetSprecThreshold
  def initialize(hprec,polyline)
    @hprec = hprec
    @polyline = polyline
    @sthd = -9999
  end

  def get_hprec_threshold
    if @polyline[0][1] <= @hprec
      # 時雨量が@polyline左端以上
      @sthd = @polyline.first[0]  # 土壌雨量下限値（polyline左端）
      return
    end
    if @polyline.last[1] >= @hprec
      # 時雨量がpolyline右端以下
      @sthd = @polyline.last[0]  # 土壌雨量最大値（polyline右端）
      return
    end
    if @polyline.size < 2
      # ポリライン不正
      return
    end
    # 両側index
    maxIndex = 0                   # 時雨量最大は左端
    minIndex = @polyline.size - 1  # 時雨量最小は右端
    while minIndex - maxIndex > 1
      # Binary search.
      curIndex = (maxIndex + minIndex) / 2
      if @polyline[curIndex][1] == @hprec
        # 時雨量がpolylineの位置と一致
        @sthd = @polyline[curIndex][0]
        return
      end
      if @polyline[curIndex][1] > @hprec
        # 時雨量がpolylineの位置より小さい
        maxIndex = curIndex
      else
        # 時雨量がpolylineの位置より大きい
        minIndex = curIndex
      end
    end
    # 線形内挿
    # (x2-x1)/(y2-y1) * (y-y1) + x1
    @sthd = (@polyline[maxIndex][0] - @polyline[minIndex][0]) / (@polyline[maxIndex][1] - @polyline[minIndex][1]) * (@hprec - @polyline[maxIndex][1]) + @polyline[maxIndex][0]
  end

   attr_reader :hprec
   attr_reader :polyline
   attr_reader :sthd
end

#
# hprec: 時雨量(mm)
# sprec: 土壌雨量(mm)
# レベル情報
# lvldata[regulation_level][[x,y],[x,y],[x,y],...]
#
def get_soilprec_scale( hprec, sprec, lvldata )
  t_lvl = []
  o_lvl = []
  levles = lvldata.keys.sort.reverse
  # 大きいスケール順
  levles.each_index{|i|
    lvl = levles[i]
    polyline = lvldata[lvl]
    o = GetSprecThreshold.new(hprec,polyline)
    o_lvl << o
    t = Thread.new do
      o_lvl[i].get_hprec_threshold()
    end
    t_lvl << t
  }
  t_lvl.each{|t| t.join()}  # スレッド待ち合わせ
  lvl_sthd = {}
  max_level = 0
  o_lvl.each_index{|i|  # 大きいスケール順結果ループ
    lvl = levles[i]
    lvl_sthd[lvl] = o_lvl[i].sthd
    if lvl_sthd[lvl] > 0
      print "lvl=%s sprec=%s thd=%s\n" % [lvl,sprec,lvl_sthd[lvl] ] if $verbose
      if max_level < lvl && sprec >= lvl_sthd[lvl]
        # 土壌雨量が閾値を超える
        max_level = lvl
      end
    end
  }  # 結果ループ
  return max_level, lvl_sthd
end
