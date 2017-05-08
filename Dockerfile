FROM kdeneon/plasma:dev-unstable
MAINTAINER Jonathan Riddell <jr@jriddell.org>
USER root
RUN apt-get update && \
    apt-get install -y kdesdk-devenv-dependencies
ENV DISPLAY=:1
ENV KDE_FULL_SESSION=true

ENV XDG_RUNTIME_DIR=/run/neon
USER neon
WORKDIR /home/neon
CMD startkde
