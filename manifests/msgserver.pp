# Copyright 2013 Mojo Lingo LLC.
# Modifications by Red Hat, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
class openshift_origin::msgserver (
  $using_systemd = false
) {
  anchor { 'openshift_origin::msgserver_begin': } ->
  class { 'openshift_origin::firewall::activemq': } ->
  anchor { 'openshift_origin::msgserver_end': }

  $cluster_members        = $::openshift_origin::real_msgserver_cluster_members
  $cluster_remote_members = delete($cluster_members, $::openshift_origin::msgserver_fqdn)

  package { ['activemq','activemq-client']:
      ensure  => present,
      require => Class['openshift_origin::install_method'],
  }

  # TODO: This module _should_ be setting up ActiveMQ for OpenShift and then passing along
  # the actual work to the Puppet ActiveMQ module. Also allows for dispatch to other msgserver
  # choices down the road.

  if $using_systemd {
    file { '/etc/tmpfiles.d/activemq.conf':
      path    => '/etc/tmpfiles.d/activemq.conf',
      content => template('openshift_origin/activemq/tmp-activemq.conf.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0444',
      require => Package['activemq'],
      notify  => Service['activemq'],
    }
  }

  file { '/var/run/activemq/':
    ensure  => 'directory',
    owner   => 'activemq',
    group   => 'activemq',
    mode    => '0750',
    require => Package['activemq'],
  }

  if ($::openshift_origin::msgserver_tls_enabled == 'enabled') or ($::openshift_origin::msgserver_tls_enabled == 'strict') {
    if ($::openshift_origin::msgserver_tls_ca != '') and ($::openshift_origin::msgserver_tls_key != '') and ($::openshift_origin::msgserver_tls_cert != '') {
      anchor { 'openshift_origin::msgserver_keystores_begin': } ->
      class { 'openshift_origin::activemq_keystores' : } ->
      anchor { 'openshift_origin::msgserver_keystores_end': }

      $activemq_openwire_port = '61617'
    } else { fail 'Valid certificate file locations are required when msgserver_tls_enabled is in strict or enabled mode.' }
  } else {
    $activemq_openwire_port = '61616'
  }

  if $::openshift_origin::msgserver_cluster {
    $activemq_config_template_real = 'openshift_origin/activemq/activemq-network.xml.erb'
  } else {
    $activemq_config_template_real = 'openshift_origin/activemq/activemq.xml.erb'
  }

  file { 'activemq.xml config':
    path    => '/etc/activemq/activemq.xml',
    content => template($activemq_config_template_real),
    owner   => 'root',
    group   => 'activemq',
    mode    => '0440',
    require => Package['activemq'],
    notify  => Service['activemq'],
  }

  file { 'jetty.xml config':
    path    => '/etc/activemq/jetty.xml',
    content => template('openshift_origin/activemq/jetty.xml.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0444',
    require => Package['activemq'],
    notify  => Service['activemq'],
  }

  file { 'jetty-realm.properties config':
    path    => '/etc/activemq/jetty-realm.properties',
    content => template('openshift_origin/activemq/jetty-realm.properties.erb'),
    owner   => 'root',
    group   => 'activemq',
    mode    => '0440',
    require => Package['activemq'],
    notify  => Service['activemq'],
  }

  service { 'activemq':
    ensure     => running,
    require    => File['activemq.xml config','jetty.xml config','jetty-realm.properties config'],
    hasstatus  => true,
    hasrestart => true,
    enable     => true,
  }
}
