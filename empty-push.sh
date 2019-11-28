#!/bin/bash

# Docker hub removed their trigger API so here's a simple script I run on my own server to push an empty commit
# which will trigger a build of all the images
# Jonathan Riddell 2019-11-28
# May be freely copied under the GNU GPL version 3 or later

set -xe

REPOS='docker-neon docker-neon-all'

BRANCHES='Neon/release-lts Neon/release Neon/stable Neon/unstable Neon/unstable-development master'

cd /home/jr/src/docker-neon

for repo in $REPOS; do
  cd $repo
  for branch in $BRANCHES; do
    git checkout ${branch}
    git commit --allow-empty -m 'empty push for hub.docker trigger'
    git push
  done
  cd -
done
