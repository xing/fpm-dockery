require 'fiber'
require 'shellwords'
require 'rubygems/package'
require 'fpm/dockery/os_db'
require 'fpm/dockery/source'
require 'fpm/dockery/joined_io'
module FPM; module Dockery
  class DockerFile < Struct.new(:variables,:cache,:recipe)

    def initialize(variables, cache = Source::Null::Cache, recipe)
      variables = variables.dup
      if variables[:distribution] && !variables[:flavour] && OsDb[variables[:distribution]]
        variables[:flavour] = OsDb[variables[:distribution]][:flavour]
      end
      variables.freeze
      super(variables, cache, recipe)
    end

    def dockerfile
      df = []
      df << "FROM #{variables[:image]}"

      df << "RUN mkdir /tmp/build"
      df << "WORKDIR /tmp/build"

      deps = (recipe.build_depends.merge recipe.depends).select{|_,v| v.fetch(:install,true) }.map{|k,_| k }.sort
      if deps.any?
        case(variables[:flavour])
        when 'debian'
          df << "RUN apt-get install --yes #{Shellwords.join(deps)}"
        when 'redhat'
          df << "RUN yum -y install #{Shellwords.join(deps)}"
        else
          raise "Unknown flavour: #{variables[:flavour]}"
        end
      end

      cache.file_map.each do |from, to|
        df << "ADD #{from} #{map_dir(to)}"
      end

      df << "ADD .build.sh /tmp/build/"

      df << "ENTRYPOINT /tmp/build/.build.sh"
      df << ''
      return df.join("\n")
    end

    def build_sh
      df = ['#!/bin/bash']
      df << 'set -e'
      df << 'set -x'
      recipe.steps.each do |k,v|
        df << "echo '------> ' #{Shellwords.escape k}"
        df << v.to_s
      end
      df << ''
      return df.join("\n")
    end

    def tar_io
      JoinedIO.new(
        self_tar,
        cache.tar_io
      )
    end

    def map_dir(dir)
      if ['','.'].include? dir
        return '/tmp/build'
      else
        return File.join('/tmp/build',dir)
      end
    end

    def self_tar
      sio = StringIO.new
      tar = Gem::Package::TarWriter.new(sio)
      tar.add_file('.build.sh','0777') do |io|
        io.write(build_sh)
      end
      tar.add_file('Dockerfile','0777') do |io|
        io.write(dockerfile)
      end
      #tar.close
      sio.rewind
      return sio
    end

  end
end ; end
