require 'fpm/fry/client'
require 'webmock/rspec'
require 'rubygems/package'
require 'tempfile'
require 'fileutils'
describe FPM::Fry::Client do

  subject{
    FPM::Fry::Client.new(docker_url: 'http://dock.er')
  }

  before(:each) do
    stub_request(:get, "http://dock.er/version").
      to_return(:status => 200, :body =>'{"ApiVersion":"1.9"}', :headers => {})
  end

  describe '#pull' do
    it 'pulls an existing image' do
      client = real_docker
      client.delete("ubuntu:jammy")
      res = nil
      expect{
        res = client.pull("ubuntu:jammy")
      }.to output(/Status: Downloaded newer image for ubuntu:jammy/).to_stdout
      expect(res.status).to eq(200)
    end
  end

  describe '#read' do
    context 'existing file' do
      let(:body){
        body = StringIO.new
        tar = Gem::Package::TarWriter.new(body)
        tar.add_file('foo','0777') do |io|
          io.write("bar")
        end
        body.rewind
        body
      }

      it 'is yielded' do
        stub_request(:get, "http://dock.er/v1.9/containers/deadbeef/archive?path=foo").to_return(status: 200, body: body.string)
        expect{|yld|
          subject.read('deadbeef','foo', &yld)
        }.to yield_with_args(Gem::Package::TarReader::Entry)
      end
    end

    context 'missing file' do
      it 'raises' do
        stub_request(:get, "http://dock.er/v1.9/containers/deadbeef/archive?path=foo").to_return(status: 404, body: "")

        expect{
          subject.read('deadbeef','foo'){}
        }.to raise_error(FPM::Fry::Client::FileNotFound) do |e|
          expect(e.data).to match(
            'path' => 'foo',
            'docker.message' => '',
            'docker.container' => 'deadbeef'
          )
        end
      end

      it 'raises (real)' do
        with_container('ubuntu:22.04') do |id|
          expect{
            real_docker.read(id,'foo'){}
          }.to raise_error(FPM::Fry::Client::FileNotFound) do |e|
            expect(e.data).to match(
              'path' => 'foo',
              'docker.message'=> /Could not find the file foo in container \h{64}\z/,
              'docker.container' => /\A\h{64}\z/
            )
          end
        end
      end
    end

    context 'missing container' do
      it 'raises' do
        stub_request(:get,'http://dock.er/v1.9/containers/deadbeef/archive?path=foo').to_return(status: 404, body:'{"message":"No such container:"}')
        expect{
          subject.read('deadbeef','foo'){}
        }.to raise_error(FPM::Fry::Client::ContainerNotFound) do |e|
          expect(e.data).to match(
            'docker.message' => 'No such container:',
            'docker.container' => 'deadbeef'
          )
        end
      end

      it 'raises (real)' do
        expect{
          real_docker.read('ishouldreallynotexist','foo'){}
        }.to raise_error(FPM::Fry::Client::ContainerNotFound) do |e|
          expect(e.data).to match(
            'docker.message'=> "No such container: ishouldreallynotexist",
            'docker.container' => 'ishouldreallynotexist'
          )
        end
      end
    end

  end

  describe '#copy' do
    context 'a simple file' do
      let(:body){
        body = StringIO.new
        tar = Gem::Package::TarWriter.new(body)
        tar.add_file('foo','0777') do |io|
          io.write("bar")
        end
        body.rewind
        body
      }

      let!(:tmpdir){
        Dir.mktmpdir('fpm-fry')
      }

      after(:each) do
        FileUtils.rm_rf(tmpdir)
      end

      it 'is copied' do
        stub_request(:get, "http://dock.er/v1.9/containers/deadbeef/archive?path=foo").to_return(status: 200, body: body.string)
        subject.copy('deadbeef','foo', { 'foo' => tmpdir + '/foo' })
        expect( File.read(File.join(tmpdir,'foo')) ).to eq('bar')
      end
    end

    context 'a folder with a symlink' do
      let(:body){
        body = StringIO.new
        body.write Gem::Package::TarHeader.new(
          name: 'foo', prefix: '', mode: '0777',
          size: 0, mtime: Time.now, typeflag: '5'
        )
        body.write Gem::Package::TarHeader.new(
          name: 'a', prefix: 'foo', mode: '0777',
          size: 0, mtime: Time.now, typeflag: '2',
          linkname: 'b'
        )
        body.write( "\0" * 1024 )
        body.rewind
        body
      }

      let!(:tmpdir){
        Dir.mktmpdir('fpm-fry')
      }

      after(:each) do
        FileUtils.rm_rf(tmpdir)
      end

      it 'is copied' do
        stub_request(:get, "http://dock.er/v1.9/containers/deadbeef/archive?path=foo").to_return(status: 200, body: body.string)
        subject.copy('deadbeef','foo', {'foo' => tmpdir + '/foo' , 'foo/a' => tmpdir + '/foo/a'})
        expect( File.readlink(File.join(tmpdir,'foo/a')) ).to eq('b')
      end
    end
  end
end
