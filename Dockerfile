FROM debian:buster-slim
RUN apt-get update \
  && LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    tzdata \
    ssl-cert \
    psmisc \
    slapd \
    ldap-utils \
    psmisc \
    procps \
    less \
    lsof \
    slapd-smbk5pwd \
    e3 \
  && ln -fs /usr/share/zoneinfo/US/Pacific-New /etc/localtime && dpkg-reconfigure -f noninteractive tzdata \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/backups/* \
  && mkdir /etc/ldap-skel \
  && cp -rv /etc/ldap/* /etc/ldap-skel/



ENV LDAP_ROOTPASS Doughnut
ENV LDAP_ORGANISATION Springfiled Nucleaon Plant
ENV LDAP_DOMAIN snpp.com
ENV LDAP_URLS ldap:///
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV SLAPD_DEBUG_LEVEL 2
EXPOSE 389

COPY addtional-schemas /addtional-schemas/
COPY dumb-init /usr/local/bin/dumb-init
COPY ./slapd.sh /

# To store config outside the container, mount /etc/ldap/slapd.d as a data volume.
# To store data outside the container, mount /var/lib/ldap as a data volume.
VOLUME /etc/ldap /var/lib/ldap

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
CMD /slapd.sh
