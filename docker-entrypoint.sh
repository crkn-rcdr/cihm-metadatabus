#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -e

export PERL5LIB=/home/tdr/CIHM-TDR/lib:/home/tdr/CIHM-Meta/lib:/home/tdr/CIHM-METS-parse/lib:/home/tdr/CIHM-Normalise/lib:/home/tdr/CIHM-Swift/lib
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/tdr/CIHM-TDR/bin:/home/tdr/CIHM-Meta/bin:/home/tdr/CIHM-METS-parse/bin:/home/tdr/CIHM-Swift/bin


# This seems to be owned by wrong user from time to time.
mkdir -p /var/lock/tdr/
chown tdr.tdr /var/lock/tdr/
mkdir -p /var/log/tdr/
chown tdr.tdr /var/log/tdr/

cronandmail ()
{
	# Postfix setup
	# needs to be in running container so local randomly generated hostname can be in main.cf
	debconf-set-selections /home/tdr/postfix-debconf.conf
	rm /etc/postfix/*.cf
        dpkg-reconfigure -f noninteractive postfix
	service postfix start

	# Cron in foreground	
	/usr/sbin/cron -f
}

echo "export PATH=$PATH" >> /root/.profile
echo "export PERL5LIB=$PERL5LIB" >> /root/.profile

echo "export PATH=$PATH" >> /home/tdr/.profile
echo "export PERL5LIB=$PERL5LIB" >> /home/tdr/.profile
chown tdr.tdr /home/tdr/.profile


# The administrator for the metadata bus -- may change to developers later.
echo "MAILTO=rmcormond@crkn.ca" > /etc/cron.d/metadatabus
echo "PATH=$PATH" >> /etc/cron.d/metadatabus
echo "PERL5LIB=$PERL5LIB" >> /etc/cron.d/metadatabus


if [ "$1" = 'solrstream' ]; then
    echo "0-59/10 * * * * tdr /bin/bash -c \"solrstream --limit=$STREAMLIMIT --localdocument=$STREAMLOCALDOCUMENT\"" >> /etc/cron.d/metadatabus
    cronandmail
elif [ "$1" = 'fullbus' ]; then
    echo "0-59/10 * * * * tdr /bin/bash -c \"reposync --since=6hours ; smelter --maxprocs=2 --timelimit=14400 ; hammer --maxprocs=2 --timelimit=14400 ; press ; hammer2 --maxprocs=10 --timelimit=14400 ; press --conf=/home/tdr/press2.conf \"" >> /etc/cron.d/metadatabus
    cronandmail
else
    # Otherwise run what was asked as the 'tdr' user
    exec sudo -u tdr -i "$@"
fi
