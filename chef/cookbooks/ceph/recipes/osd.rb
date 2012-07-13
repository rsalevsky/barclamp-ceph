# initialize ceph nodes

# we need a master, and our mon-cluster needs to work...
master_mons = search("node", "roles:ceph-mon-master AND ceph_clustername:#{node['ceph']['clustername']} AND chef_environment:#{node.chef_environment}", "X_CHEF_id_CHEF_X asc") || []

if master_mons.size == 0
  Chef::Log.error("No master server found in ceph cluster #{node[:ceph][:clustername]} - not initializing/configuring OSDs")
  return 
end

include_recipe "ceph::default"
package "util-linux"

node[:ceph][:osd][:enabled] = true
c = ceph_keyring "client.admin" do
  secret get_master_secret
  action [:create, :add] 
end

# search for possible OSDs, labeled 
devices = node[:ceph][:devices]
Chef::Log.info "Devices: #{devices.join(',')}"

devices.each do |device|
  execute "make xfs filesystem on #{device}" do
    command "mkfs.xfs -f #{device}"
    ## test if the FS is already an XFS file system.
    not_if "xfs_admin -l #{device}"
  end

  # /var/lib/ceph/$type/$cluster-$id
  # chicken-egg here - I don't know the index to mount this on - we'll go with the UUID for now (sorry TV)...  
  
  # /var/lib/ceph/$type/$cluster-$uuid ($id is unknown)

  # why not use the serial # of the drive? )

  osd_path = get_osd_path(device)

  directory osd_path do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
  end
  
  mount osd_path do 
    device device
    fstype "xfs"
    options "noatime"
    action [:enable, :mount]
  end
    
  ceph_osd "Initializing new osd on #{device} - #{id}" do
    path osd_path
    action [:initialize]
    not_if "test -e #{osd_path}/whoami"
  end

  ceph_osd "Starting the osd from #{id}" do
    path osd_path
    action [:start]
  end
end if devices
