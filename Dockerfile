FROM perl:5.34.1-bullseye

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
  mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
  ln -sf /usr/share/zoneinfo/America/Montreal /etc/localtime && \
  \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus build-essential libxml-libxml-perl libxml-libxslt-perl libxslt1-dev \
  libxml2-dev libxml2-utils xml-core libaio-dev libssl-dev rsync sudo less lsb-release \
  poppler-utils libpoppler-dev libpoppler-glib-dev libgirepository1.0-dev python3-swiftclient && \
  \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  VERSION=node_15.x && DISTRO="$(lsb_release -s -c)" && \
  echo "deb https://deb.nodesource.com/$VERSION $DISTRO main" > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq nodejs && \
  \
  apt-get clean

# Cache some xsd's for validation
RUN mkdir -p /opt/xml && svn co https://github.com/crkn-rcdr/Digital-Preservation.git/trunk/xml /opt/xml/current && \
  xmlcatalog --noout --add uri http://www.loc.gov/standards/xlink/xlink.xsd file:///opt/xml/current/unpublished/xsd/xlink.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.loc.gov/alto/v3/alto-3-0.xsd file:///opt/xml/current/unpublished/xsd/alto-3-0.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.loc.gov/alto/v3/alto-3-1.xsd file:///opt/xml/current/unpublished/xsd/alto-3-1.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.w3.org/2001/03/xml.xsd file:///opt/xml/current/unpublished/xsd/xml.xsd /etc/xml/catalog

WORKDIR /home/tdr
COPY cpanfile* *.conf /home/tdr/
COPY aliases /etc/aliases

RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)


COPY CIHM-Normalise CIHM-Normalise
COPY CIHM-Meta CIHM-Meta
COPY CIHM-Swift CIHM-Swift
COPY data data

ENV PERL5LIB /home/tdr/CIHM-Meta/lib:/home/tdr/CIHM-Normalise/lib:/home/tdr/CIHM-Swift/lib
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/tdr/CIHM-Meta/bin:/home/tdr/CIHM-Swift/bin

SHELL ["/bin/bash", "-c"]
USER tdr
