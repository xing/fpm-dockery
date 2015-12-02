require 'tmpdir'
require 'fileutils'
require 'fpm/fry/command/cook'
describe FPM::Fry::Command::Cook do

  let(:tmpdir) do
    Dir.mktmpdir('fpm-fry')
  end

  let(:targetdir) do
    Dir.mktmpdir('fpm-fry-target')
  end

  let(:ui) do
    FPM::Fry::UI.new(StringIO.new,StringIO.new,nil,tmpdir)
  end

  after(:each) do
    FileUtils.rm_rf(tmpdir)
    FileUtils.rm_rf(targetdir)
  end

  around(:example) do |example|
    Dir.chdir(targetdir) do
      example.run
    end
  end

  context 'without recipe' do
    subject do
      s = FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    it 'returns an error' do
      expect(subject.logger).to receive(:error).with("Recipe not found", a_hash_including(recipe: "recipe.rb"))
      expect(subject.execute).to eq 1
    end
  end

  describe '#output_class' do

    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    context 'debian-automatic' do
      before(:each) do
        subject.flavour = 'debian'
      end
      it 'returns Deb' do
        expect(subject.output_class).to eq FPM::Package::Deb
      end
    end

    context 'redhat-automatic' do
      before(:each) do
        subject.flavour = 'redhat'
      end
      it 'returns Deb' do
        expect(subject.output_class).to eq FPM::Package::RPM
      end
    end

  end

  describe '#builder' do

    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    context 'trivial case' do
      before(:each) do
        subject.detector = FPM::Fry::Detector::String.new('ubuntu-12.04')
        subject.flavour = 'debian'
        subject.recipe = File.expand_path('../data/recipe.rb',File.dirname(__FILE__))
      end
      it 'works' do
        expect(subject.builder).to be_a FPM::Fry::Recipe::Builder
      end
      it 'contains the right variables' do
        expect(subject.builder.variables).to eq(distribution: 'ubuntu', distribution_version: '12.04', flavour: 'debian', codename: 'precise')
      end
      it 'has exactly one package' do
        expect(subject.builder.recipe.packages.size).to eq 1
      end
      it 'has loaded the right recipe' do
        expect(subject.builder.recipe.packages[0].name).to eq 'foo'
      end
    end

  end

  describe '#image_id' do
    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    context 'with an existing image' do
      before(:each) do
        subject.image = 'foo:bar'
        stub_request(:get, "http://unix/version").
          to_return(:status => 200, :body =>'{"ApiVersion":"1.9"}', :headers => {})
        stub_request(:get, "http://unix/v1.9/images/foo:bar/json").
                     to_return(:status => 200, :body => "{\"id\":\"deadbeef\"}")
      end
      it 'returns the id' do
        expect(subject.image_id).to eq 'deadbeef'
      end
    end
  end

  describe '#build_image' do
    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    context 'with an existing cache image' do
      let(:builder) do
        FPM::Fry::Recipe::Builder.new({}, FPM::Fry::Recipe.new, logger: subject.logger)
      end

      before(:each) do
        subject.image_id = 'f'*32
        subject.flavour  = 'unknown'
        subject.cache = FPM::Fry::Source::Null::Cache
        subject.builder = builder
        stub_request(:get, "http://unix/version").
          to_return(:status => 200, :body =>'{"ApiVersion":"1.9"}', :headers => {})
        stub_request(:get, "http://unix/v1.9/images/fpm-fry:5cb0db32efafac12020670506c62c39/json").
                    to_return(:status => 200, :body => "")
        stub_request(:post, "http://unix/v1.9/build?dockerfile=Dockerfile.fpm-fry&rm=1").
                    with(:headers => {'Content-Type'=>'application/tar'}).
                    to_return(:status => 200, :body => '{"stream":"Successfully built deadbeef"}', :headers => {})
      end
      it 'returns the id' do
        expect(subject.build_image).to eq 'deadbeef'
      end
    end

    context 'without an existing cache image' do
      let(:builder) do
        FPM::Fry::Recipe::Builder.new({}, FPM::Fry::Recipe.new, logger: subject.logger)
      end

      before(:each) do
        subject.image_id = 'f'*32
        subject.flavour  = 'unknown'
        subject.cache = FPM::Fry::Source::Null::Cache
        subject.builder = builder
        stub_request(:get, "http://unix/version").
          to_return(:status => 200, :body =>'{"ApiVersion":"1.9"}', :headers => {})
        stub_request(:get, "http://unix/v1.9/images/fpm-fry:5cb0db32efafac12020670506c62c39/json").
                    to_return(:status => 404)
        stub_request(:post, "http://unix/v1.9/build?rm=1&dockerfile=Dockerfile.fpm-fry&t=fpm-fry:5cb0db32efafac12020670506c62c39").
                    with(:headers => {'Content-Type'=>'application/tar'}).
                    to_return(:status => 200, :body => '{"stream":"Successfully built xxxxxxxx"}', :headers => {})
        stub_request(:post, "http://unix/v1.9/build?dockerfile=Dockerfile.fpm-fry&rm=1").
                    with(:headers => {'Content-Type'=>'application/tar'}).
                    to_return(:status => 200, :body => '{"stream":"Successfully built deadbeef"}', :headers => {})
      end
      it 'returns the id' do
        expect(subject.build_image).to eq 'deadbeef'
      end
    end

  end

  describe '#build!' do
    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    context 'trivial case' do

      before(:each) do
        subject.build_image = 'fpm-fry:x'
        stub_request(:get, "http://unix/version").
          to_return(:status => 200, :body =>'{"ApiVersion":"1.9"}', :headers => {})
        stub_request(:post, "http://unix/v1.9/containers/create").
          with(:body => "{\"Image\":\"fpm-fry:x\"}",
               :headers => {'Content-Type'=>'application/json'}).
          to_return(:status => 201, :body => '{"Id":"caafffee"}')
        stub_request(:post, "http://unix/v1.9/containers/caafffee/start").
          with(:body => "{}",
               :headers => {'Content-Type'=>'application/json'}).
          to_return(:status => 204)
        stub_request(:post, "http://unix/v1.9/containers/caafffee/attach?stderr=1&stdout=1&stream=1").
          to_return(:status => 200, :body => [2,6,"stderr",1,6,"stdout"].pack("I<I>Z6I<I>Z6"))
        stub_request(:post, "http://unix/v1.9/containers/caafffee/wait").
          to_return(:status => 200, :body => '{"StatusCode":0}')
        stub_request(:delete, "http://unix/v1.9/containers/caafffee").
          to_return(:status => 200)
      end
      it 'yields the id' do
        expect{|yld| subject.build!(&yld) }.to yield_with_args('caafffee')
      end
    end
  end

  describe '#update?' do

    let(:client) do
      c = double('client')
      allow(c).to receive(:url){|*args| args.join('/') }
      c
    end

    subject do
      s = FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
      s.client = client
      s
    end

    context 'debian auto without cache' do

      before(:each) do
        subject.flavour = 'debian'
        subject.image = 'ubuntu:precise'
        allow(subject.client).to receive(:post).
          with(a_hash_including(path: 'containers/create')).
          and_return(double('response', body: '{"Id":"deadbeef"}'))
        allow(subject.client).to receive(:read).
          with('deadbeef','/var/lib/apt/lists').
          and_yield(double('lists', header: double('lists.header', name: 'lists/')))
        allow(subject.client).to receive(:delete).
          with(a_hash_including(path: 'containers/deadbeef'))
      end

      it 'is true' do
        expect(subject.logger).not_to receive(:info)
        expect(subject.update?).to eq true
      end
    end

    context 'debian auto with cache' do

      before(:each) do
        subject.flavour = 'debian'
        subject.image = 'ubuntu:precise'
        allow(subject.client).to receive(:post).
          with(a_hash_including(path: 'containers/create')).
          and_return(double('response', body: '{"Id":"deadbeef"}'))
        allow(subject.client).to receive(:read).
          with('deadbeef','/var/lib/apt/lists').
          and_yield(double('lists', header: double('lists.header', name: 'lists/'))).
          and_yield(double('cache', header: double('cache.header', name: 'lists/doenst_matter')))
        allow(subject.client).to receive(:delete).
          with(a_hash_including(path: 'containers/deadbeef'))
      end

      it 'is true' do
        expect(subject.logger).to receive(:info).with("/var/lib/apt/lists is not empty, you could try to speed up builds with --update=never")
        expect(subject.update?).to eq true
      end
    end

  end

  describe '#packages' do

    subject do
      FPM::Fry::Command::Cook.new('fpm-fry', ui: ui)
    end

    let(:recipe) do
      recipe = FPM::Fry::Recipe.new
      recipe.packages[0].name = "foo"
      recipe
    end

    let(:builder) do
      FPM::Fry::Recipe::Builder.new({}, recipe, logger: subject.logger)
    end

    let(:output_class) do
      FPM::Package::Dir
    end

    before(:each) do 
      subject.builder = builder
      subject.output_class = output_class
    end

    context 'with one package' do

      it 'yields one packages' do
        expect{|p|
          subject.packages(&p)
        }.to yield_with_args({'**' => String})
      end

      it 'writes one package' do
        subject.packages{}
        expect( Dir.entries('.').sort ).to eq ['.','..','foo.dir']
      end

      it 'cleans up tmp' do
        subject.packages{}
        expect( Dir.entries(tmpdir) ).to eq ['.','..']
      end

    end

    context 'with multiple package' do

      before(:each) do
        builder.instance_eval do
          package 'blub' do
            files "/a/b"
          end
        end
      end

      it 'yields multiple packages' do
        expect{|p|
          subject.packages(&p)
        }.to yield_with_args({'/a/b' => String, '**' => String})
      end

      it 'writes one package' do
        subject.packages{}
        expect( Dir.entries('.').sort ).to eq ['.','..','blub.dir','foo.dir']
      end

      it 'cleans up tmp' do
        subject.packages{}
        expect( Dir.entries(tmpdir) ).to eq ['.','..']
      end

    end

  end

end
