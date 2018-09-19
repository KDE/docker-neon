# KDE neon Docker images - Plasma

Updated daily with the latest from KDE neon, itself automatically updated with the latest KDE software.

## Running

Flavours available are: `kdeneon/plasma:dev-unstable`, `kdeneon/plasma:dev-stable`, `kdeneon/plasma:user`, `kdeneon/plasma:user-lts`

For flavours with all applications installed see `kdeneon/all`.

By default it will run a full session with startkde on DISPLAY=:1, you can use Xephyr as an X server window.

```
Xephyr -screen 1024x768 :1 &
docker run -v /tmp/.X11-unix:/tmp/.X11-unix kdeneon/plasma:dev-unstable
```

Or you can tell it to run on DISPLAY=:0 and run a single app

```
xhost +
docker run -v /tmp/.X11-unix:/tmp/.X11-unix -e DISPLAY=:0 --security-opt seccomp=unconfined kdeneon/plasma:dev-unstable dolphin
```
