# Overview

The Metadabus was created to automate management of data that was being loaded into [Solr](https://solr.apache.org/) for the Canadiana Access Platform (CAP). The metadata is based on a schema called the Canadiana Metadata Repository (CMR) record. 

The metadata bus is a series of data processing scripts and tools which allow metadata to flow between stages from when an artifact is first acquired by Canadiana all the way to when it is viewable on the platform. 
The output of the Metadata Bus processes are derivatives of the source data collected during the preservation and archive processes, which are formatted in such a way that allow for easy public consumption.  
Changes or new additions to the source data are queued, processed and updated across public platforms. 


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

todo


## DMD:
todo


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
todo

## DMD Task:
todo

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


 
