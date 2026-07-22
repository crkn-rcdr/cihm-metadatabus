# Overview

The Metadabus was created to automate management of data that was being loaded into [Solr](https://solr.apache.org/) for the Canadiana Access Platform (CAP). The metadata is based on a schema called the Canadiana Metadata Repository (CMR) record. 

The metadata bus is a series of data processing scripts and tools which allow metadata to flow between stages from when an artifact is first acquired by Canadiana all the way to when it is viewable on the platform. 
The output of the Metadata Bus processes are derivatives of the source data collected during the preservation and archive processes, which are formatted in such a way that allow for easy public consumption.  
Changes or new additions to the source data are queued, processed and updated across public platforms. 


# Getting Started

These steps create a local checkout with the required submodule, build the Docker image, and show how to launch metadata bus commands inside the local container.

## Clone the required repositories

The main repository includes `CIHM-Meta`, `CIHM-Normalise`, `data`, and `xml`. `CIHM-Swift` is a Git submodule, so clone recursively:

```
$ git clone --recurse-submodules git@github.com:crkn-rcdr/cihm-metadatabus.git
$ cd cihm-metadatabus
```

If you already cloned the repository without submodules, initialize them before building:

```
$ git submodule update --init --recursive
```

The Docker build uses the checked-in `xml/` directory for schema validation. If you need to refresh those schema files from their source, clone the Digital Preservation repository beside this one:

```
$ cd ..
$ git clone git@github.com:crkn-rcdr/Digital-Preservation.git
$ cd cihm-metadatabus
```

CAP and Solr are runtime/integration dependencies, but they are not required to build this local Docker image.

## Prepare local configuration

Create a local secrets file. `env-dist` contains the default variable names and non-secret examples; put private passwords or local overrides in `.env.secret`.

```
$ touch .env.secret
```

Create the local log directory with the UID/GID used by the `tdr` user in the container:

```
$ mkdir -p logs
$ sudo chown -R 1117:1117 logs
```

## Build the local Docker image

The examples below use Docker Compose v2. If your workstation uses the legacy command, replace `docker compose` with `docker-compose`.

```
$ docker compose build --pull
```

## Run commands in local Docker

Open an interactive shell in the container:

```
$ docker compose run --rm cihm-metadatabus bash
```

The Docker image sets `PATH` and `PERL5LIB`, so metadata bus commands can be launched directly from that shell:

```
tdr@container:~$ dmdtask
tdr@container:~$ hammer2
tdr@container:~$ ocrtask
tdr@container:~$ reposync
tdr@container:~$ smelter
tdr@container:~$ solrstream
```

You can also run one command without opening a shell:

```
$ docker compose run --rm cihm-metadatabus dmdtask
```

For a production-like loop during local testing, run the command from the container shell:

```
tdr@container:~$ while :; do dmdtask; sleep 1m; done
```

Logs written to `/var/log/tdr` in the container are available on the host in `logs/`:

```
$ tail -f logs/root.log
```


# Services

The Metadata Bus includes the following services: 


## Smelter:  

Reads METS records from the repository and generates canvas and manifest records. 

Manifest records have a noid for an _id and a slug which is set by Smelter 

Canvas records have a noid for an _id, and are not tied to any specific manifest.  


## Hammer2: 

Handles the processing of individual manifests 

Reads a _view in the manifest and collection documents to read data from those documents, and potentially from XML descriptive metadata files (in swift) and updates the cosearch and copresentation databases. 

 

## Solrstream: 

Streams updates that occur in the search database to individual Solr cores. Solr is an enterprise search engine platform.  

 

## Reposync: 

Keeps the dipstaging and wipmeta database up to date with the public availability of replicas of AIP content in repositories. 


## OCR:

Handles OCR export and import tasks.

For export tasks, `ocrtask` reads queued canvas lists, pulls the source image files from Access Swift storage, and writes them to the OCR work directory for processing.

For import tasks, `ocrtask` reads the completed OCR package from the work directory, validates ALTO XML, stores OCR XML and single-page OCR PDFs back into Swift, updates the associated Canvas records, and requests multi-page OCR PDF generation for affected manifests.


## DMD:

Handles Descriptive Metadata tasks created by the staff "Load Metadata" tool.

`dmdtask` splits uploaded metadata files into individual records, extracts identifiers and labels, validates the XML, and generates CMR JSON so staff can preview the crosswalked result before storage.

When records are approved for storage, `dmdtask` writes descriptive metadata XML to Access or Preservation storage, updates labels, and records per-item storage results back to the task document.


# Databases 

The above services interact with the following 'Access Databases': 
 

## Dipstaging: 

Derived Data 

Ids are AIP IDs 

Used by Smelter and reposync 

Process data from the repository to create manifests dents 

Documents are created by reposync on data in the repository 

 

## Canvas: 

Source Data 

Ids are noids 

Used to store information about individual images 

Analogous to sequences within internalmeta records 

 

## Access - Manifest: 

Source Data 

Ids are noids 

Used to store information about groups of canvases 

Analogous to internalmeta records 

 

## Access - Collection: 

Source Data 

Ids are noids 

Used  to store info about groups of manifests and/or other collections. 

Combines both the concepts of series records and the collection tags in internalmeta 

An ordered collection references it's child manifests 

Before, an issue pointed to a parent series 

 

## COSearch: 

Derived Data 

Ids are noids or slug 

Analogous to cosearch database 

Streamed to Solr 

 

## COPresentation: 

Derived Data 

Ids are noids or slug 

Analogous to copresentation database 

Read by CAP (Canadiana Access Platform) 

 
## OCR:

Task queue and status database for OCR export and import jobs.

Documents describe batches of canvases to export for OCR or import after OCR processing. The database tracks task progress, success or failure, and messages from `ocrtask`.

## DMD Task:

Task queue and status database for descriptive metadata uploads.

Documents are created by the staff metadata loader and may include the uploaded source file as a `metadata` attachment. During processing, `dmdtask` adds `dmd.json` and `flatten.json` attachments, item-level review data, processing messages, and storage progress.

# More Information

Other key documents:

* [Building, testing and deploying software](doc/build-test.md)
* [History of software stack](doc/stack.md)
* [CMR and Crosswalks to CMR](doc/cmr.md)
* [Descriptive Metadata tasks](doc/dmdtask.md) (microservice for "Load Metadata")
* [Descriptive Metadata Tools](doc/dmdtools.md)

Other relevant repositories:

* [CAP front-end](https://github.com/crkn-rcdr/cap)
* [Solr configuration](https://github.com/crkn-rcdr/solr)
* [CMR version 1.2](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) XML Schema Definition (XSD)


 
