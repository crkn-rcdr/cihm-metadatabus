FROM perl:5.36.0-bullseye


RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr

WORKDIR /home/tdr
COPY --chown=tdr:tdr . /home/tdr


RUN cpanm -n --installdeps . && perl Makefile.PL

ENV PERL5LIB /home/tdr/lib
USER tdr
SHELL ["/bin/bash", "-c"]
