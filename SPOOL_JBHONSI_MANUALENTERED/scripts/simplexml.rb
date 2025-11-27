class XML_SimpleParse
  def initialize(file)
    if file.is_a?(IO)
      @file = file
    elsif file.is_a?(String)
      if File::exists?(file)
        @file = open(file)
      else
        @file = StringIO.new(file)
      end
    else
      raise "Input is not a IO or a String object."
    end
  end

  def each_block(key)
    startmark = "<#{key}>"
    endmark = "</#{key}>"

    buf = {}
    flag = false

    @file.each{|line|
      if line =~ /<([^ ]+)(.*)>/
        mark = "<#{$1}>"
        attr = $2
        if mark == startmark
          flag = true

          if !attr.nil?
            tmp = attr.split(' ')
            a = {}
            tmp.each{|s|
              tt = s.split('=')
              if tt.size != 2
                next
              end
              a[tt[0]] = tt[1].tr('"','')
            }
            buf['ATTRIBUTES'] = a
          end

          next
        end
      end

      if flag == true && line.strip == endmark
        yield(buf)
        flag = false
        buf = {}
      end

      if flag == true
        if line.strip =~ /<([^>]+)>(.*)/
          k = $1

          # search end
          text = $2

          if text =~ /(.*)</#{k}>$/
            text = $1
          else
            text = ""
            @file.each{|l|
              if l =~ /(.*)<\/#{k}>$/
                text += $1.strip if !$1.nil?
                break
              else
                text += l.strip
              end
            }
          end

          if text =~ /^<[^>]+>/
            buf[k] = expand(text)
          else
            buf[k] = text
          end
        end
      end
    }
  end

  private
  def expand(buf)
    ret = {}
    while (!buf.nil?) && buf.size > 0
      buf =~ /<([^>]+)>(.*)/
      key = $1
      tmp = $2

      tmp =~ /(.*)<\/#{key}>(.*)/

      val = $1
      buf = $2

      if val =~ /^</
        val = expand(val)
      end
      ret[key] = val

    end

    ret
  end

end
