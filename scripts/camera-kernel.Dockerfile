FROM node@sha256:3d27e5c11e5786e309ec3e03f93ae536eb36e6e5eb3714d5eb3300a36157add0
RUN printf '' > /etc/apt/sources.list.d/debian.sources && \
    printf 'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20261031T000000Z bookworm main\n' > /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bc bison flex libelf-dev libssl-dev
