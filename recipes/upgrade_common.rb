bash "remove old PPA lists if they exist" do
  code <<-CMD
    find /etc/apt/sources.list.d/ -name "*gluster*" | grep -P '.+glusterfs-(?!#{node['gluster']['version']}).+' | xargs -I list rm -f list
  CMD
end

include_recipe "gluster::repository"

node['gluster']['server']['volumes'].each do |volume_name, volume_values|
  gluster_mount volume_name do
    server lazy { %x(hostname --fqdn).strip }
    mount_point node['gluster']['client']['mount_point']
    action [:umount]
  end
end
