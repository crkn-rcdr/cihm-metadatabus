FROM ubuntu:trusty-20170817

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
    mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr /var/lock/tdr && \
    apt-get update && apt-get install -y cpanminus build-essential libxml-libxml-perl libxml-libxslt-perl rsync && apt-get clean

WORKDIR /home/tdr
COPY cpanfile* *.conf /home/tdr/
ENV PERL_CPANM_OPT "--mirror http://feta.office.c7a.ca/stacks/c7a-perl-devel/ --mirror http://www.cpan.org/"
RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || (cat /root/.cpanm/work/*/build.log && exit 1)

USER tdr
