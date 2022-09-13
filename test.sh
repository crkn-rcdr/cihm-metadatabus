#!/bin/sh

cd CIHM-Meta/
perl Makefile.PL
make 
make test 
make install

cd ..
docker-compose build
docker-compose run cihm-metadatabus $1