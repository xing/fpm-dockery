require 'fpm/fry/recipe'
require 'fpm/fry/recipe/builder'
require 'fpm/fry/docker_file'
describe FPM::Fry::DockerFile do

  module DockerFileParams
    module ClassMethods
      def recipe
        @recipe ||= FPM::Fry::Recipe.new
        if block_given?
          yield FPM::Fry::Recipe::Builder.new(variables,recipe: recipe)
        end
        @recipe
      end

      def variables( x = nil )
        @variables = x if x
        @variables || {}
      end

      def base( x = nil )
        @base = x if x
        @base || "<base>"
      end
    end

    def variables
      self.class.variables
    end
    def cache
      FPM::Fry::Source::Null::Cache
    end
    def recipe
      self.class.recipe
    end
    def base
      self.class.base
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end

  describe 'Build' do

    subject do
      FPM::Fry::DockerFile::Build.new(base, variables,recipe)
    end

    describe '#build_sh' do

      context 'simple case' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        recipe do |b|
          b.run "foo", "bar", "--baz"
        end

        it 'works' do
          expect(subject.build_sh).to eq(<<'SHELL')
#!/bin/bash
set -e
echo -e '\e[1;32m====> foo\ bar\e[0m'
foo bar --baz
SHELL
        end
      end

    end

    describe '#docker_file' do

      context 'simple ubuntu' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        recipe do |b|
          b.build_depends 'blub'
          b.depends 'foo'
          b.depends 'arg'
        end

        it 'works' do
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install --no-install-recommends --yes arg blub foo
COPY .build.sh /tmp/build/
CMD /tmp/build/.build.sh
SHELL
        end
      end

      context 'simple centos' do
        include DockerFileParams

        variables(
          image: 'centos:6.5',
          distribution: 'centos',
          flavour: 'redhat'
        )

        recipe do |b|
          b.build_depends 'blub'
          b.depends 'foo'
          b.depends 'arg'
        end

        it 'works' do
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build
RUN yum -y install arg blub foo
COPY .build.sh /tmp/build/
CMD /tmp/build/.build.sh
SHELL
        end
      end

      context 'install overrides' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        recipe do |b|
          b.depends 'a'
          b.depends 'b', install: true
          b.depends 'c', install: false
          b.depends 'd', install: 'D'
          b.depends 'e', install: 'e=1.0.0'
        end

        it 'works' do
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install --no-install-recommends --yes D a b e\\=1.0.0
COPY .build.sh /tmp/build/
CMD /tmp/build/.build.sh
SHELL
        end
      end

      context 'dependencies with alternatives' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        recipe do |b|
          b.depends 'a | b'
        end

        it 'works' do
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install --no-install-recommends --yes a
COPY .build.sh /tmp/build/
CMD /tmp/build/.build.sh
SHELL
        end
      end

      context 'with a source responding to #to' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        before(:each) do
          allow(subject.recipe.source).to receive(:to).and_return 'src/foo'
        end

        it 'adjusts the paths' do
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build/src/foo
COPY .build.sh /tmp/build/src/foo/
CMD /tmp/build/src/foo/.build.sh
SHELL
        end

      end

      context 'with a dockerfile hook' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        let(:probe){
          probe = double(:probe)
          expect(probe).to receive(:call){|recipe,df|
            expect(recipe).to be_a FPM::Fry::Recipe
            expect(df).to match source: Array, dependencies: Array, build: Array
            df[:source] << "probe a"
            df[:dependencies] << "probe b"
            df[:build] << "probe c"
          }
          probe
        }

        recipe do |b|
          b.depends 'a | b'
        end

        it 'calls the hook' do
          subject.recipe.dockerfile_hooks << probe
          expect(subject.dockerfile).to eq(<<SHELL)
FROM <base>
WORKDIR /tmp/build
probe a
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install --no-install-recommends --yes a
probe b
COPY .build.sh /tmp/build/
CMD /tmp/build/.build.sh
probe c
SHELL
        end
      end

    end

    describe '#tar_io' do

       context 'simple ubuntu' do
        include DockerFileParams

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        it 'works' do
          io = subject.tar_io
          entries = FPM::Fry::Tar::Reader.new(io).map{|e| e.header.name }
          expect( entries ).to eq ['.build.sh','Dockerfile.fpm-fry']
        end

      end
    end
  end

  describe 'Source' do
    subject do
      FPM::Fry::DockerFile::Source.new(variables,cache)
    end

    describe '#docker_file' do

      context 'simple case' do
        include DockerFileParams
        let(:cache){
          c = double('cache')
          allow(c).to receive(:file_map){ nil }
          c
        }

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        it "map the files" do
          expect(subject.dockerfile).to eq(<<DOCKERFILE)
FROM ubuntu:precise
RUN mkdir /tmp/build
COPY . /tmp/build
DOCKERFILE
        end
      end

      context 'with a cache supporting prefix' do
        include DockerFileParams
        let(:cache){
          c = double('cache')
          allow(c).to receive(:prefix).and_return('a_prefix')
          allow(c).to receive(:file_map){ {'a_prefix' => '' } }
          allow(c).to receive(:logger).and_return(logger)
          c
        }

        variables(
          image: 'ubuntu:precise',
          distribution: 'ubuntu',
          flavour: 'debian'
        )

        it "map the files" do
          allow(logger).to receive(:hint).with(/\AYou can remove the file_map:/)
          expect(subject.dockerfile).to eq(<<DOCKERFILE)
FROM ubuntu:precise
RUN mkdir /tmp/build
COPY a_prefix /tmp/build
DOCKERFILE
        end

        it "hints that file_map can be removed" do
          expect(logger).to receive(:hint).with(/\AYou can remove the file_map:/)
          subject.dockerfile
        end

        it "hints that file_map can be removed even when the paths are not exactly the same" do
          allow(cache).to receive(:file_map).and_return( './a_prefix' => '' )
          expect(logger).to receive(:hint).with(/\AYou can remove the file_map:/)
          subject.dockerfile
        end

        it "hints that file_map can be removed even when the paths are not exactly the same" do
          allow(cache).to receive(:file_map).and_return( 'a_prefix/' => '' )
          expect(logger).to receive(:hint).with(/\AYou can remove the file_map:/)
          subject.dockerfile
        end
      end
    end

  end

end
