#!/usr/bin/ruby

require 'docker'
require 'optparse'

def command_options
    options = {pull: false, all: false, edition: 'user', kill: false }
    OptionParser.new do |opts|
        opts.banner = "Usage: neondocker [options]"

        opts.on('-p', '--pull', 'Always pull latest version') { |v| options[:pull] = v }
        opts.on('-a', '--all', 'Use Neon All images (larger, contains all apps)') { |v| options[:all] = v }
        opts.on('-e', '--edition EDITION', '[user-lts,user,dev-stable,dev-unstable]') { |v| options[:edition] = v }
        opts.on('-k', '--kill', 'kill container on exit') { |v| options[:kill] = v }
        opts.on('-n', '--new', 'Always start a new container even if one is already running from the requested image') { |v| options[:new] = v }
    end.parse!

    editionoptions = ['user-lts','user','dev-stable','dev-unstable']
    if !editionoptions.include?(options[:edition])
        puts "Unknown edition. Valid editions are: userlts,user,devstable,devunstable"
        exit 1
    end
    return options
end

def validate_docker
    begin
        Docker.validate_version!
    rescue
        puts "Could not connect to Docker, check it is installed, running and your user is in the right group for access"
        exit 1
    end
end

# Has the image already been downloaded to the local Docker?
def docker_has_image?(tag)
    # jings there has to be a way to filter for this
    Docker::Image.all().each do |image|
        if image.info['RepoTags'] != nil
            if image.info['RepoTags'].include?(tag)
                return true
            end
        end
    end
    false
end

def docker_image_tag(options)
    imageType = options[:all] ? "all" : "plasma"
    tag = "kdeneon/" + imageType + ":" + options[:edition]
end
    
def docker_pull(tag)
    image = Docker::Image.create('fromImage' => tag)
end

def command?(command)
    system("which #{ command} > /dev/null 2>&1")
end

def running_xephyr
    installed = command?('Xephyr')
    if not installed
        puts "Xephyr is not installed, apt-get install xserver-xephyr or similar"
        exit 1
    end
    system('Xephyr :1 &')
    yield
    # FIXME don't kill all Xephyrs, only this one
    system('killall Xephyr')
end

# If this image already has a container then use that, else start a new one
# TODO option to always start a new one
def get_container(tag)
    allContainers = Docker::Container.all(all: true)
    allContainers.each do |container|
        if container.info['Image'] == tag
            return Docker::Container.get(container.info['id'])
        end
    end
    begin
        return Docker::Container.create('Image' => tag)
    rescue Docker::Error::NotFoundError
        puts "Could not find an image with tag #{tag}"
        return nil
    end
end

# runs the container and wait until Plasma or whatever has stopped running
def run_container(tag, alwaysNew)
    if alwaysNew
        container = Docker::Container.create('Image' => tag)
    else
        container = get_container(tag)
    end
    container.start('Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'])
    container.refresh!
    while container.info['State']['Status'] == "running"
        puts 'running'
        sleep 1
        container.refresh!
    end
end


if $0 == __FILE__
    options = command_options
    validate_docker
    tag = docker_image_tag(options)
    if not docker_has_image?(tag)
        options[:pull] = true
    end
    if options[:pull]
        docker_pull(tag)
    end
    running_xephyr do
        run_container(tag, options[:new])
    end
    exit 0
end
# TODO run a single command
# TODO package it up
# TODO update wiki docs
