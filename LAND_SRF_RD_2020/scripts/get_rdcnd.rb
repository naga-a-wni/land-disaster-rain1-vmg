# 引数：fti、出力データ参照
# 返り：路面状態
def get_rdcnd(t, refw_fcst, startft=0)
  if t == startft
    refw_fcst[t]["RDCND"] = get_rdcnd_first( refw_fcst[t]["RDTMP"], refw_fcst[t]["WX"], refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] )
    return
  end
  refw_fcst[t]["RDCND"] = LACK_VALUE_8
  if refw_fcst[t]["RDTMP"] < 0.45 && refw_fcst[t]["RDTMP"] != LACK_VALUE_16
    if refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] >= 3 && refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] != LACK_VALUE_16 && refw_fcst[t]["RDCND"] == LACK_VALUE_8
      refw_fcst[t]["RDCND"] = 3  #（２）路温＜0.5度で、時間降雪≧3cmの場合→  「圧」
    end
    if refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] >= 1 && refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] != LACK_VALUE_16 && refw_fcst[t]["RDTMP"] < 0.45 && refw_fcst[t]["RDCND"] == LACK_VALUE_8
      bstat = false
      cnt = 0
      totalsnow = 0
      t.downto(startft){|m|
        if refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] >= 1 && refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] != LACK_VALUE_16 && refw_fcst[m]["RDTMP"] < 0.45 
          cnt = cnt + 1
          totalsnow = totalsnow + refw_fcst[m]["SNWFLL_1HOUR_TOTAL"]
          if totalsnow >= 5 && cnt > 1
            bstat = true
          end
        else
          break
        end
      }
      if bstat
        refw_fcst[t]["RDCND"] = 3  #（１）路温＜0.5度で、時間降雪≧1cmかつ路温＜0.5度の状態が連続し、トータル5cm以上に達した場合→「圧」
      end
    end
    if t > startft
      if refw_fcst[t-1]["RDCND"] == 3 && refw_fcst[t]["RDCND"] == LACK_VALUE_8
        bstat = false
        cnt = 0
        (t-1).downto(startft){|m|
          if refw_fcst[m]["RDCND"] == 3
            cnt = cnt + 1
          else
            break
          end
        }
        if cnt <= 5
          refw_fcst[t]["RDCND"] = 3  #（３） 路温＜0.5度で、前路面状態が「圧」で、路面状態が「圧」が過去から連続5コマ以下の場合  →  「圧」
        end
      end
    end
    if t + 1 > 6 + startft
      if refw_fcst[t-1]["RDCND"] == 3 && refw_fcst[t]["RDCND"] == LACK_VALUE_8
        cnt = 0
        cntb = 0
        bstat = false
        (t-1).downto(startft){|m|
          if refw_fcst[m]["RDCND"] == 3
            cnt = cnt + 1
          end
          if (refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] < 1 || refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] == LACK_VALUE_16) && refw_fcst[m]["RDCND"] == 3
            cntb = cntb + 1
          end
          if t - m == 6 && cnt == 6
            bstat = true  #（４'）路温＜0.5度で、前路面状態が「圧」で、過去路面状態「圧」かつ時間降雪＜1cmの状態が過去5コマ未満で、
                          #       路面状態「圧」が過去から連続6コマ以上の場合→  「圧」
          end
        }
        if bstat && cntb < 5
          refw_fcst[t]["RDCND"] = 3
        end
      end
    end
    if t > startft
      if refw_fcst[t-1]["RDCND"] == 0 && isdry(refw_fcst[t]["WX"])
        refw_fcst[t]["RDCND"] = 0  #（４）路温＜0.5度で、前路面状態が「乾」で、天気マークが非降水系の場合→  「乾」
      end
    end
    if t >= 5 + startft
      if refw_fcst[t-1]["RDCND"] == 1 && refw_fcst[t]["RDCND"] == LACK_VALUE_8
        bstat = true
        cnt = 0
        0.upto(5){|m|
          if !isdry(refw_fcst[t-m]["WX"])
            bstat = false
            break
          end
        }
        if bstat
          refw_fcst[t]["RDCND"] = 0  #（５）路温＜0.5度で、前路面状態が「湿」で、天気マークが非降水系が現在も含めて6コマ連続となっている場合→  「乾」
        end
      end
    end
    if refw_fcst[t]["RDCND"] == LACK_VALUE_8
      if t > startft
        refw_fcst[t]["RDCND"] = 4  #（６）路温＜0.5度で、（１）～（５）を全て満たさない場合→  「凍」
      end
    end
  elsif refw_fcst[t]["RDTMP"] >= 0.45 && refw_fcst[t]["RDTMP"] != LACK_VALUE_16
    if refw_fcst[t]["RDTMP"] < 4.45 && refw_fcst[t]["RDTMP"] != LACK_VALUE_16
      if refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] >= 1 && refw_fcst[t]["SNWFLL_1HOUR_TOTAL"] != LACK_VALUE_16
        refw_fcst[t]["RDCND"] = 2  #（７）路温≧0.5度で、時間降雪≧1cm以上で、路温＜4.5度の場合→「シャ」(気温変更、2007.02.01 Y.Touda)
      elsif t > startft
        if refw_fcst[t-1]["RDCND"] == 3
          refw_fcst[t]["RDCND"] = 2  #（８）路温≧0.5度で、前路面状態が「圧」で、路温＜4.5度の場合→「シャ」(気温変更、2007.02.01 Y.Touda)
        elsif refw_fcst[t-1]["RDCND"] == 2
          bstat = false
          1.upto(6){|m|
            if refw_fcst[t-m]["RDCND"] != 2
              bstat = true
              break
            end
            if t == m
              break
            end
          }
          if bstat
            refw_fcst[t]["RDCND"] = 2  #（９）路温≧0.5度で、前路面状態が「シャ」で、路面状態「シャ」が過去から連続6コマ未満で、路温＜4.5度の場合→  「シャ」
          end
        end
      end
    end
    if t >= 6 + startft
      if refw_fcst[t-1]["RDCND"] == 2
        cnt = 0
        cntb = 0
        bstat = false
        (t-1).downto(startft){|m|
          if refw_fcst[m]["RDCND"] == 2
            cnt = cnt + 1
          end
          if (refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] < 1 || refw_fcst[m]["SNWFLL_1HOUR_TOTAL"] == LACK_VALUE_16) && refw_fcst[m]["RDCND"] == 2
            cntb = cntb + 1
          end
          if t-m == 6 && cnt == 6
            bstat = true
          end
        }
        if bstat && cntb < 5
          refw_fcst[t]["RDCND"] = 2 # (10')路温≧0.5度で、前路面状態が「シャ」で、路面状態「シャ」が過去から連続6コマ以上で、過去路面状態「シャ」かつ時間降雪＜1cmの状態が過去5コマ未満の場合→  「シャ」
        end
      end
    end
    if t > startft
      if refw_fcst[t-1]["RDCND"] == 0 && isdry(refw_fcst[t]["WX"]) && refw_fcst[t]["RDCND"] == LACK_VALUE_8
        refw_fcst[t]["RDCND"] = 0  #（１０）路温≧0.5度で、前路面状態が「乾」で、天気マークが非降水系の場合→  「乾」
      end
    end
    if t > 5 + startft
      if refw_fcst[t-1]["RDCND"] == 1 && isdry(refw_fcst[t]["WX"]) && refw_fcst[t]["RDCND"] == LACK_VALUE_8
        bstat = true
        (t-5).upto(t){|m|
          if !isdry(refw_fcst[m]["WX"])
            bstat = false
            break
          end
        }
        if bstat
          refw_fcst[t]["RDCND"] = 0  #（１１）路温≧0.5度で、前路面状態が「湿」で、天気マークが非降水系の状態が現在も含めて6コマ連続となっている場合→  「乾」
        end
      end
    end
    if refw_fcst[t]["RDCND"] == LACK_VALUE_8
      if t > startft
        refw_fcst[t]["RDCND"] = 1  #（１２）路温≧0.5度で、（７）～（１１）を全て満たさない場合→  「湿」
      end
    end
  else
    refw_fcst[t]["RDCND"] = LACK_VALUE_8 #-
  end
end

# 天気マークが非降水系→乾燥
def isdry(wx)
  # 非降水(100/200)
  return true if wx == 100
  return true if wx == 200
  return false
end

# (FT=0) 初期状態
def get_rdcnd_first( rtemp, wx, snow )
  if isdry(wx)
    return 0 # 乾燥
  end
  if rtemp == LACK_VALUE_16
    return LACK_VALUE_8
  end
  if snow < 0.5 || snow == LACK_VALUE_16
    if rtemp < 0.45
      return 4 # 凍結
    end
    return 1 # 湿潤
  elsif snow < 2.5
    if rtemp < 0.45
      return 4 # 凍結
    elsif rtemp < 4.45
      return 2 # シャ
    end
    return 1 # 湿潤
  else
    if rtemp < 0.45 
      return 3 # 圧雪
    elsif rtemp < 4.45
      return 2 # シャ
    end
    return 1 # 湿潤
  end
  return LACK_VALUE_8
end

def wx_conv(wx)
 cv = $config["wx_conv"][wx]
 return wx if cv == nil
 return cv
end
