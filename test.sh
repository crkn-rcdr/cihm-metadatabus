#!/bin/sh

cd CIHM-Meta/
perl Makefile.PL
make 
make test 

cd ..
docker-compose build
docker-compose run cihm-metadatabus $1