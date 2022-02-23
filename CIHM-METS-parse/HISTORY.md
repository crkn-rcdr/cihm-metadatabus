# History

This code has a long history behind it that provides context.

## 2012 CMR and Solr

Starting in 2012, an internal [Canadiana Metadata Repository (CMR) XML format](http://www.canadiana.ca/schema/2012/xsd/cmr/cmr.xsd)  was used as a normalized storage format.  CMR records could be submit to Canadiana to be part of the national index on which the Canadiana Discovery Portal was based.  Software existed which would import CMR data into our Solr search engine, including CIHM::Solr.

While there was some data in MySQL, most data was stored within the Solr core.  Data was only updated when new data was submitted, and existing data was left in the Solr core which was used both as an index and as NoSQL storage.

 All Canadiana AIPs automatically had a CMR file gemat was used as an internal format. It was based on the metadata referenced from within our METS records which was stored in 1 of 3 possible XML formats: MARC XML, Dublin Core, and our own [issueinfo](http://www.canadiana.ca/schema/2012/xsd/issueinfo/issueinfo.xsd).
 
 Software existed which would convert our METS referenced data to CMR, including a function CIHM::TDR->build_cmr().
 
## 2016 Metadata Bus

In early 2016 we started work on what we call our Metadata Bus.  We wanted to be able to more easily upgrade individual components of our platform without impacting others, so adopted a Microservices architecture with CouchDB acting as our communications conduit (our Bus). Microservices would know they had work to do based on CouchDB views, etc.

Solr would be streamed to from CouchDB, where all data could be rebuilt from the data in the AIP.  CouchDB was used as a communications conduit between Microservices (which might run in different servers rooms in different provinces), and Solr would be as an index: neither were being used for long-term storage.

The latest versions of CIHM::Solr and CIHM::TDR->build_cmr() were built into a new microservice we called Hammer which would take data referenced from METS and post to a CouchDB database.  The output of build_cmr() was fed directly into CIHM::Solr, which would then read the Solr formatted XML to create a simple perl hash (key/value pairs, where some keys would have arrays of data).

The data stored in CouchDB would later be combined with other data with a microservice called Press that would output to a cosearch database (which would be distributed via CouchDB to the locations where Solr was running, and then data streamed to Solr) and copresentation database (Used by the front-end interface for presentation).

No data was retained from the old Solr core other than which collections each AIP was a member of. Any one-off data that was stored in Solr might still exist in the Discovery Portal demonstration site, but is no longer part of our current platform.

## 2017

Moving forward we plan to get rid of the last usage of the CMR format, which is contained within this library. We will refactor to no longer make use of xsl rules for transformation, with all the logic contained in perl.
