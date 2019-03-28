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

require 'test/unit'
require_relative 'neondocker'
require 'timeout'

class ExecutableTest < Test::Unit::TestCase
  def setup
    ENV['PATH'] = Dir.pwd
  end

  def make_exe(name)
    File.write(name, '')
    File.chmod(0o700, name)
  end

  def test_exec_not_windows
    # If env looks windowsy, skip this test. It won't pass because we look
    # for gpg2.exe which obviously won't exist.
    return if ENV['PATHEXT']
    make_exe('gpg2')
    assert_equal "#{Dir.pwd}/gpg2", Executable.new('gpg2').find
    assert_nil Executable.new('foobar').find
  end

  def test_windows
    # windows
    ENV['RELEASEME_FORCE_WINDOWS']
    make_exe('gpg2.exe')
    make_exe('svn.com')

    ENV['PATHEXT'] = '.COM;.EXE'.downcase # downcase so this passes on Linux
    ENV['PATH'] = Dir.pwd

    assert_equal "#{Dir.pwd}/gpg2.exe", Executable.new('gpg2').find
    assert_equal "#{Dir.pwd}/svn.com", Executable.new('svn').find
    assert_nil Executable.new('foobar').find
  end
end

class NeonDockerTest < Test::Unit::TestCase
  def setup
    @neon_docker = NeonDocker.new
  end

  def test_full_session
    Timeout.timeout(2) do
      system('./neondocker.rb')
    end
    system('killall Xephyr')
  rescue Timeout::Error
    omit('timeout')
  end

  def test_standalone_session
    Timeout.timeout(2) do
      system('./neondocker.rb okular')
    end
  rescue Timeout::Error
    omit('timeout')
  end

  def test_unknown_edition
    exit_status = system('./neondocker.rb', '--edition', 'foo')
    refute(exit_status)
  end

  def test_tag_name
    @neon_docker.options = {pull: false, all: false, edition: 'user', kill: false }
    assert_equal('kdeneon/plasma:user', @neon_docker.docker_image_tag)
  end

  def test_run_xephyr
    @neon_docker.running_xephyr do
      puts 'running'
    end
  end

  def test_docker_has_image
    @neon_docker.tag = 'kdeneon/plasma:user'
    assert(@neon_docker.docker_has_image?)
    @neon_docker.tag = 'foo'
    refute(@neon_docker.docker_has_image?)
  end

  def test_container
    @neon_docker.options = {pull: false, all: false, edition: 'user', kill: false }
    @neon_docker.tag = 'kdeneon/plasma:user'
    assert(@neon_docker.container.is_a?(Docker::Container))
    @neon_docker.container = nil
    @neon_docker.tag = 'moo'
    assert_nil(@neon_docker.container)
  end

  def test_xdisplay
    assert_equal(1, @neon_docker.xdisplay)
  end
end
