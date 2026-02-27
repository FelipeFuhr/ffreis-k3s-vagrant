# frozen_string_literal: true

require 'json'

cp_count = Integer(ENV.fetch('KUBE_CP_COUNT', '3'))
worker_count = Integer(ENV.fetch('KUBE_WORKER_COUNT', '5'))
etcd_count = Integer(ENV.fetch('KUBE_ETCD_COUNT', '3'))
provider = ENV.fetch('KUBE_PROVIDER', 'libvirt')
box = ENV.fetch('KUBE_BOX', 'bento/ubuntu-24.04')
network_prefix = ENV.fetch('KUBE_NETWORK_PREFIX', '10.30.0')
api_lb_requested = ENV.fetch('KUBE_API_LB_ENABLED', 'true') == 'true'
api_lb_enabled = api_lb_requested && cp_count > 1
api_lb_ip = ENV.fetch('KUBE_API_LB_IP', "#{network_prefix}.5")
api_lb_hostname = ENV.fetch('KUBE_API_LB_HOSTNAME', 'k3s-api.local')
cp_cpus = Integer(ENV.fetch('KUBE_CP_CPUS', '1'))
cp_memory = Integer(ENV.fetch('KUBE_CP_MEMORY', '1536'))
worker_cpus = Integer(ENV.fetch('KUBE_WORKER_CPUS', '1'))
worker_memory = Integer(ENV.fetch('KUBE_WORKER_MEMORY', '1536'))
api_lb_cpus = Integer(ENV.fetch('KUBE_API_LB_CPUS', '1'))
api_lb_memory = Integer(ENV.fetch('KUBE_API_LB_MEMORY', '512'))
etcd_cpus = Integer(ENV.fetch('KUBE_ETCD_CPUS', '1'))
etcd_memory = Integer(ENV.fetch('KUBE_ETCD_MEMORY', '1024'))
k3s_version = ENV.fetch('K3S_VERSION', 'v1.30.6+k3s1')
k3s_cluster_token = ENV.fetch('K3S_CLUSTER_TOKEN', 'k3s-vagrant-shared-token')

raise 'KUBE_CP_COUNT must be >= 1' if cp_count < 1
raise 'KUBE_ETCD_COUNT must be >= 3' if etcd_count < 3

nodes = []
if api_lb_enabled
  nodes << {
    name: 'api-lb',
    role: 'api-lb',
    ip: api_lb_ip,
    cpus: api_lb_cpus,
    memory: api_lb_memory
  }
end

etcd_nodes = []
(1..etcd_count).each do |index|
  etcd_nodes << {
    name: "etcd#{index}",
    role: 'etcd',
    ip: "#{network_prefix}.#{20 + index}",
    cpus: etcd_cpus,
    memory: etcd_memory
  }
end
nodes.concat(etcd_nodes)

(1..cp_count).each do |index|
  nodes << {
    name: "cp#{index}",
    role: 'server',
    ip: "#{network_prefix}.#{10 + index}",
    cpus: cp_cpus,
    memory: cp_memory
  }
end

(1..worker_count).each do |index|
  nodes << {
    name: "worker#{index}",
    role: 'agent',
    ip: "#{network_prefix}.#{100 + index}",
    cpus: worker_cpus,
    memory: worker_memory
  }
end

external_etcd_endpoints = etcd_nodes.map { |node| "http://#{node[:ip]}:2379" }.join(',')
external_etcd_initial_cluster = etcd_nodes.map { |node| "#{node[:name]}=http://#{node[:ip]}:2380" }.join(',')
server_endpoint = if api_lb_enabled
                    "https://#{api_lb_ip}:6443"
                  else
                    "https://#{network_prefix}.11:6443"
                  end

File.write('.vagrant-nodes.json', JSON.pretty_generate(nodes))

Vagrant.configure('2') do |config|
  config.vm.box = box
  config.vm.synced_folder '.', '/vagrant', type: 'rsync'

  nodes.each do |node|
    config.vm.define node[:name] do |machine|
      machine.vm.hostname = node[:name]
      machine.vm.network 'private_network', ip: node[:ip]

      machine.vm.provider provider do |provider_cfg|
        provider_cfg.cpus = node[:cpus]
        provider_cfg.memory = node[:memory]
      end

      machine.vm.provision 'shell', path: 'scripts/00_common.sh', env: {
        'NODE_ROLE' => node[:role]
      }

      if node[:role] == 'api-lb'
        machine.vm.provision 'shell', path: 'scripts/05_api_lb.sh', env: {
          'NODE_NAME' => node[:name],
          'CP_COUNT' => cp_count.to_s,
          'NETWORK_PREFIX' => network_prefix,
          'API_LB_HOSTNAME' => api_lb_hostname,
          'API_LB_IP' => api_lb_ip
        }
      elsif node[:role] == 'etcd'
        machine.vm.provision 'shell', path: 'scripts/15_init_external_etcd.sh', env: {
          'ETCD_NAME' => node[:name],
          'ETCD_IP' => node[:ip],
          'ETCD_INITIAL_CLUSTER' => external_etcd_initial_cluster
        }
      elsif node[:name] == 'cp1'
        machine.vm.provision 'shell', path: 'scripts/10_init_server.sh', env: {
          'K3S_VERSION' => k3s_version,
          'SERVER_IP' => node[:ip],
          'SERVER_ENDPOINT' => server_endpoint,
          'EXTERNAL_ETCD_ENDPOINTS' => external_etcd_endpoints,
          'K3S_CLUSTER_TOKEN' => k3s_cluster_token
        }
      elsif node[:role] == 'server'
        machine.vm.provision 'shell', path: 'scripts/20_join_server.sh', env: {
          'K3S_VERSION' => k3s_version,
          'SERVER_IP' => node[:ip],
          'SERVER_ENDPOINT' => server_endpoint,
          'EXTERNAL_ETCD_ENDPOINTS' => external_etcd_endpoints,
          'K3S_CLUSTER_TOKEN' => k3s_cluster_token
        }
      elsif node[:role] == 'agent'
        machine.vm.provision 'shell', path: 'scripts/30_join_agent.sh', env: {
          'K3S_VERSION' => k3s_version,
          'SERVER_IP' => "#{network_prefix}.11",
          'SERVER_ENDPOINT' => server_endpoint,
          'K3S_CLUSTER_TOKEN' => k3s_cluster_token
        }
      end
    end
  end
end
