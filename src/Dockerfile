FROM ubuntu:noble

RUN apt update
RUN apt -y install squashfuse squashfs-tools xorriso fakeroot curl gpg wget fdisk sudo
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys
RUN apt -y autoremove
RUN apt -y clean
RUN rm -rf /var/lib/apt/lists/*
RUN mkdir /root/.gnupg
RUN chmod 600 /root/.gnupg

COPY generate-iso.sh /app/

VOLUME /data
WORKDIR /data

ENTRYPOINT [ "/app/generate-iso.sh" ]
