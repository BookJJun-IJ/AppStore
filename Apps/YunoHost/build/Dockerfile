FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and clean up unnecessary units for Docker
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        curl \
        ca-certificates \
        gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Remove unnecessary systemd services for Docker
    rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
          /lib/systemd/system/systemd-update-utmp*

# Install YunoHost (non-interactive, stable branch)
RUN curl -sSL https://install.yunohost.org/bookworm | bash -s -- -a -d stable

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/sys/fs/cgroup", "/etc/yunohost", "/home/yunohost.backup", "/home/yunohost.app", "/var/mail"]

EXPOSE 80 443

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
