FROM ubuntu:resolute

RUN apt update \
 && apt install -y curl unzip python3

RUN curl -L -o /usr/local/bin/uuu https://github.com/nxp-imx/mfgtools/releases/download/uuu_1.5.243/uuu-ubuntu20.04
RUN chmod a+x /usr/local/bin/uuu
RUN curl -L -o /tmp/xpack.tar.gz https://github.com/xpack-dev-tools/aarch64-none-elf-gcc-xpack/releases/download/v15.2.1-1.1/xpack-aarch64-none-elf-gcc-15.2.1-1.1-linux-x64.tar.gz
RUN tar -C /opt -xzvf /tmp/xpack.tar.gz
RUN curl -L -o /tmp/platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip
RUN unzip -d /opt /tmp/platform-tools.zip
