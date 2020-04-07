FROM perl:5.30.2

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
  mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus build-essential libxslt1-dev libxml2-dev libaio-dev libssl-dev rsync cron postfix sudo less nodejs yarnpkg && apt-get clean

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
COPY aliases docker-entrypoint.sh cpanfile* *.conf /home/tdr/
RUN mv aliases /etc/alises && mv docker-entrypoint.sh /

RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)


COPY CIHM-Normalise CIHM-Normalise
COPY CIHM-TDR CIHM-TDR
COPY CIHM-Meta CIHM-Meta
COPY CIHM-METS-parse CIHM-METS-parse
COPY CIHM-Swift CIHM-Swift
COPY Access-Platform/Databases Databases

# Used for schema validation
RUN cd Databases ; yarnpkg install

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
USER root
