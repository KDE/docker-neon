FROM ubuntu:16.04
MAINTAINER Jonathan Riddell <jr@jriddell.org>
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN echo keyboard-configuration keyboard-configuration/layout select 'English (US)' | debconf-set-selections;
RUN echo keyboard-configuration keyboard-configuration/layoutcode select 'us' | debconf-set-selections;
RUN apt-get update && apt-get install -y wget less nano sudo psmisc
RUN wget https://archive.neon.kde.org/public.key
RUN apt-key add public.key
RUN rm public.key
ADD neon.list /etc/apt/sources.list.d/
RUN apt-get update
RUN apt-get install -y neon-desktop plasma-workspace-wayland kwin-wayland kwin-wayland-backend-x11 kwin-wayland-backend-wayland
RUN apt-get dist-upgrade -y
ENV DISPLAY=:1
ENV KDE_FULL_SESSION=true
ENV PS1='\[\e[34m\]\udocker@user$(__git_ps1)>'
RUN groupadd admin
RUN groupadd video
RUN useradd -G admin,video -ms /bin/bash neon

# No password needed
RUN echo 'neon:U6aMy0wojraho' | chpasswd -e
RUN echo 'neon ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Wayland bits
RUN mkdir /run/neon
RUN chown neon:neon /run/neon
ENV XDG_RUNTIME_DIR=/run/neon
USER neon
WORKDIR /home/neon
CMD startkde
