# neondocker command

A wee command to simplify running KDE neon Docker images.

KDE neon Docker images are the fastest and easiest way to test out KDE's software.  You can use them on top of any Linux distro.

## Pre-requisites

Install Docker and ensure you add yourself into the necessary group.
Also install Xephyr which is the X-server-within-a-window to run
Plasma.  With Ubuntu this is:

```apt install docker.io xserver-xephyr
usermod -G docker
newgrp docker
```

## Run

To run a full Plasma session of Neon Developer Unstable Edition:
`neondocker`

To run a full Plasma session of Neon User Edition:
`neondocker --edition user`

For more options see
`neondocker --help`
