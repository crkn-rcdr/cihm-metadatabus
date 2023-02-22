FROM perl:5.36.0-bullseye


RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr

WORKDIR /home/tdr
COPY --chown=tdr:tdr . /home/tdr


RUN mkdir -p /home/tdr/lib/CIHM/Meta/dmd && mv /home/tdr/*.pm /home/tdr/lib/CIHM/Meta/dmd && \
    cpanm -n --installdeps . && perl Makefile.PL && make test

ENV PERL5LIB /home/tdr/lib
USER tdr
SHELL ["/bin/bash", "-c"]
