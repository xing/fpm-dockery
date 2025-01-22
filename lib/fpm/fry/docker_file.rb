require 'fiber'
require 'shellwords'
require 'rubygems/package'
require 'fpm/fry/source'
require 'fpm/fry/joined_io'
module FPM; module Fry
  class DockerFile < Struct.new(:variables,:cache,:recipe)

    NAME = 'Dockerfile.fpm-fry'

    class Source < Struct.new(:variables, :cache)

      def initialize(variables, cache = Source::Null::Cache)
        variables = variables.dup.freeze
        super(variables, cache)
        if cache.respond_to? :logger
          @logger = cache.logger
        else
          @logger = Cabin::Channel.get
        end
      end

      def dockerfile
        df = []
        df << "FROM #{variables[:image]}"

        df << "RUN mkdir /tmp/build"

        file_map.each do |from, to|
          df << "COPY #{map_from(from)} #{map_to(to)}"
        end

        df << ""
        return df.join("\n")
      end

      def tar_io
        JoinedIO.new(
          self_tar_io,
          cache.tar_io
        )
      end

      def self_tar_io
        sio = StringIO.new
        tar = Gem::Package::TarWriter.new(sio)
        tar.add_file(NAME,'0777') do |io|
          io.write(dockerfile)
        end
        #tar.close
        sio.rewind
        return sio
      end

    private

      attr :logger

      def file_map
        prefix = ""
        to = ""
        if cache.respond_to? :prefix
          prefix = cache.prefix
        end
        if cache.respond_to? :to
          to = cache.to || ""
        end
        fm = cache.file_map
        if fm.nil?
          return { prefix => to }
        end
        if fm.size == 1
          key, value = fm.first
          key = key.gsub(%r!\A\./|/\z!,'')
          if ["",".","./"].include?(value) && key == prefix
            logger.hint("You can remove the file_map: #{fm.inspect} option on source. The given value is the default")
          end
        end
        return fm
      end

      def map_to(dir)
        if ['','.'].include? dir
          return '/tmp/build'
        else
          return File.join('/tmp/build',dir)
        end
      end

      def map_from(dir)
        if dir == ''
          return '.'
        else
          return dir
        end
      end

    end

    class Build < Struct.new(:base, :variables, :recipe)

      attr :options
      private :options

      def initialize(base, variables, recipe, options = {})
        variables = variables.dup.freeze
        raise Fry::WithData('unknown flavour', 'flavour' => variables[:flavour]) unless ['debian','redhat'].include? variables[:flavour]
        @options = options.dup.freeze
        super(base, variables, recipe)
      end

      def dockerfile
        df = {
          source: [],
          dependencies: [],
          build: []
        }
        df[:source] << "FROM #{base}"
        workdir = '/tmp/build'
        # TODO: get this from cache, not from the source itself
        if recipe.source.respond_to? :to
          to = recipe.source.to || ""
          workdir = File.expand_path(to, workdir)
        end
        df[:source] << "WORKDIR #{workdir}"

        # need to add external sources before running any command
        recipe.build_mounts.each do |source, target|
          df[:dependencies] << "COPY #{source} ./#{target}"
        end

        recipe.before_dependencies_steps.each do |step|
          df[:dependencies] << "RUN #{step.to_s}"
        end

        if build_dependencies.any?
          case(variables[:flavour])
          when 'debian'
            update = ''
            if options[:update]
              update = 'apt-get update && '
            end
            df[:dependencies] << "ARG DEBIAN_FRONTEND=noninteractive"
            df[:dependencies] << "RUN #{update}apt-get install --no-install-recommends --yes #{Shellwords.join(build_dependencies)}"
          when 'redhat'
            df[:dependencies] << "RUN yum -y install #{Shellwords.join(build_dependencies)}"
          else
            raise "Unknown flavour: #{variables[:flavour]}"
          end
        end

        recipe.before_build_steps.each do |step|
          df[:build] << "RUN #{step.to_s}"
        end

        df[:build] << "COPY .build.sh #{workdir}/"
        df[:build] << "CMD #{workdir}/.build.sh"
        recipe.apply_dockerfile_hooks(df)
        return [*df[:source],*df[:dependencies],*df[:build],""].join("\n")
      end

      def build_sh
        df = ['#!/bin/bash']
        df << 'set -e'
        recipe.steps.each do |v|
          if v.respond_to? :name
            df << "echo -e '\\e[1;32m====> #{Shellwords.escape v.name}\\e[0m'"
          end
          df << v.to_s
        end
        df << ''
        return df.join("\n")
      end

      def tar_io
        sio = StringIO.new
        tar = Gem::Package::TarWriter.new(sio)
        tar.add_file('.build.sh','0777') do |io|
          io.write(build_sh)
        end
        tar.add_file(NAME,'0777') do |io|
          io.write(dockerfile)
        end
        recipe.build_mounts.each do |source, _|
          tar.add_file(source,'0777') do |io|
            io.write(File.read(source))
          end
        end
        #tar.close
        sio.rewind
        return sio
      end

    private
      def build_dependencies
        return @build_dependencies if @build_dependencies
        deps = []
        (recipe.build_depends.merge recipe.depends).each do |k,v|
          install = v.fetch(:install,true)
          next unless install
          case( install )
          when true
            deps << simplify_build_dependency(k)
          when String
            deps << simplify_build_dependency(install)
          end
        end
        @build_dependencies = deps.sort
      end

      def simplify_build_dependency( dep )
        dep.split('|').first.strip
      end
    end

  end
end ; end
