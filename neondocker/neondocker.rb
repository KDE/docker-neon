#!/usr/bin/env ruby

# Copyright 2017 Jonathan Riddell <jr@jriddell.org>
# Copyright 2015-2019 Harald Sitter <sitter@kde.org>
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

if $PROGRAM_NAME != __FILE__
  # Note that during program execution docker is required in the exec block
  # as it gets on-demand installed if applicable.
  begin
    require 'docker'
  rescue LoadError
    puts 'Could not find docker-api library, run: sudo gem install docker-api'
    exit 1
  end
end

require 'etc'
require 'optparse'
require 'shellwords'

# Finds executables. MakeMakefile is the only core ruby entity providing
# PATH based executable lookup, unfortunately it is really not meant to be
# used outside extconf.rb use cases as it mangles the main name scope by
# injecting itself into it (which breaks for example the ffi gem).
# The Shell interface's command-processor also has lookup code but it's not
# Windows compatible.
# NB: this is lifted from releaseme! should this need changing, change it there
# first! also mind the unit test.
class Executable
  attr_reader :bin

  def initialize(bin)
    @bin = bin
  end

  # Finds the executable in PATH by joining it with all parts of PATH and
  # checking if the resulting absolute path exists and is an executable.
  # This also honor's Windows' PATHEXT to determine the list of potential
  # file extensions. So find('gpg2') will find gpg2 on POSIX and gpg2.exe
  # on Windows.
  def find
    # PATHEXT on Windows defines the valid executable extensions.
    exts = ENV.fetch('PATHEXT', '').split(';')
    # On other systems we'll work with no extensions.
    exts << '' if exts.empty?

    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      path = unescape_path(path)
      exts.each do |ext|
        file = File.join(path, bin + ext)
        return file if executable?(file)
      end
    end

    nil
  end

  private

  class << self
    def windows?
      @windows ||= ENV['RELEASEME_FORCE_WINDOWS'] || mswin? || mingw?
    end

    private

    def mswin?
      @mswin ||= /mswin/ =~ RUBY_PLATFORM
    end

    def mingw?
      @mingw ||= /mingw/ =~ RUBY_PLATFORM
    end
  end

  def windows?
    self.class.windows?
  end

  def executable?(path)
    stat = File.stat(path)
  rescue SystemCallError
  else
    return true if stat.file? && stat.executable?
  end

  def unescape_path(path)
    # Strip qutation.
    # NB: POSIX does not define any quoting mechanism so you simply cannot
    # have colons in PATH on POSIX systems as a side effect we mustn't
    # strip quotes as they have no syntactic meaning and instead are
    # assumed to be part of the path
    # http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03
    return path.sub(/\A"(.*)"\z/m, '\1') if windows?
    path
  end
end

# A wee command to simplify running KDE neon Docker images.
#
# KDE neon Docker images are the fastest and easiest way to test out KDE's
# software.  You can use them on top of any Linux distro.
#
# ## Pre-requisites
#
# Install Docker and ensure you add yourself into the necessary group.
# Also install Xephyr which is the X-server-within-a-window to run
# Plasma.  With Ubuntu this is:
#
# ```apt install docker.io xserver-xephyr
# usermod -G docker
# newgrp docker
# ```
#
# # Run
#
# To run a full Plasma session of Neon Developer Unstable Edition:
# `neondocker`
#
# To run a full Plasma session of Neon User Edition:
# `neondocker --edition user`
#
# For more options see
# `neondocker --help`
class NeonDocker
  attr_accessor :options # settings
  attr_accessor :tag # docker image tag to use
  attr_accessor :container # my Docker::Container

  def command_options
    @options = { pull: false, all: false, edition: 'unstable', kill: false }
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
              '[user,testing,unstable]') do |v|
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

    edition_options = ['user', 'testing', 'unstable']
    unless edition_options.include?(@options[:edition])
      puts "Unknown edition. Valid editions are: #{edition_options}"
      exit 1
    end
    @options
  end

  def validate_docker
    Docker.version
  rescue
    puts 'Could not connect to Docker, check it is installed, running and ' \
         'your user is in the right group for access'
    exit 1
  end

  # Has the image already been downloaded to the local Docker?
  def docker_has_image?
    !Docker::Image.all.find do |image|
      next false if image.info['RepoTags'].nil?
      image.info['RepoTags'].include?(@tag)
    end.nil?
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
    Executable.new(command).find
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
    Process.kill('KILL', xephyr.pid)
  end

  # If this image already has a container then use that, else start a new one
  def container
    return @container if defined? @container
    # find devices to bind for Wayland
    devices = Dir['/dev/dri/*'] + Dir['/dev/video*']
    devices_list = []
    devices.each do |dri|
      devices_list.push('PathOnHost' => dri,
                        'PathInContainer' => dri,
                        'CgroupPermissions' => 'mrw')
    end
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
                                            'Env' => ['DISPLAY=:0'],
                                            'Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'],
                                            'Devices' => devices_list,
                                            'Privileged' => true)
    elsif @options[:wayland]
      @container = Docker::Container.create('Image' => @tag,
                                            'Env' => ['DISPLAY=:0'],
                                            'Cmd' => ['startplasma-wayland'],
                                            'Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'],
                                            'Devices' => devices_list,
                                            'Privileged' => true)
    else
      @container = Docker::Container.create('Image' => @tag,
                                            'Env' => ["DISPLAY=:#{xdisplay}"],
                                            'Binds' => ['/tmp/.X11-unix:/tmp/.X11-unix'],
                                            'Devices' => devices_list,
                                            'Privileged' => true)
    end
    @container
  end

  # runs the container and wait until Plasma or whatever has stopped running
  def run_container

    container.start()
    loop do
      container.refresh! if container.respond_to? :refresh!
      status = container.info.fetch('State', [])['Status']
      status ||= container.json.fetch('State').fetch('Status')
      break if not status == 'running'
      sleep 1
    end
    container.delete if !@options[:keep_alive] || @options[:reattach]
  end
