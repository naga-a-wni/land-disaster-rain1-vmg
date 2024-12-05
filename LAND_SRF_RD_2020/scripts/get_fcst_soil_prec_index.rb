#
# 土壌雨量指数
#

# L     : height of "Ryushutukou" (mm)
L1 = 15
L2 = 60
L3 = 15
L4 = 15
# alpha : flowout value "Ryuushutu keisuu" (1/hr)
ALPHA1 = 0.10 / 6
ALPHA2 = 0.15 / 6
ALPHA3 = 0.05 / 6
ALPHA4 = 0.01 / 6
# beta  : permeat value "Shintou keisuu" (1/hr)
BETA1  = 0.12 / 6
BETA2  = 0.05 / 6
BETA3  = 0.01 / 6
# threshhold value of 10 min (mm)
TH10MIN = 160
# threshhold value of 1 hour (mm)
TH1HR = 400

# prec : rainfall value (mm/10min)
def dojyouryo_10min(prec, check_r60, s1, s2, s3)
  flag = 0
  _s1_old = s1
  _s2_old = s2
  _s3_old = s3
  if check_r60 < 0 then
    flag = 1
  end
  if check_r60 > TH1HR then
    flag = 1
  end
  if prec < 0 then
    flag = 1
  end
  if prec > TH10MIN then
    flag = 1
  end
  # q1 ~ q3 is flowout value / 10min
  # if q < 0 then , set value 0.
  q11 = ALPHA1 * (s1 - L1)
  q12 = ALPHA2 * (s1 - L2)
  q2 = ALPHA3 * (s2 - L3)
  q3 = ALPHA4 * (s3 - L4)
  if q11 < 0 then q11 = 0 end
  if q12 < 0 then q12 = 0 end
  if q2 < 0 then q2 = 0 end
  if q3 < 0 then q3 = 0 end
  q1 = q11 + q12
  s3 = (1 - BETA3  ) * s3 - q3  + BETA2 * s2
  s2 = (1 - BETA2  ) * s2 - q2  + BETA1 * s1
  s1 = (1 - BETA1  ) * s1 - q1  + prec
  if flag == 1 then
    s1 =_s1_old
    s2 =_s2_old
    s3 =_s3_old
  end
  return [s1, s2, s3]
end

#
# r60  : rainfall value (mm/1h)
# ds   : [s1,s2,s3]
#
def get_fcst_soil_prec_index(r60, ds)
  if r60 < 0 || r60 > TH1HR
    return ds
  end
  prec = r60 / 6.0
  6.times{|i|
    ds = dojyouryo_10min(prec, r60, ds[0], ds[1], ds[2])
  }
  return ds
end
