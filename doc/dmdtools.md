# Descriptive Metadata tools


Some tools have been created to help with data migration and cleanup.

The output of these tools is stored on a CIFS server on the CRKN LAN.

`\\crkn-nas\wip\_Metadata_Synchronized\`


Source Code: [CIHM-Meta/bin](../CIHM-Meta/bin)

## dmdsync

Synchronizes data from the Preservation repository (METS records) and stores in `_Metadata_Synchronized/preservation` , 
and from the Access repository (XML files stored in Swift) and stores in `_Metadata_Synchronized/access`.

Files are separated into various directories based on their identifier (AIP ID or Slug), and then each XML file had a 
`-MARC.xml` , `-DC.xml` or `-issueinfo.xml` suffix depending on the type of XML.

## dmdstats

Offers some basic statistics of the type of metadata in each of the above directories.

* `_Metadata_Synchronised/analysis/dmdstats.csv` - table with counts of each type of metadata
* `_Metadata_Synchronised/analysis/dmdstats-IDlists/` - set of lists of the identifiers of each type
* `_Metadata_Synchronised/dmdZIP/` - set of zip files of the XML files of each type
* `_Metadata_Synchronised/dmdZIP-backup/` - Periodic (manual) backups of the dmdZIP files to allow comparisons

# Future MARC cleanup


## dmdstats-MARC856-URIcount

Creates a file `_Metadata_Synchronised/analysis/dmdstats-MARC856-URIcount.csv`. For each of the prefix directories, creates a count of files which have
a specific count of $u values. Useful to detect places to look for very large counts of $u which might be redundant/incorrect/etc.

## dmdstats-MARC856u-list

Creates a series of .csv files in `_Metadata_Synchronised/analysis/MARC856ulists/` that are based on the prefix as well as the domain in an 856$u , used to
help update any records that have unexpected values.

## dmdstats-MARCfields-list

Creates a series of .csv files in `_Metadata_Synchronised/analysis/MARCfieldslist/` that are based on the prefix as well as MARC field ID's which show the values in those fields.
Useful to get a broad overview of what fields are currently being encoded, whether or not those fields (and relevant subfields) are used in the current
crosswalks. If we change the crosswalks, or adopt new software, we will need to take a closer look at how existing records are encoded.

## dmdstats-access-MARC245

Creates a series of .csv files in `_Metadata_Synchronised/analysis/MARC245lists/` that are based on the prefix that show what metadata loader would
use for the "label" field if we expanded to using "abc" rather than only $a.

See [issue #73](https://github.com/crkn-rcdr/cihm-metadatabus/issues/73)

## dmdstats-access-MARC533

Creates a series of .csv files in `_Metadata_Synchronised/analysis/MARC533lists/`.

See [issue 68](https://github.com/crkn-rcdr/cihm-metadatabus/issues/68)


# Experimental

## dmd-Preservation-DCmultidate

Creates a series of .csv files in `_Metadata_Synchronised/Fixed/dcDateRanges` which are encoded in the format we use for loading Dublin Core with the metadata loader. Was used to load metadata in order to initiate metadata updates to clean up the custom way dates were encoded.

See [Digital-Preservation/issues/31](https://github.com/crkn-rcdr/Digital-Preservation/issues/31)

This is part of the Archivematica adoption project

## dmd-Preservation-IssueInfoDC

Creates a series of .csv files in `_Metadata_Synchronised/Fixed/IssueinfoDC` which are encoded in the format we use for loading
Dublin Core with the metadata loader.

See [Digital-Preservation/issues/32](https://github.com/crkn-rcdr/Digital-Preservation/issues/32).

This is part of the Archivematica adoption project.


## dmd-Preservation-MARCDC

Creates a series of .csv files in `_Metadata_Synchronised/Fixed/MARCDC` which are encoded in the format we use for loading
Dublin Core with the metadata loader.

See [Digital-Preservation/issues/33](https://github.com/crkn-rcdr/Digital-Preservation/issues/33).

This is part of the Archivematica adoption project.
