require 'fpm/fry/detector'
require 'fpm/fry/inspector'
require 'fpm/fry/client'
require 'rubygems/package/tar_header'
describe FPM::Fry::Detector do

  Detector = FPM::Fry::Detector

  context 'mocked' do
    let(:inspector){
      inspector = double('inspector')
      allow(inspector).to receive(:exists?).with(String).and_return(false)
      allow(inspector).to receive(:link_target).with(String).and_return(nil)
      allow(inspector).to receive(:read_content).with(String).and_raise(FPM::Fry::Client::FileNotFound)
      inspector
    }

    subject{
      Detector.detect(inspector)
    }

    context 'flavour' do

      it 'is debian when apt-get is present' do
        expect(inspector).to receive(:exists?).with('/usr/bin/apt-get').and_return true
        expect(subject[:flavour]).to eq 'debian'
      end

      it 'is redhat when rpm is present' do
        expect(inspector).to receive(:exists?).with('/bin/rpm').and_return true
        expect(subject[:flavour]).to eq 'redhat'
      end

    end

    context '/etc/lsb-release' do

      it 'is parsed for distribution' do
        expect(inspector).to receive(:read_content).with('/etc/lsb-release').and_return <<LSB
DISTRIB_ID=foo
Random trash
LSB
        expect(subject[:distribution]).to eq 'foo'
      end

      it 'is parsed for release' do
        expect(inspector).to receive(:read_content).with('/etc/lsb-release').and_return <<LSB
DISTRIB_RELEASE=1.2.34
Random trash
LSB
        expect(subject[:release]).to eq '1.2.34'
      end

    end

    context '/etc/debian_version' do

      it 'is parsed for version' do
        expect(inspector).to receive(:read_content).with('/etc/debian_version').and_return(<<LSB)
6.0.5
LSB
        expect(subject[:release]).to eq '6.0.5'
      end

      it 'sets distribution to debian' do
        expect(inspector).to receive(:read_content).with('/etc/debian_version').and_return(<<LSB)
6.0.5
LSB
        expect(subject[:distribution]).to eq 'debian'
      end

    end

    context '/etc/redhat-release' do

      it 'is parsed for version' do
        expect(inspector).to receive(:read_content).with('/etc/redhat-release').and_return(<<LSB)
Foobar release 1.33.7
LSB
        expect(subject[:release]).to eq '1.33.7'
      end

      it 'is parsed for distribution' do
        expect(inspector).to receive(:read_content).with('/etc/redhat-release').and_return(<<LSB)
Foobar release 1.33.7
LSB
        expect(subject[:distribution]).to eq 'foobar'
      end

    end

  end

  context 'with ubuntu:24.04' do

    let(:result) do
      result = nil
      with_inspector('ubuntu:24.04') do |inspector|
        result = Detector.detect(inspector)
      end
      result
    end

    it 'finds ubuntu' do
      expect(result[:distribution]).to eq('ubuntu')
    end

    it 'finds release 24.04' do
      expect(result[:release]).to eq('24.04')
    end

    it 'finds codename noble' do
      expect(result[:codename]).to eq('noble')
    end

    it 'finds flavour debian' do
      expect(result[:flavour]).to eq('debian')
    end

  end

  context 'with ubuntu:22.04' do

    let(:result) do
      result = nil
      with_inspector('ubuntu:22.04') do |inspector|
        result = Detector.detect(inspector)
      end
      result
    end

    it 'finds ubuntu' do
      expect(result[:distribution]).to eq('ubuntu')
    end

    it 'finds release 22.04' do
      expect(result[:release]).to eq('22.04')
    end

    it 'finds codename jammy' do
      expect(result[:codename]).to eq('jammy')
    end

    it 'finds flavour debian' do
      expect(result[:flavour]).to eq('debian')
    end

  end

  context 'with ubuntu:20.04' do

    let(:result) do
      result = nil
      with_inspector('ubuntu:20.04') do |inspector|
        result = Detector.detect(inspector)
      end
      result
    end

    it 'finds ubuntu' do
      expect(result[:distribution]).to eq('ubuntu')
    end

    it 'finds release 20.04' do
      expect(result[:release]).to eq('20.04')
    end

    it 'finds codename focal' do
      expect(result[:codename]).to eq('focal')
    end

    it 'finds flavour debian' do
      expect(result[:flavour]).to eq('debian')
    end

  end

  context 'with debian:11' do

    let(:result) do
      result = nil
      with_inspector('debian:11') do |inspector|
        result = Detector.detect(inspector)
      end
      result
    end

    it 'finds debian' do
      expect(result[:distribution]).to eq('debian')
    end

    it 'finds release 11.*' do
      expect(result[:release]).to match /\A11\.\d+/
    end

    it 'finds codename bullseye' do
      expect(result[:codename]).to eq('bullseye')
    end

    it 'finds flavour debian' do
      expect(result[:flavour]).to eq('debian')
    end

  end

  context 'with debian:12' do

    let(:result) do
      result = nil
      with_inspector('debian:12') do |inspector|
        result = Detector.detect(inspector)
      end
      result
    end

    it 'finds debian' do
      expect(result[:distribution]).to eq('debian')
    end

    it 'finds release 12.*' do
      expect(result[:release]).to match /\A12\.\d+/
    end

    it 'finds codename bookworm' do
      expect(result[:codename]).to eq('bookworm')
    end

    it 'finds flavour debian' do
      expect(result[:flavour]).to eq('debian')
    end

  end
end
