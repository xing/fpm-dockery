require 'fpm/fry/recipe/builder'
require 'fpm/fry/inspector'
require 'fpm/fry/plugin/init'
describe FPM::Fry::Plugin::Init do

  context 'init syntax' do

    let(:inspector){
      inspector = double('inspector')
      # this should cause the plugin to find sysv
      allow(inspector).to receive(:exists?).with(String).and_return(false)
      allow(inspector).to receive(:link_target).with(String).and_return(nil)
      allow(inspector).to receive(:exists?).with("/etc/init.d").and_return(true)
      inspector
    }

    let(:builder){
      FPM::Fry::Recipe::Builder.new({}, inspector: inspector)
    }

    it 'returns the init system' do
      expect(builder.plugin('init')).to be_a FPM::Fry::Plugin::Init::System
    end

    it 'caches the init system' do
      a = builder.plugin('init')
      b = builder.plugin('init')
      expect(a).to be b
    end

    it 'adds a method returning the init system' do
      builder.plugin('init')
      expect(builder.init).to be_a FPM::Fry::Plugin::Init::System
    end
  end

  context 'init detection (real)' do
    context 'with ubuntu:24.04' do
      skip 'finds systemd' do
        with_inspector('ubuntu:24.04') do |insp|
          builder = FPM::Fry::Recipe::Builder.new({},inspector: insp)
          builder.extend(FPM::Fry::Plugin::Init)
          expect(builder.init).to be_systemd
        end
      end
    end

    context 'with ubuntu:22.04' do
      skip 'finds systemd' do
        with_inspector('ubuntu:22.04') do |insp|
          builder = FPM::Fry::Recipe::Builder.new({},inspector: insp)
          builder.extend(FPM::Fry::Plugin::Init)
          expect(builder.init).to be_systemd
        end
      end
    end

    context 'with ubuntu:20.04' do
      skip 'finds systemd' do
        with_inspector('ubuntu:20.04') do |insp|
          builder = FPM::Fry::Recipe::Builder.new({},inspector: insp)
          builder.extend(FPM::Fry::Plugin::Init)
          expect(builder.init).to be_systemd
        end
      end
    end

    context 'with debian:bookworm' do
      it 'finds sysv' do
        with_inspector('debian:12') do |insp|
          builder = FPM::Fry::Recipe::Builder.new({},inspector: insp)
          builder.extend(FPM::Fry::Plugin::Init)
          expect(builder.init).to be_sysv
          expect(builder.init).not_to be_with :chkconfig
          expect(builder.init).to be_with :'update-rc.d'
          expect(builder.init).to be_with :'invoke-rc.d'
        end
      end
    end


  end

end
