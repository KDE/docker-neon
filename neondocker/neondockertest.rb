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

require 'test/unit'
require_relative 'neondocker'

class NeonDockerTest < Test::Unit::TestCase
    def setup
        puts "setup"
    end
    
    def test_unknown_edition
        exitStatus = system('./neondocker.rb', '--edition', 'foo')
        assert(exitStatus == false, 'Should be false')
    end
   
    def test_tag_name
        options = {pull: false, all: false, edition: 'user', kill: false }
        assert(docker_image_tag(options) == "kdeneon/plasma:user")
    end
    
    def test_run_xephyr
        #assert(run_xephyr == true)
        running_xephyr(1) do 
            puts 'running'
        end
    end
        
    def test_docker_has_image
        assert(docker_has_image?('kdeneon/plasma:user') == true)
        assert(docker_has_image?('foo') == false)
    end

    def test_get_container
        assert(get_container('kdeneon/plasma:user').kind_of?(Docker::Container))
        assert(get_container('moo') == nil)
    end
    
    def test_get_xdisplay
        assert(get_xdisplay == 1)
    end
end
