#
# Cookbook Name:: gluster
# Recipe:: server_setup
#
# Copyright 2015, Andrew Repton
# Copyright 2015, Grant Ridder
# Copyright 2015, Biola University
# Copyright 2017, Ervin Barta
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

# Prepare Physical volumes
node['gluster']['server']['disks'].each do |physical_device|
  lvm_physical_volume physical_device
end

# Create and start volumes
node['gluster']['server']['volumes'].each do |volume_name, volume_values|
  bricks         = []
  volume_path    = "#{node['gluster']['server']['brick_mount_path']}/#{volume_name}"
  brick_dir_path = "#{volume_path}/#{node['gluster']['server']['brick_dir']}"
  master_node    = volume_values['peers'].first
  ssh_user       = node.default['gluster']['server']['ssh_user']

  # All nodes where this cookbook is ran, are considered to be peers and server_setup
  # at the same time

  # Use either configured LVM volumes or default LVM volumes
  # Configure the LV's per gluster volume
  # Each LV is one brick
  if node['gluster']['server']['disks'].any?
    lvm_volume_group 'gluster' do
      physical_volumes node['gluster']['server']['disks']

      if volume_values.attribute?('filesystem')
        filesystem = volume_values['filesystem']
      else
        Chef::Log.warn('No filesystem specified, defaulting to xfs')
        filesystem = 'xfs'
      end

      # Even though this says volume_name, it's actually Brick Name. At the moment this method only supports one brick per volume per server
      logical_volume volume_name do
        size volume_values['size']
        filesystem filesystem
        mount_point volume_path
      end
    end
  else
    Chef::Log.warn('No disks defined for LVM, create gluster on existing filesystem')
    directory volume_path do
      owner 'root'
      group 'root'
      mode '0755'
      recursive true
      action :create
    end
  end

  bricks << brick_dir_path

  # Save the array of bricks to the node's attributes
  node.normal['gluster']['server']['volumes'][volume_name]['bricks'] = bricks

  # If the current node isn't master, add it to the master pool by self probing
  ## Requirements:
  ## - the current node has SSH access to the master node
  ## - the SSH user can run 'sudo' commands (!requiretty is set in /etc/sudoers)
  ## - node FQDN is correctly set (preferably running avahi-daemon), and it's accessible

  unless master_node =~ /#{node['fqdn']}/ || master_node =~ /#{node['hostname']}/
    # Note that the hostname will be resolved on the current node and not on
    # the master node -- '$' isn't esacaped
    bash "probe current node from master" do
      user ssh_user
      code <<-CMD
        ssh -o StrictHostKeychecking=no #{master_node} "sudo gluster peer probe $(hostname --fqdn)"
      CMD
      only_if "cat /etc/passwd | grep '#{ssh_user}'"
    end

    directory brick_dir_path

    # include the current node in the cluster
    bash "add current node as a brick" do
      code <<-CMD
        gluster volume add-brick #{volume_name} $(hostname --fqdn):#{brick_dir_path}
        gluster volume rebalance #{volume_name} start
      CMD
      not_if "gluster volume info | grep $(hostname --fqdn):#{brick_dir_path}"
    end
  end

  # Only continue if the node is the first peer in the array
  if master_node =~ /#{node['fqdn']}/ || master_node =~ /#{node['hostname']}/

    # Create the volume if it doesn't exist
    unless File.exist?("/var/lib/glusterd/vols/#{volume_name}/info")
      # Create a hash of peers and their bricks
      volume_bricks = {}
      brick_count = 0
      volume_values['peers'].each do |peer|
        # As every server will be running the same code, we know what the brick paths will be on every node
        if node['gluster']['server']['volumes'][volume_name].attribute?('bricks')
          peer_bricks = node['gluster']['server']['volumes'][volume_name]['bricks']
          volume_bricks[peer] = peer_bricks
          brick_count += (peer_bricks.count || 0)
        else
          Chef::Log.warn("No bricks found for volume #{volume_name}")
        end
      end

      # Create option string
      force = false
      options = ''

      case volume_values['volume_type']
      when 'distributed'
        Chef::Log.warn('You have specified distributed, serious data loss can occur in this mode as files are spread randomly among the bricks')
        options = ' '
      when 'replicated'
        # Replicated can be anything from two nodes to X nodes. Replica_count should equal number of bricks.
        if brick_count < 2
          Chef::Log.warn("Correct number of bricks not available: #{brick_count} needs to be at least 1. Skipping...")
          next
        end
        Chef::Log.warn('You have specified replicated, so the attribute replica_count will be set to be the same number as the bricks you have')
        node.set['gluster']['server']['volumes'][volume_name]['replica_count'] = brick_count
        options = "replica #{brick_count}"
      when 'distributed-replicated'
        # brick count has to be a multiple of replica count
        if (brick_count % volume_values['replica_count']).nonzero?
          Chef::Log.warn("Correct number of bricks not available: #{brick_count} needs to be a multiple of #{volume_values['replica_count']}. Skipping...")
          next
        else
          options = "replica #{volume_values['replica_count']}"
        end
      when 'striped'
        # This is similar to a replicated volume, stripe count is the same as the number of bricks
        Chef::Log.warn('You have specified striped, so the attribute replica_count will be set to be the same number as the bricks you have')
        node.set['gluster']['server']['volumes'][volume_name]['replica_count'] = brick_count
        options = "stripe #{brick_count}"
      when 'distributed-striped'
        if (brick_count % volume_values['replica_count']).nonzero?
          Chef::Log.warn("Correct number of bricks not available: #{brick_count} available, at least #{required_bricks} are required for volume #{volume_name}. Skipping...")
          next
        else
          options = "stripe #{volume_values['replica_count']}"
        end
      end
      unless options.empty?
        volume_bricks.each do |peer, vbricks|
          vbricks.each do |brick|
            options << " #{peer}:#{brick}"
            if vbricks.count > 1
              Chef::Log.warn('We have multiple bricks on the same peer, adding force flag to volume create')
              force = true
            end
          end
        end
      end

      volume_create_cmd = "gluster volume create #{volume_name} #{options}"

      execute 'gluster volume create' do
        command lazy {
          if force
            "echo y | #{volume_create_cmd} force"
          elsif system("df #{node['gluster']['server']['brick_mount_path']}/#{volume_name}/ --output=target |grep -q '^/$'") && node['gluster']['server']['disks'].empty?
            Chef::Log.warn("Directory #{node['gluster']['server']['brick_mount_path']}/ on root filesystem, force creating volume #{volume_name}")
            "echo y | #{volume_create_cmd} force"
          else
            volume_create_cmd
          end
        }
        action :run
        not_if options.empty?
      end
    end

    # Start the volume
    execute "gluster volume start #{volume_name}" do
      action :run
      not_if { `gluster volume info #{volume_name} | grep Status`.include? 'Started' }
    end

    # Restrict access to the volume if configured
    gluster_volume_option "#{volume_name}/auth.allow" do
      if volume_values['allowed_hosts']
        value volume_values['allowed_hosts'].join(',')
        action :set
      else
        action :reset
      end
    end

    # Configure volume quote if configured
    if volume_values['quota']
      # Enable quota
      execute "gluster volume quota #{volume_name} enable" do
        action :run
        not_if "egrep '^features.quota=on$' /var/lib/glusterd/vols/#{volume_name}/info"
      end

      # Configure quota for the root of the volume
      execute "gluster volume quota #{volume_name} limit-usage / #{volume_values['quota']}" do
        action :run
        not_if "egrep '^features.limit-usage=/:#{volume_values['quota']}$' /var/lib/glusterd/vols/#{volume_name}/info"
      end
    end
    if volume_values['options']
      volume_values['options'].each do |option_key, option_value|
        gluster_volume_option "#{volume_name}/#{option_key}" do
          value option_value
        end
      end
    end
  end

  # All nodes act as clients as well, so mount the brick on self
  gluster_mount volume_name do
    server lazy { %x(hostname --fqdn).strip }
    mount_point "/mnt/gluster/#{volume_name}"
    action [:mount, :enable]
  end
end
