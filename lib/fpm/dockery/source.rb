module FPM; module Dockery ; module Source
  module Null

    module Cache
      def self.tar_io
        StringIO.new("\x00"*1024)
      end
      def self.file_map
        return {}
      end
    end

    def self.build_cache(*_)
      return Cache
    end

  end
end ; end ; end
