#!/usr/bin/ruby

# Copyright 2017 Jonathan Riddell <jr@jriddell.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

begin
  require 'docker'
rescue
  puts 'Could not find docker-api library, run: sudo gem install docker-api'
  exit 1
end
require 'optparse'
require 'mkmf'

=begin
A wee command to simplify running KDE neon Docker images.

KDE neon Docker images are the fastest and easiest way to test out KDE's
software.  You can use them on top of any Linux distro.

## Pre-requisites

Install Docker and ensure you add yourself into the necessary group.
Also install Xephyr which is the X-server-within-a-window to run
Plasma.  With Ubuntu this is:

```apt install docker.io xserver-xephyr
usermod -G docker
newgrp docker
```

# Run

To run a full Plasma session of Neon Developer Unstable Edition:
`neondocker`

To run a full Plasma session of Neon User Edition:
`neondocker --edition user`

For more options see
`neondocker --help`
=end
class NeonDocker
  attr_accessor :options # settings
  attr_accessor :tag # docker image tag to use
  attr_accessor :container # my Docker::Container

  def command_options
    @options = { pull: false, all: false, edition: 'dev-unstable', kill: false }
    OptionParser.new do |opts|
      opts.banner = 'Usage: neondocker [options] [standalone-application]'

      opts.on('-p', '--pull', 'Always pull latest version') do |v|
        @options[:pull] = v
      end
      opts.on('-a', '--all',
              'Use Neon All images (larger, contains all apps)') do |v|
        @options[:all] = v
      end
      opts.on('-e', '--edition EDITION',
              '[user-lts,user,dev-stable,dev-unstable]') do |v|
        @options[:edition] = v
      end
      opts.on('-k', '--keep-alive', 'keep-alive container on exit') do |v|
        @options[:keep_alive] = v
      end
      opts.on('-r', '--reattach',
              'reuse an existing container [assumes -k]') do |v|
        @options[:reattach] = v
      end
      opts.on('-n', '--new',
              'Always start a new container even if one is already running' \
              'from the requested image') { |v| @options[:new] = v }
      opts.on('-w', '--wayland', 'Run a Wayland session') do |v|
        @options[:wayland] = v
      end
      opts.on_tail('standalone-application: Run a standalone application ' \
                   'rather than full Plasma shell. Assumes -n to always ' \
                   'start a new container.')
    end.parse!

    edition_options = ['user-lts', 'user', 'dev-stable', 'dev-unstable']
    unless edition_options.include?(@options[:edition])
      puts "Unknown edition. Valid editions are: #{edition_options}"
      exit 1
    end
    @options
  end

  def validate_docker
      Docker.validate_version!
    rescue
      puts 'Could not connect to Docker, check it is installed, running and ' \
           'your user is in the right group for access'
      exit 1
  end

  # Has the image already been downloaded to the local Docker?
  def docker_has_image?
    !Docker::Image
      .all
      .find { |image| image.info['RepoTags'].include?(@tag) }.nil?
  end

  def docker_image_tag
    image_type = @options[:all] ? 'all' : 'plasma'
    @tag = 'kdeneon/' + image_type + ':' + @options[:edition]
  end

  def docker_pull
    puts "Downloading image #{@tag}"
    Docker::Image.create('fromImage' => @tag)
  end

  # Is the command available to run?
  def installed?(command)
    MakeMakefile.find_executable(command)
  end

  def running_xhost
    unless installed?('xhost')
      puts 'xhost is not installed, run apt install xserver-xephyr or similar'
      exit 1
    end
    system('xhost +')
    yield
    system('xhost -')
  end

  def xdisplay
    return @xdisplay if defined? @xdisplay
    @xdisplay = (0..1024).find { |i| !File.exist?("/tmp/.X11-unix/X#{i}") }
  end

  def running_xephyr
    installed = installed?('Xephyr')
    unless installed
      puts 'Xephyr is not installed, apt-get install xserver-xephyr or similar'
      exit 1
    end
    xephyr = IO.popen("Xephyr -screen 1024x768 :#{xdisplay}")
    yield
    Process.kill("KILL", xephyr.pid)
  end

  # If this image already has a container then use that, else start a new one
  def container
    return @container if defined? @container
    if @options[:reattach]
      all_containers = Docker::Container.all(all: true)
      all_containers.each do |container|
        if container.info['Image'] == @tag
          @container = Docker::Container.get(container.info['id'])
        end
      end
      begin
        @container = Docker::Container.create('Image' => @tag)
      rescue Docker::Error::NotFoundError
        puts "Could not find an image with @tag #{@tag}"
        return nil
      end
    elsif !ARGV.empty?
      @container = Docker::Container.create('Image' => @tag,
                                            'Cmd' => ARGV,
                                            'Env' => ['DISPLAY=:0'])
    elsif @options[:wayland]
      @container = Docker::Container.create('Image' => @tag,
                                            'Env' => ['DISPLAY=:0'],
                                            'Cmd' => ['startplasmacompositor'])
    else
      @container = Docker::Container.create('Image' => @tag,
                                            'Env' => ["DISPLAY=:#{xdisplay}"])
    end
    @container
  end

  # runs the container and wait until Plasma or whatever has stopped running
  def run_container
    # find devices to bind for Wayland
    devices = Dir["/dev/dri/*"] + Dir["/dev/video*"]
    devices_list = []
    devices.each do |dri|
      devices_list.push({'PathOnHost' => dri, 'PathInContainer' => dri, 'CgroupPermissions' => 'mrw'})
    end
    container.start('Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'],
                    'Devices' => devices_list,
                    'Privileged' => true)
    container.refresh!
    while container.info['State']['Status'] == 'running'
      sleep 1
      container.refresh!
    end
    if !@options[:keep_alive] || @options[:reattach]
      container.delete
    end
  end
end

if $PROGRAM_NAME == __FILE__
  neon_docker = NeonDocker.new
  options = neon_docker.command_options
  neon_docker.validate_docker
  neon_docker.docker_image_tag
  options[:pull] = true unless neon_docker.docker_has_image?
  neon_docker.docker_pull if options[:pull]
  if !ARGV.empty? || options[:wayland]
    neon_docker.running_xhost do
      neon_docker.run_container
    end
  else
    neon_docker.running_xephyr do
      neon_docker.run_container
    end
  end
  exit 0
end
