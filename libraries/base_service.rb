require 'poise'
require 'chef/resource'
require 'chef/provider'

class Chef
  class Resource
    class BaseService < Chef::Resource
      include Poise(container: true)

      actions(:install)

      attribute(
        :user,
        kind_of: String,
        default: lazy { node['proxysql']['user'] }
      )
      attribute(
        :group,
        kind_of: String,
        default: lazy { node['proxysql']['group'] }
      )
      attribute(
        :data_dir,
        kind_of: String,
        default: lazy { node['proxysql']['data_dir'] }
      )
      attribute(
        :config_dir,
        kind_of: String,
        default: lazy { node['proxysql']['config_dir'] }
      )
    end
  end

  class Provider
    class BaseService < Chef::Provider
      include Poise

      def action_install
        converge_by("Proxysql installing #{new_resource.name}") do
          notifying_block do
            validate!
            create_user
            dirs = [
              new_resource.config_dir,
              new_resource.data_dir
            ]
            create_directories(dirs)
            install_proxysql_repository
            deriver_install
          end
        end
      end

      protected

      def deriver_install
        raise 'Not implemented'
      end

      def validate!
        platform_supported?
      end

      def platform_supported?
        platform = node['platform']
        return if %w[redhat centos debian ubuntu].include?(platform)
        raise "Platform #{platform} is not supported"
      end

      def create_directories(dirs)
        Array(dirs).each do |dir|
          directory dir do
            owner new_resource.user
            group new_resource.group
            mode '0750'
          end
        end
      end

      private

      def create_user
        group new_resource.group do
          action :create
        end

        user new_resource.user do
          group new_resource.group
          shell '/bin/false'
          action :create
        end
      end

      def install_proxysql_repository
        url = node['percona']['repository']['url']
        name = node['percona']['repository']['name']

        case node['platform']
        when 'rhel', 'centos'
          execute "rpm -Uhv #{url}" do
            creates "/etc/yum.repos.d/#{name}"
          end
        when 'debian', 'ubuntu'
          basename = ::File.basename(url)
          percona_repo_deb = Chef::Config[:file_cache_path] + "/#{basename}"

          apt_update 'for_percona_repo' do
            action :nothing
          end

          dpkg_package basename do
            source percona_repo_deb
            action :nothing
            notifies :update, 'apt_update[for_percona_repo]'
          end

          remote_file percona_repo_deb do
            source url
            notifies :install, "dpkg_package[#{basename}]"
          end
        end
      end
    end
  end
end
