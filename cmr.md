# What is CMR

The Canadiana Metadata Repository (CMR) record was created to have a single normalised record that contained simple features that other record types had in common.
The idea was that metadata from a variety of institutions would be crosswalked to this format and made searchable in the Canadiana Discovery Portal.
(See [History of software stack](stack.md)).

While some details have changed since, a good place to start is [CMR version 1.2](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) XML Schema Definition (XSD)

# Key changes

* We moved from expressing the format in XML to JSON
* We use the field names as they are expressed within the Solr schema
* There are additional fields added from sources other than a descriptive metadata crosswalk

# Simple lookup table

## Required Control fields

| CMR field | type | Required | status | Description |
------------|------|--------|----------|----
| key | slug |Y  | | | 
| noid | string(noid)  | Y | | Parent slug for issue of a series |
| type | string | Y | | One of "series", "document", "page" |
| depositor | slug | Y | lcalpha | | |
| label | string | Y | | Label currently copied from Access IIIF label |


## Optional control fields

| CMR field | type | Required | status | Description |
------------|------|--------|----------|----
| manifest_noid| string(noid} | N | | noid of manifest, used by type=page |
| pkey | string(slug) | N | | Parent slug for issue of a series (its "multi-part" collectin), or pages of a manifest |
| plabel | string| N | | Label of parent for issue of a series (lookup when building record) |
| seq | Positive Integer | N | | Ussed to sort issues of a series |
| pubmin | string | N | Current | Minimum ISO 8601 date for a publication date range. |
| pubmax | string | N | Current | Maximum ISO 8601 date for a publication date range. |
| lang | array of strings | N | Current | 3-character ISO 639-3 language code |
| identifier | array of strings | N | Current | Displayed array of identifiers |
| collection | array of strings | N | Current | array of the slugs of collections this document is part of (excluding pkey) |
| item count | positive integer | | | |
| component_count | positive integer | 
| component_count_fulltext | integer | 

## Description and content

| CMR field | type | Required | status | Description |
------------|------|--------|----------|----
| ti | text | 
| au | text |
| pu | text |
| su | text |
| no | text |
| ab | text |
| tx | text | 


## Heritage Premium metadata fields

Special data for https://heritage.canadiana.ca/
Data side-loaded from [data/tag](data/tag)


| field | type | Required | status | Description |
------------|------|--------|----------|----
| tag | array of text |
| tagPerson | array of text |
| tagName | array of text |
| tagPlace | array of text | 
| tagDate | array of date ranges |
| tagNotebook | array of text |
| tagDescription | array of text |

## Library of Parliament fields

Special data for https://parl.canadiana.ca/
Data side-loaded from [data/parl](data/parl)


| field | type | Required | status | Description |
------------|------|--------|----------|----
| parlLabel | string |
| parlChamber | array of strings |
| parlSession | array of strings |
| parlType | string |
| parl ReportTitle | array of text |
| parlCallNumber | string |
| parlPrimeMinisters | string |




