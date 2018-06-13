#
# Cookbook Name:: gluster
# Recipe:: client_mount
#
# Copyright 2015, Grant Ridder
# Copyright 2015, Biola University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This recipe can be used to mount Gluster volumes using client atttributes.
#   It has been deprecated in favor of the gluster_mount LWRP and will be
#   removed in a future update.

volumes = node['gluster']['client']['volumes']

Chef::Log.info("Mounting GlusterFS volumes:\n#{volumes}")

volumes.each do |volume_name, volume_values|
  Chef::Log.info("Processing volume: #{volume_name}")

  if volume_values['server'].nil? || volume_values['mount_point'].nil?
    Chef::Log.warn("No config for volume #{volume_name}. Skipping...")
    next
  else

  master_node = volume_values['server']
  volume_path = "#{master_node}:/#{volume_name}"
  mount_point = volume_values['mount_point']


    # Define a backup server for this volume, if available
    mount_options = 'defaults,_netdev,nobootwait'
    unless volume_values['backup_server'].nil?
      mount_options += ',backupvolfile-server=' + volume_values['backup_server']
    end

    # Handle the case where the endpoint is disconnected
    ## When GFS is unmounted, all file existance checks fail -- it's not a regular file
    ## and throws a "ERROR: cannot open `/mnt/gluster-cache' (Transport endpoint is not connected)`"
    bash "umount_gfs" do
      code "umount #{mount_point}"
      only_if "mount -l | grep '#{mount_point}' && ! [[ -e #{mount_point} ]]"
    end

    # Ensure the mount point exists
    directory mount_point do
      recursive true
      action :create
    end

    # Mount the partition and add to /etc/fstab
    mount mount_point do
      device volume_path
      fstype 'glusterfs'
      options mount_options
      pass 0
      action [:mount, :enable]
    end

    Chef::Log.info("GlusterFS auto-mounting enabled: #{node['gluster']['client']['automount']}")
    if node['gluster']['client']['automount']
      # overriden by firewall
      # postpone execution with :delayed
      bash "auto_mount" do
        code <<-CMD
          sed -i '/exit 0/i mkdir -p #{mount_point}; mount #{volume_path}' /etc/rc.local
        CMD

        action :nothing
        not_if "grep '#{volume_path}' /etc/rc.local"
      end

      execute "echo 'Delaying /etc/rc.local update'" do
        notifies :run, "bash[auto_mount]", :delayed
      end
    end
  end
end
