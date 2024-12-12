require 'bundler/setup'
require 'bundler/gem_tasks'

task :default => "test:units"

task :test => "test:all"

IMAGES = %w(ubuntu:20.04 ubuntu:22.04 ubuntu:24.04 debian:11 debian:12)

namespace :test do
  task :setup do
    known_images = `docker images --format '{{.Repository}}:{{.Tag}}'`.chomp.split("\n")
    IMAGES.each do |img|
      sh "docker pull #{img}" unless known_images.include?(img)
    end
  end

  task :units do
    sh "rspec"
  end

  task :all => :setup do
    sh "FPM_FRY_DOCKER=yes rspec"
  end
end
