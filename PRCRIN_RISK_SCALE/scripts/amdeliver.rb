require 'thread'
require 'socket'
require 'stringio'

class Amdeliver
  attr_accessor :rw_timeout, :port, :send_timeout

  BUF_SIZE = 4096
  REPLAY_SIZE = 30
  MAGIC = 'amdeliver1'
  DEFAULT_PORT = 31257
  RW_TIMEOUT = 60
  SEND_TIMEOUT = 600

  def initialize(port=DEFAULT_PORT)
    @port = port
    @send_timeout = SEND_TIMEOUT
    @rw_timeout = RW_TIMEOUT
  end

  def make_request_data(size, service)
    buf = MAGIC
    buf += sprintf("%010d",size)
    buf += sprintf("%010d",service)
    buf
  end

  def replay_check(buf)
    magic = buf[0,MAGIC.size]
    if magic != MAGIC
      return [nil,nil]
    end

    code = buf[MAGIC.size,10].to_i
    mlen = buf[MAGIC.size+10,10].to_i

    [code,mlen]
  end

  def make_career(fp, nel_id, prog="addcareer")
    total_size = 32+prog.size+5

    pos = fp.pos
    fp.seek(0,IO::SEEK_END)
    data_size = fp.pos
    size = data_size + total_size
    fp.seek(pos,IO::SEEK_SET)

    buf = Array.new(total_size, 0).pack("C*")
#    buf = "\0" * total_size
    sp = StringIO.new(buf)

    sp.write([nel_id].pack('N'))
    sp.write([size].pack('N'))
    sp.write([1].pack('N'))
    sp.write([size-12].pack('N'))
    sp.write([total_size-16].pack('N'))
    sp.write([total_size-24].pack('N'))

    addr = IPSocket.getaddress(Socket.gethostname)
    tmp = addr.split('.')
    b = [tmp[0].to_i,tmp[1].to_i,tmp[2].to_i,tmp[3].to_i].pack("C*")
#    b = "\0"*4
#    b[0] = tmp[0].to_i
#    b[1] = tmp[1].to_i
#    b[2] = tmp[2].to_i
#    b[3] = tmp[3].to_i

    sp.write(b)

    sp.write([0x1].pack('N'))
    sp.write(prog)

    sp.rewind
    ret = sp.read
    sp.close
    return ret
  end

  def file_deliver(addr, fn, port=@port, tmo=@send_timeout)
    fp = open(fn)
    fp.binmode

    res = amdeliver(addr,fp,port,tmo)
    fp.close
    return res
  end

  def file_deliver_with_career(addr, fn, nel_id, prog='addcareer',
                               port=@port, tmo=@send_timeout)
    fp = open(fn)
    fp.binmode

    res = amdeliver(addr,fp,port,tmo,nel_id,prog)
    fp.close
    return res
  end

  def buf_deliver(addr, buf, port=@port, tmo=@send_timeout)
    sp = StringIO.new(buf)
    res = amdeliver(addr,sp,port,tmo)
    sp.close
    return res
  end

  def buf_deliver_with_career(addr, buf, nel_id, prog='addcareer',
                              port=@port, tmo=@send_timeout)
    sp = StringIO.new(buf)
    res = amdeliver(addr,sp,port,tmo,nel_id, prog)
    sp.close
    return res
  end

  def amdeliver(address, fp, port, send_timeout, nel_id=nil, prog='addcareer')
    fp.seek(0,IO::SEEK_END)
    size = fp.pos
    fp.seek(0,IO::SEEK_SET)

    send_limit = Time.new + send_timeout

    if nel_id.nil?
      data_id = fp.read(4).unpack('N')[0]

      buf = fp.read(4)
      if buf.size != 4
        raise "Data size read error."
      end

      checksize = buf.unpack('N')[0]
      if checksize != size
        raise "File size check failed."
      end
    else
      data_id = nel_id
      career = make_career(fp,nel_id,prog)
      size += career.size
    end

    sk = TCPSocket.open(address, port)
    sk.binmode

    sk.write make_request_data(size, -1)

    if !nel_id.nil?
      sk.write(career)
    end

    fp.seek(0,IO::SEEK_END)
    fpendpos = fp.pos

    fp.seek(0,IO::SEEK_SET)

    while true
      ret = IO::select [],[sk],[],@timeout

      if ret.nil?
        raise "Socket write timeout."
      end

      buf = fp.read(BUF_SIZE)

      sk.write buf

      if buf.size != BUF_SIZE
        break
      elsif fp.pos == fpendpos
        break
      end

      if Time.new > send_limit
        raise "Send timeout. Over #{send_timeout} seconds."
      end
    end

    ret = IO::select [sk],[],[],@timeout

    if ret.nil?
      raise "Replay packet receive timeout."
    end
    tmp = sk.read(REPLAY_SIZE)
    if tmp.nil?
      raise "Replay read error."
    end
    buf = tmp

    mes = ""
    code = 1
    if buf.size == REPLAY_SIZE
      code,len = replay_check(buf)

      if !len.nil? && len != 0
        mes = sk.read(len)
      end
    end
    sk.close
    return [code, mes, data_id]
  end
end
