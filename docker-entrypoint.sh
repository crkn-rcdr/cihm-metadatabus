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



echo "MAILTO=rmcormond@crkn.ca" > /etc/cron.d/metadatabus
echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/cron.d/metadatabus


if [ "$1" = 'solrstream' ]; then
	echo "0-59/10 * * * * tdr /bin/bash -c \"solrstream --limit=$STREAMLIMIT --localdocument=$STREAMLOCALDOCUMENT\"" >> /etc/cron.d/metadatabus
        cronandmail
elif [ "$1" = 'fullbus' ]; then
	echo "0-59/10 * * * * tdr /bin/bash -c \"reposync --since=48hours ; hammer --maxprocs=2 --timelimit=14400 ; press\"" >> /etc/cron.d/metadatabus
	cronandmail
else
	# Otherwise run what was asked as the 'tdr' user
	exec sudo -u tdr "$@"
fi
