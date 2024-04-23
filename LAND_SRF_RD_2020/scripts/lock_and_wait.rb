# lock and wait
def lock_and_wait(lock_file)
  f = open(lock_file,'w')
  while true
    if f.flock(File::LOCK_EX | File::LOCK_NB)
      return f
    else
      $log.write("waiting.")
      sleep(10)
    end
  end
end

def unlock_and_wait(lock_f)
  lock_f.flock(File::LOCK_UN)
end
