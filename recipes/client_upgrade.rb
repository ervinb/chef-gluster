include_recipe "gluster::upgrade_common"

package node['gluster']['client']['package'] do
  action :upgrade
end

include_recipe 'gluster::client_mount'
