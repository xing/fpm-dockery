require 'fpm/fry/plugin'
# A plugin that detects the init system of a docker image.
#
# This plugin is a low-level plugin and is used by other plugins such as "service".
#
# @example in a recipe when using the image "ubuntu:22.04"
#   plugin 'init'
#   init.systemd? #=> true
#   init.sysv? #=> false
module FPM::Fry::Plugin::Init

  # Contains information about the init system in use.
  class System
    # @return [Hash<Symbol,Object>] features of the init system
    attr :with

    def with?(feature)
      !!with[feature]
    end
    def sysv?
      name == :sysv
    end
    def upstart?
      name == :upstart
    end
    def systemd?
      name == :systemd
    end
  private
    attr :name
    def initialize(name, with)
      @name, @with = name, with
    end
  end

  # @return [System] initsystem in use
  def init
    return @init
  end

private
  def self.detect(inspector)
    if inspector.exists?('/lib/systemd/systemd')
      return System.new(:systemd, {})
    end
    if inspector.exists?('/etc/init')
      return detect_upstart(inspector)
    end
    if inspector.exists?('/etc/init.d')
      return detect_sysv(inspector)
    end
    return nil
  end

  def self.detect_upstart(inspector)
    features = {
      sysvcompat: inspector.exists?('/lib/init/upstart-job') ? '/lib/init/upstart-job' : false
    }
    return System.new(:upstart,features)
  end

  def self.detect_sysv(inspector)
    features = {
      :chkconfig => inspector.exists?('/sbin/chkconfig'),
      :'update-rc.d' => inspector.exists?('/usr/sbin/update-rc.d'),
      :'invoke-rc.d' => inspector.exists?('/usr/sbin/invoke-rc.d')
    }
    return System.new(:sysv,features)
  end

  def self.extended(base)
    base.instance_eval do
      @init ||= FPM::Fry::Plugin::Init.detect(inspector)
    end
  end

  def self.apply(builder)
    builder.extend(self)
    return builder.init
  end

end
