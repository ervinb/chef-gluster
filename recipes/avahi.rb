# Setup avahi for local network discovery

node.default['gluster']['server']['avahi_dependencies'].each do |dependency|
  package dependency
end

service 'avahi-daemon' do
  supports :restart => true, :start => true, :stop => true
  action [:enable, :start]
end

template '/etc/avahi/avahi-daemon.conf' do
  action :create
  source 'avahi-daemon.conf.erb'
  variables({
    'internal_nic' => node.default['gluster']['server']['internal_nic']
  })
  notifies :restart, 'service[avahi-daemon]', :immediately
end
