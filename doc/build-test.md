# cihm-metadatabus

Docker build environment and libraries for key portions of the metadata bus.

The file `env-dist` has the environment variables that you would change by adding to `.env.secret` file, adding in passwords as required.


To create a local 'log' directory for testing:

```
$ mkdir log ; sudo chown 1117.1117 log
```

To run a shell inside the container, to test any command (the Dockerfile sets the correct path for the shell):

```
$ docker-compose build --pull
$ docker-compose run cihm-metadatabus bash
```

To test a specific script, for example, dmdtask, run:

```
$ docker-compose build --pull
$ docker-compose run cihm-metadatabus bash
tdr@6495e43707b5:~$ dmdtask
```


Then, in another terminal, run:
```
$ tail -f log/root.log
```

What you run in bash inside the container can be an infinite loop if you wished to run similar to how it is run in production.

```
$ docker-compose build --pull
$ docker-compose run cihm-metadatabus bash
Creating cihm-metadatabus_cihm-metadatabus_run ... done
tdr@6495e43707b5:~$ while :; do dmdtask ; sleep 1m ; done
```

A script exists for building and pushing images which should be used:

```
russell@russell-XPS-13-7390:~/git/cihm-metadatabus$ ./deployimage.sh 
```



## CIHM-Meta

Core of Metadtabus. See [HISTORY.md](../CIHM-Meta/HISTORY.md) for some of the history of the code.

Tools:

* dmdtask - handles Descriptive MetaData tasks, which process and update databases with metadata
* hammer2 - Sources data from the `access` and other databases to create the cache files that will be used by Solr search and presentation (Currently CAP).
* ocrtask - Handles OCR related tasks -- exporting Canvas images to filesystem used for OCR, and importing results (ALTO XML, PDF) into Access storage for Canvases.
* reposync - reads data from `tdrepo` database about added/replicated AIPs, and updates `wipmeta` (packaging tools) and `dipstaging` ("Import into Access" web interface to smelter)
* smelter - Microservice responsible for "Import into Access", copying data from presertavion storage (AIP files, METS data) to Access storage (manifests and canvases)
* solrstream - copies data from CouchDB `cosearch` database to Solr `cosearch` core,using the CouchDB [/db/_changes](https://docs.couchdb.org/en/latest/api/database/changes.html) interface.
* walk-canvas-orphan - Walks through canvases looking for any which are not referenced by any manifest. This is the first of a set of tools to walk databases to ensure data integrity across multiple data sources.  More will be written to check things such as whether all files in access storage are appropriately references in CouchDB documents (any missing, any extra, etc).

Most of the libraries have names which make it obvious which of the above tools they are part of. Exceptions are:

* CIHM::Meta::REST::cantaloupe  -  Cantaloupe makes use of an authentication system which injects headers. This is where this is set up
* CIHM::Meta::REST::UserAgent - This is the user agent for communicating with Cantaloupe and injecting the headers.


## CIHM-Normalise

Normalization functions.  This includes crosswalks from MARC, Issueinfo and Simple Dublin Core to CMR.

## CIHM-Swift

Separate submodule of https://github.com/crkn-rcdr/CIHM-Swift which has common functionality created for interacting with [OpenStack Swift](https://docs.openstack.org/swift/latest/). Module code includes comments pointing at the documentation for the functinality implimented.

