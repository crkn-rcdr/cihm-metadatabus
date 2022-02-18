#!/bin/sh

echo
echo "Building cihm-metadatabus-legacy:latest"

docker build -t cihm-metadatabus-legacy:latest .

if [ "$?" -ne "0" ]; then
  exit $?
fi


docker login docker.c7a.ca

if [ "$?" -ne "0" ]; then
  echo 
  echo "Error logging into the c7a Docker registry."
  exit 1
fi

TAG=`date -u +"%Y%m%d%H%M%S"`

echo
echo "Tagging cihm-metadatabus-legacy:latest as docker.c7a.ca/cihm-metadatabus-legacy:$TAG"

docker tag cihm-metadatabus-legacy:latest docker.c7a.ca/cihm-metadatabus-legacy:$TAG

if [ "$?" -ne "0" ]; then
  exit $?
fi

echo
echo "Pushing docker.c7a.ca/cihm-metadatabus-legacy:$TAG"

docker push docker.c7a.ca/cihm-metadatabus-legacy:$TAG

if [ "$?" -ne "0" ]; then
  exit $?
fi

echo
echo "Push sucessful. Create a new issue at:"
echo
echo "https://github.com/crkn-rcdr/Systems-Administration/issues/new?title=Legacy+Metadata+Bus+image:+%60docker.c7a.ca/cihm-metadatabus-legacy:$TAG%60&body=Please+describe+the+changes+in+this+update%2e"
echo
echo "to alert the systems team. Don't forget to describe what's new!"