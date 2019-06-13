FROM ubuntu:trusty-20190515

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
  mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus build-essential libxml-libxml-perl libxml-libxslt-perl libio-aio-perl rsync cron postfix && apt-get clean

ENV TINI_VERSION 0.16.1
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends wget; \
    rm -rf /var/lib/apt/lists/*; \
    \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    \
# install tini
    wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch"; \
    wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7; \
    gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
    rm -r "$GNUPGHOME" /usr/local/bin/tini.asc; \
    chmod +x /usr/local/bin/tini; \
    tini --version; \
    \
    apt-get purge -y --auto-remove wget ; apt-get clean

WORKDIR /home/tdr
COPY cpanfile* *.conf /home/tdr/
COPY aliases /etc/aliases

ENV PERL_CPANM_OPT "--mirror http://pinto.c7a.ca/stacks/c7a-perl-devel/ --mirror http://www.cpan.org/"
RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)

#COPY dist/CIHM-Meta-0.17.tar.gz .
#RUN cpanm CIHM-Meta-0.17.tar.gz

COPY docker-entrypoint.sh /
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
USER root
