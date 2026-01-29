FROM perl:5.36.0-bullseye

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
  mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
  ln -sf /usr/share/zoneinfo/America/Montreal /etc/localtime && \
  ln -sf /usr/include/x86_64-linux-gnu/ImageMagick-6/ /usr/local/include/ && \
  \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus build-essential libxml-libxml-perl libxml-libxslt-perl libxslt1-dev \
  libxml2-dev libxml2-utils xml-core libaio-dev libssl-dev rsync sudo less lsb-release \
  poppler-utils libpoppler-dev libpoppler-glib-dev libgirepository1.0-dev python3-swiftclient \
  imagemagick-6-common libmagickcore-6.q16-6 default-jre && \
  \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq ca-certificates curl gnupg && \
  mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq nodejs && \
  \
  apt-get clean

# Upgrades to Imagemagik now have a policy file which needs to be adjusted.
# https://stackoverflow.com/questions/42928765/convertnot-authorized-aaaa-error-constitute-c-readimage-453
# We've also had memory issues.
# https://stackoverflow.com/questions/31407010/cache-resources-exhausted-imagemagick
RUN echo "\n<policy domain=\" coder\" rights=\"read|write\" pattern=\"PDF\" />\n<policy domain=\"coder\" rights=\"read|write\" pattern=\"LABEL\" \/>/" >>/etc/ImageMagick-6/policy.xml && \
  sed -i -E 's/name="memory" value=".+"/name="memory" value="8GiB"/g' /etc/ImageMagick-6/policy.xml && \
  sed -i -E 's/name="map" value=".+"/name="map" value="8GiB"/g' /etc/ImageMagick-6/policy.xml && \
  sed -i -E 's/name="area" value=".+"/name="area" value="8GiB"/g' /etc/ImageMagick-6/policy.xml && \
  sed -i -E 's/name="disk" value=".+"/name="disk" value="8GiB"/g' /etc/ImageMagick-6/policy.xml


# Cache some xsd's for validation
# Clone the repo: https://github.com/crkn-rcdr/Digital-Preservation
# Copy the contents or the xml dir into your /home/tdr/xml directory, ex: sudo cp -r /home/brittny/Digital-Preservation/xml /home/tdr/xml

RUN xmlcatalog --noout --add uri http://www.loc.gov/standards/xlink/xlink.xsd file:///home/tdr/xml/unpublished/xsd/xlink.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.loc.gov/alto/v3/alto-3-0.xsd file:///home/tdr/xml/unpublished/xsd/alto-3-0.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.loc.gov/alto/v3/alto-3-1.xsd file:///home/tdr/xml/unpublished/xsd/alto-3-1.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.loc.gov/alto/v4/alto-4-2.xsd file:///home/tdr/xml/unpublished/xsd/alto-4-2.xsd /etc/xml/catalog && \
  xmlcatalog --noout --add uri http://www.w3.org/2001/03/xml.xsd file:///home/tdr/xml/unpublished/xsd/xml.xsd /etc/xml/catalog

# https://pdfbox.apache.org/download.html
# This number will need to be updated every so often
ENV PDFBOXAPPVER=2.0.33
RUN wget -nv \
  "https://archive.apache.org/dist/pdfbox/$PDFBOXAPPVER/pdfbox-app-$PDFBOXAPPVER.jar" \
  "https://archive.apache.org/dist/pdfbox/$PDFBOXAPPVER/pdfbox-app-$PDFBOXAPPVER.jar.asc" \
  && wget -nv -O pdfbox_KEYS "https://archive.apache.org/dist/pdfbox/KEYS" \
  && gpg --batch --import pdfbox_KEYS \
  && gpg --batch --verify "pdfbox-app-$PDFBOXAPPVER.jar.asc" "pdfbox-app-$PDFBOXAPPVER.jar"



WORKDIR /home/tdr
COPY cpanfile* *.conf *.tar.gz /home/tdr/
COPY aliases /etc/aliases

# https://metacpan.org/dist/AnyEvent-Fork-Pool -- file not found.
# Built dist to manually install via http://software.schmorp.de/pkg/AnyEvent-Fork-Pool.html 
# Specifically the "Download GNU tarball" from http://cvs.schmorp.de/AnyEvent-Fork-Pool/
#RUN cpanm -n --reinstall /home/tdr/AnyEvent-Fork-Pool-1.3.tar.gz && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)
RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)

COPY CIHM-Normalise CIHM-Normalise
COPY CIHM-Meta CIHM-Meta
COPY CIHM-Swift CIHM-Swift
COPY data data
COPY xml xml

ENV PERL5LIB /home/tdr/CIHM-Meta/lib:/home/tdr/CIHM-Normalise/lib:/home/tdr/CIHM-Swift/lib
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/tdr/CIHM-Meta/bin:/home/tdr/CIHM-Swift/bin

SHELL ["/bin/bash", "-c"]
USER tdr
