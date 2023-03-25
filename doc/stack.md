# History of Stack: CMR, Solr, CAP, Metadatabus

The Metadabus was created to automate management of data that was being loaded into Solr for CAP.


* Code for the Canadiana Access Portal (CAP) started earlier, but first commit to the Subversion repository (which was copied to Git and GitHub) was on [April 26, 2010](https://github.com/crkn-rcdr/cap/tree/6e03c7e5337fcc978465b02062708b1fffb15ae6/).
* The 1.0 version of the Canadiana Metadata Repository (CMR) data schema was [announced by William Wueppelmann on Mon, 12/20/2010](https://web.archive.org/web/20150912073813/http://www.canadiana.ca/en/content/cmr-canadiana-metadata-repository-schema) via a blog article, and made [available on the webiste](https://web.archive.org/web/20130711000227/http://www.canadiana.ca/en/cmr).
* The Canadiana Discovery Portal (CDP) and its API was presented at the second Code4Lib North (McMaster University, May 5-6, 2011)
  * http://hdl.handle.net/11375/14376   (Video [also on YouTube](https://www.youtube.com/watch?v=KD7w-1pAdxU))
* The [Beta.canadiana.ca URL](https://web.archive.org/web/20101201000000*/beta.canadiana.ca) became [Search.canadiana.ca](https://web.archive.org/web/20120201000000*/search.canadiana.ca), and a redirect was kept for many years (The word "beta" didn't have meaning outside software people, so many thought it was an official service).
* CMR [version 1.2 of the XML Schema Definition (XSD)](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) is published November 2012.
* The [schema which Solr used to store and index data](https://github.com/crkn-rcdr/solr) is CMR plus additional fields.
* At this point CMR records were created and loaded via a large series of separate normalization/crosswalk scripts, sometimes several per metadata contributor. When the structure of an AIP was created as part of new OAIS archiving, a cmr.xml file (already crosswalked from the metadata record other Canadiana staff supplied) was part of the AIP (See [AIP definition](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/txt/aip.txt) )
* It was decided we wanted to automate the loading of the Solr core, and to have the metadata crosswalks run at load time rather than earlier to allow us to enhance the crosswalks and have that apply to content previously ingested into our OAIS platform.
* As part of creating the Metadatabus, the CDP codebase and Solr core was separated from what was being used by all the other portals in the spring of 2016.
* For efficiency, documents not needed for search were split out into a separate CouchDB database:  cosearch was loaded into Solr, while copresentation was made available to CAP directly.
* The CDP didn't receive new updates for several years, and eventually in 2018 it was decided to decomission that service.
* While there have been other minor design changes, the core of CMR and CAP have remained: What is searchable via CAP, and the format that metadata is crosswalked to, remains based on CMR records loaded into a Solr database.