end

# Jiggles dependencies into place.

# Install deb dependencies.
class DebDependencies
  def run
    pkgs_to_install = []
    pkgs_to_install << 'docker.io' unless File.exist?('/var/run/docker.sock')
    pkgs_to_install << 'xserver-xephyr' unless Executable.new('Xephyr').find

    return if pkgs_to_install.empty?

    warn 'Some packages need installing to use neondocker...'
    system('pkcon', 'install', *pkgs_to_install) || raise
  end
end

# Install !core gem dependencies and re-execs.
class GemDependencies
  def run
    require 'docker'
  rescue LoadError
    if ENV['NEONDOCKER_REEXC']
      abort 'E: Installing ruby dependencies failed -> bugs.kde.org'
    end
    warn 'Some ruby dependencies need installing to use neondocker...'
    system('pkexec', 'gem', 'install', '--no-document', 'docker-api')
    ENV['NEONDOCKER_REEXC'] = '1'
    puts '...reexecuting...'
    exec(__FILE__, *ARGV)
  end
end

# Switchs group through re-exec.
class GroupDependencies
  DOCKER_GROUP = 'docker'.freeze

  def run
    return if Process.uid.zero? # root always has access
    return if Process.groups.include?(docker_gid)

    unless user_in_group?
      adduser? || raise # adduser? actually aborts, the raise is just sugar
      system('pkexec', 'adduser', Etc.getlogin, DOCKER_GROUP) || raise
    end

    puts '...reexecuting with docker access...'
    exec('sg', DOCKER_GROUP, '-c', __FILE__, *ARGV)
  end

  private

  def user_in_group?
    member = false
    Etc.group do |group|
      member = group.mem.include?(Etc.getlogin) if group.name == DOCKER_GROUP
    end
    member
  end

  def adduser?
    loop do
      puts <<~QUESTION
        You currently do not have access to the docker socket. Do you want to
        give this user access? [Y/n]
      QUESTION

      input = gets.strip
      if input.casecmp('n').zero?
        abort <<~MSG
          Without socket access you need to use pkexec or sudo to run neondocker
        MSG
      end

      return true if input.casecmp('y').zero?
    end
    false
  end

  def docker_gid
    @docker_gid ||= begin
      gid = nil
      Etc.group do |group|
        gid = group.gid if group.name == DOCKER_GROUP
      end
      gid
    end
  end
end

# Jiggles dependencies into place.
class DependencyJiggler
  def run
    DebDependencies.new.run
    GemDependencies.new.run
    GroupDependencies.new.run
  end
end

# Parses Linux os-release files.
#
# Variables from os-release are accessible through constants.
#
# @example Put os-release 'ID' of current system
#   puts OSRelease::ID
#
# @note When running on potential !Linux or legacy systems you'll need to check
#   {#available?} before accessing constants, otherwise you may encounter
#   {NotFoundError} exceptions.
#
# @see https://www.freedesktop.org/software/systemd/man/os-release.html
module OSRelease
  # Raised when no default os-release file could be found.
  class NotFoundError < StandardError; end

  class << self
    # @return [Boolean] true when an os-release file was found in default
    #   locations as per the os-release specification
    def available?
      default_path
      true
    rescue NotFoundError
      false
    end

    # @param key [Symbol] variable name in the os-release file
    # @return [Boolean] true when the variable key is defined in the os-release
    #   data
    def variable?(key)
      data.key?(key)
    end

    # Behaves exactly like {Hash#fetch}.
    #
    # @return value of variable (if it is defined see {#variable?})
    def value(key, default = nil, &block)
      data.fetch(key, default, &block)
    end

    # @api private
    def load!(path = default_path)
      @data = default_data.dup
      File.read(path).split("\n").each do |line|
        # Split by comment to also drop leading and trailing comments. Then
        # strip to possibly reduce to an empty line.
        # Note that trailing comments are technically not defined by the spec.
        line = line.split('#', 2)[0].strip
        next if line.empty?

        key, value = parse(line)
        @data[key.to_sym] = value
      end
      @data
    end

    # @api private
    def reset!
      @data = nil
    end

    # @api private
    def const_missing(name)
      return value(name) if variable?(name)

      super
    end

    private

    STRINGLISTS = %w[ID_LIKE].freeze

    def parse(line)
      key, value = line.split('=', 2)
      return parse_list(key, value) if STRINGLISTS.include?(key)

      parse_string(key, value)
    end

    def parse_list(key, value)
      # If the value is quoted split twice. This is effectively the same
      # as dropping the quotes. ID_LIKE derives from ID and is therefore
      # super restricted in what it may contain so that a double split has
      # no adverse affects.
      value = Shellwords.split(value)[0] if value.start_with?('"')
      [key, Shellwords.split(value)]
    end

    def parse_string(key, value)
      value = Shellwords.split(value)
      [key, value[0]]
    end

    def data
      @data ||= load!
    end

    def default_data
      # Spec defines some variables with a default value.
      {
        ID: 'linux',
        NAME: 'Linux',
        PRETTY_NAME: 'Linux'
      }
    end

    def default_path
      paths = %w[/etc/os-release /usr/lib/os-release]
      path = paths.find { |x| File.exist?(x) }
      return path if path

      raise NotFoundError,
            "Could not find os-release file in default locations: #{paths}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if OSRelease.available? && (OSRelease::ID == 'ubuntu' ||
                             (defined? OSRelease::ID_LIKE && OSRelease::ID_LIKE.include?('ubuntu')))
    DependencyJiggler.new.run
  end

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
