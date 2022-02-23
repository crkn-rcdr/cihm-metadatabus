# CIHM::Meta module history

## Short version

The git log suggests this code was created on November 22, 2017, and that it was created by Russell McOrmond.

This was the date that code was refactored while it was in our Subversion repository, and included many 'svn mv' commands from across our repository to land in CIHM-META/trunk .

When we tried to use `git svn` to move to Git to publish on Github, we lost the history prior to moving into the new project. We tried many different ways to extract the history, including a perl script to filter the output of `svnadmin dump` , but the problem turned out to be too messy.  We decided to leave that history in the Subversion repository, and create this note to reference the issue.

As of January 12, 2018 when the internal http://svn.c7a.ca/svn/c7a/ repository is at revision 6786

This repository was created using:

`git svn clone file:///data/svn/c7a -T CIHM-Meta/trunk --authors-file=/home/git/authors.txt --no-metadata -s CIHM-Meta`

## Longer version

Work on the design for what we call the Metadata Bus was started by Julienne Pascoe (Metadata Architect) in June 2015.

Code was commit to Subversion in January 2016, starting with CIHM::Meta::Hammer . 

While much of the design work was being done by Julienne, much of the Perl coding work was being done by Russell McOrmond (Lead Systems Engineer).  The exception was Eqod related tools which Julienne authored in order to process some data we received from a project where we hired EQOD to do some data entry.

The first release of the metadata bus was completed in May 2016, which allowed us to process all the METS records in our repository with `hammer`, use `press` to process internal metadata (mix data from `hammer` and other sources) into 'cosearch' and 'copresentation' CouchDB databases, and to use `solrstream` to stream data from CouchDB to Solr.
