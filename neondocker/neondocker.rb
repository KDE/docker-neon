#!/usr/bin/ruby

=begin
Copyright 2017 Jonathan Riddell <jr@jriddell.org>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of
the License or (at your option) version 3 or any later version
accepted by the membership of KDE e.V. (or its successor approved
by the membership of KDE e.V.), which shall act as a proxy
defined in Section 14 of version 3 of the license.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

begin
    require 'docker'
rescue
    puts "Could not find docker-api library, run: sudo gem install docker-api"
    exit 1
end
require 'optparse'

$standalone_application = nil

def command_options
    options = {pull: false, all: false, edition: 'user', kill: false }
    OptionParser.new do |opts|
        opts.banner = "Usage: neondocker [options] [standalone-application]"

        opts.on('-p', '--pull', 'Always pull latest version') { |v| options[:pull] = v }
        opts.on('-a', '--all', 'Use Neon All images (larger, contains all apps)') { |v| options[:all] = v }
        opts.on('-e', '--edition EDITION', '[user-lts,user,dev-stable,dev-unstable]') { |v| options[:edition] = v }
        opts.on('-k', '--keep-alive', 'keep-alive container on exit') { |v| options[:keep_alive] = v }
        opts.on('-r', '--reattach', 'reuse an existing container [assumes -k]') { |v| options[:reattach] = v }
        opts.on('-n', '--new', 'Always start a new container even if one is already running from the requested image') { |v| options[:new] = v }
        opts.on('-w', '--wayland', 'Run a Wayland session') { |v| options[:wayland] = v }
        opts.on_tail("standalone-application: Run a standalone application rather than full Plasma shell. Assumes -n to always start a new container.")
    end.parse!

    edition_options = ['user-lts','user','dev-stable','dev-unstable']
    if !edition_options.include?(options[:edition])
        puts "Unknown edition. Valid editions are: #{edition_options}"
        exit 1
    end
    $standalone_application = ARGV
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
    puts "Downloading image #{tag}"
    image = Docker::Image.create('fromImage' => tag)
end

# Is the command available to run?
def command?(command)
    system("which #{ command} > /dev/null 2>&1")
end

def running_xhost
    installed = command?('xhost')
    if not installed
        puts "xhost is not installed, apt-get install xserver-xephyr or similar"
        exit 1
    end
    system('xhost +')
    yield
    system('xhost -')
end

def get_xdisplay
    i = 1
    while FileTest.exist?("/tmp/.X11-unix/X#{i}")
        i = i + 1
    end
    return i
end

def running_xephyr(xdisplay)
    installed = command?('Xephyr')
    if not installed
        puts "Xephyr is not installed, apt-get install xserver-xephyr or similar"
        exit 1
    end
    xephyr = IO.popen("Xephyr -screen 1024x768 :#{xdisplay}")
    yield
    system("kill #{xephyr.pid}")
end

# If this image already has a container then use that, else start a new one
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
def run_container(tag, alwaysNew, reattach, keep_alive, wayland = false, xdisplay = 0)
    if reattach
        container = get_container(tag)
    elsif $standalone_application.length > 0
        container = Docker::Container.create('Image' => tag, 'Cmd' => $standalone_application, 'Env' => ['DISPLAY=:0'])
    elsif wayland
        container = Docker::Container.create('Image' => tag, 'Env' => ["DISPLAY=:0"], 'Cmd' => ['startplasmacompositor'])
    else
        container = Docker::Container.create('Image' => tag, 'Env' => ["DISPLAY=:#{xdisplay}"])
    end
    container.start('Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'],
                    'Devices' => [
                        {"PathOnHost" => '/dev/video0', 'PathInContainer' => '/dev/video0', 'CgroupPermissions' => 'mrw'},
                        {"PathOnHost" => '/dev/dri/card0', 'PathInContainer' => '/dev/dri/card0', 'CgroupPermissions' => 'mrw'},
                        {"PathOnHost" => '/dev/dri/controlD64', 'PathInContainer' => '/dev/dri/controlD64', 'CgroupPermissions' => 'mrw'},
                        {"PathOnHost" => '/dev/dri/renderD128', 'PathInContainer' => '/dev/dri/renderD128', 'CgroupPermissions' => 'mrw'}
                    ])
    container.refresh!
    while container.info['State']['Status'] == "running"
        sleep 1
        container.refresh!
    end
    if not keep_alive or reattach
        container.delete
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
    if $standalone_application.length > 0 or options[:wayland]
        running_xhost do
            run_container(tag, options[:new], options[:reattach], options[:keep_alive], options[:wayland])
        end
    else
        xdisplay = get_xdisplay
        running_xephyr(xdisplay) do
            run_container(tag, options[:new], options[:reattach], options[:keep_alive], options[:wayland], xdisplay)
        end
    end
    exit 0
end
