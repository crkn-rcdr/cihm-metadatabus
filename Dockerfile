FROM perl:5.34.0

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
  mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
  \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus build-essential libxslt1-dev \
  libxml2-dev libaio-dev libssl-dev rsync cron postfix sudo less lsb-release && \
  \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  VERSION=node_15.x && DISTRO="$(lsb_release -s -c)" && \
  echo "deb https://deb.nodesource.com/$VERSION $DISTRO main" > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq nodejs && \
  \
  apt-get clean

ENV TINI_VERSION 0.19.0
RUN set -ex; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends wget; \
  rm -rf /var/lib/apt/lists/*; \
  \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  \
  # install tini
  export GNUPGHOME="$(mktemp -d)"; \
  ( \
  gpg --batch --keyserver keyserver.ubuntu.com  --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver ipv4.pool.sks-keyservers.net  --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver ha.pool.sks-keyservers.net  --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver pool.sks-keyservers.net  --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver pgp.mit.edu              --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver keyserver.pgp.com        --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  || gpg --batch --keyserver p80.pool.sks-keyservers.net --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
  ) ; \
  wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch"; \
  wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch.asc"; \
  gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
  rm -r "$GNUPGHOME" /usr/local/bin/tini.asc; \
  chmod +x /usr/local/bin/tini; \
  tini --version; \
  \
  apt-get purge -y --auto-remove wget ; apt-get clean

WORKDIR /home/tdr
COPY cpanfile* *.conf /home/tdr/
COPY aliases /etc/aliases

RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)


COPY CIHM-Normalise CIHM-Normalise
COPY CIHM-TDR CIHM-TDR
COPY CIHM-Meta CIHM-Meta
COPY CIHM-METS-parse CIHM-METS-parse
COPY CIHM-Swift CIHM-Swift

COPY docker-entrypoint.sh /
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
USER root
