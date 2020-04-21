require 'spec_helper_acceptance'

describe 'Scenario: install foreman with journald' do
  apache_service_name = ['debian', 'ubuntu'].include?(os[:family]) ? 'apache2' : 'httpd'

  before(:context) do
    case fact('osfamily')
    when 'RedHat'
      on default, 'yum -y remove foreman* tfm-*'
    when 'Debian'
      on default, 'apt-get purge -y foreman*', { :acceptable_exit_codes => [0, 100] }
      on default, 'apt-get purge -y ruby-hammer-cli-*', { :acceptable_exit_codes => [0, 100] }
    end

    on default, "systemctl stop #{apache_service_name}", { :acceptable_exit_codes => [0, 5] }
  end

  let(:pp) do
    <<-EOS
    if $facts['os']['family'] == 'RedHat' and $facts['os']['name'] != 'Fedora' {
      class { 'redis::globals':
        scl => 'rh-redis5',
      }
    }

    $directory = '/etc/foreman'
    $certificate = "${directory}/certificate.pem"
    $key = "${directory}/key.pem"
    exec { 'Create certificate directory':
      command => "mkdir -p ${directory}",
      path    => ['/bin', '/usr/bin'],
      creates => $directory,
    } ->
    exec { 'Generate certificate':
      command => "openssl req -nodes -x509 -newkey rsa:2048 -subj '/CN=${facts['fqdn']}' -keyout '${key}' -out '${certificate}' -days 365",
      path    => ['/bin', '/usr/bin'],
      creates => $certificate,
      umask   => '0022',
    } ->
    file { [$key, $certificate]:
      owner => 'root',
      group => 'root',
      mode  => '0640',
    } ->
    class { '::foreman':
      user_groups            => [],
      initial_admin_username => 'admin',
      initial_admin_password => 'changeme',
      server_ssl_ca          => $certificate,
      server_ssl_chain       => $certificate,
      server_ssl_cert        => $certificate,
      server_ssl_key         => $key,
      server_ssl_crl         => '',
      logging_type           => 'journald',
    }
    EOS
  end

  it_behaves_like 'a idempotent resource'

  it_behaves_like 'the foreman application'

  describe package('foreman-journald') do
    it { is_expected.to be_installed }
  end

  # Logging to the journal is broken on Travis and EL7 but works in Vagrant VMs
  # and regular docker containers
  describe command('journalctl -u foreman'), unless: ENV['TRAVIS'] == 'true' && os[:family] == 'redhat' && os[:release] =~ /^7\./ do
    its(:stdout) { is_expected.to match(%r{Redirected to https://#{host_inventory['fqdn']}/users/login}) }
  end

  describe command('journalctl -u dynflow-sidekiq@orchestrator'), unless: ENV['TRAVIS'] == 'true' && os[:family] == 'redhat' && os[:release] =~ /^7\./ do
    its(:stdout) { is_expected.to match(%r{Everything ready for world: }) }
  end
end
