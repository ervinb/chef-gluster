include_recipe "gluster::upgrade_common"

bash "kill glusterfsd and glusterd" do
  code <<-CMD
  killall glusterfsd glusterd
  CMD
end

# Upgrade the server package
package node['gluster']['server']['package'] do
  action :upgrade
end

include_recipe "gluster::server_install"

include_recipe "gluster::server_setup"
