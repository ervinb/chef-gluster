vagrant_user = "vagrant"
vagrant_home = "/home/vagrant"

directory "#{vagrant_home}/.ssh" do
  owner vagrant_user
  mode "0700"
end

template "#{vagrant_home}/.ssh/id_rsa" do
  source "id_rsa"
  owner vagrant_user
  mode "0400"
end

template "#{vagrant_home}/.ssh/id_rsa.pub" do
  source "id_rsa.pub"
  owner vagrant_user
  mode "0600"
end

bash "allow shared SSH key to connect" do
  code <<-CMD
  cat #{vagrant_home}/.ssh/id_rsa.pub >> #{vagrant_home}/.ssh/authorized_keys
  CMD

  not_if "grep 'shared-gfs-access' #{vagrant_home}/.ssh/authorized_keys"
end
