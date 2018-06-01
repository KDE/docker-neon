FROM ubuntu:18.04
MAINTAINER Jonathan Riddell <jr@jriddell.org>
ADD public.key /
ADD bash-prompt /
RUN apt-get update && \
    apt-get install -y gnupg2
ADD neon.list /etc/apt/sources.list.d/
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    echo keyboard-configuration keyboard-configuration/layout select 'English (US)' | debconf-set-selections && \
    echo keyboard-configuration keyboard-configuration/layoutcode select 'us' | debconf-set-selections && \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections && \
    apt-key add /public.key && \
    rm /public.key && \
    apt-get update && \
    apt-get install -y ubuntu-minimal ubuntu-standard neon-desktop plasma-workspace-wayland kwin-wayland kwin-wayland-backend-x11 kwin-wayland-backend-wayland kwin && \
    apt-get dist-upgrade -y && \
    groupadd admin && \
    useradd -G admin,video -ms /bin/bash neon && \
    # Refresh apt cache once more now that appstream is installed \
    rm -r /var/lib/apt/lists/* && \
    apt-get update && \
    # Blank password \
    echo 'neon:U6aMy0wojraho' | chpasswd -e && \
    echo 'neon ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    apt-get clean && \
    cp /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit /root/ && \
    rm /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit && \
    cp /root/start_kdeinit /usr/lib/x86_64-linux-gnu/libexec/kf5/start_kdeinit && \
    # Wayland bits \
    mkdir /run/neon && \
    chown neon:neon /run/neon && \
    export PS1=`cat /bash-prompt`
ENV DISPLAY=:1
ENV KDE_FULL_SESSION=true
ENV SHELL=/bin/bash

ENV XDG_RUNTIME_DIR=/run/neon
USER neon
COPY gitconfig $HOME/.gitconfig
WORKDIR /home/neon
CMD startkde
