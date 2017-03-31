#!/usr/bin/ruby

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
        running_xephyr do 
            puts 'running'
        end
    end
        
    def test_docker_has_image
        assert(docker_has_image?('kdeneon/plasma:user') == true)
        assert(docker_has_image?('foo') == false)
    end

end
