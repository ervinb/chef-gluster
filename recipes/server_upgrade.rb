include_recipe "gluster::upgrade_common"

bash "kill glusterfsd and glusterd" do
  code <<-CMD
  killall glusterfsd glusterd
  CMD
end

include_recipe "gluster::server_install"

include_recipe "gluster::server_setup"
