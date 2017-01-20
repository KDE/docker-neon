FROM ubuntu:16.04
MAINTAINER Jonathan Riddell <jr@jriddell.org>
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN echo keyboard-configuration keyboard-configuration/layout select 'English (US)' | debconf-set-selections;
RUN echo keyboard-configuration keyboard-configuration/layoutcode select 'us' | debconf-set-selections;
RUN apt-get update && apt-get install -y wget less nano sudo psmisc
RUN wget https://archive.neon.kde.org/public.key
RUN apt-key add public.key
ADD neon.list /etc/apt/sources.list.d/
RUN apt-get update
RUN apt-get install -y neon-desktop
RUN apt-get dist-upgrade -y
ENV DISPLAY=:1
ENV KDE_FULL_SESSION=true
RUN groupadd admin
RUN useradd -G admin -ms /bin/bash neon
RUN echo 'neon:U6aMy0wojraho' | chpasswd -e
RUN echo 'neon ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER neon
WORKDIR /home/neon
CMD startkde
