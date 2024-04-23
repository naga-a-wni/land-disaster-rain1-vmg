def send_mail(title)
  if $config["email_send"] == 1
    sendto = $config["email_addrs"].join(",")
    cmd = "echo -e \"%s\" | /bin/mail -s \"#{title}\" #{sendto}" % [Time.now.to_s]
    system(cmd)
  end
end
