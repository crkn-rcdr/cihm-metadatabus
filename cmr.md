# What is CMR

The Canadiana Metadata Repository (CMR) record was created to have a single normalised record that contained simple features that other record types had in common.
The idea was that metadata from a variety of institutions would be crosswalked to this format and made searchable via the Canadiana Discovery Portal.
(See [History of software stack](stack.md)).

While some details have changed since, a good place to start is [CMR version 1.2](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) XML Schema Definition (XSD)

# Key changes

* We moved from expressing the format in XML to JSON
* We use the field names as they are expressed within the Solr schema, saving an additional crosswalk
* There are additional fields added from sources other than a descriptive metadata crosswalk

# Simple lookup table of currently used fields

## Required Control fields

field | type | Description |
------|------|----
key | string | slug of this record | 
noid | string | noid of this record |
type | string | One of "series", "document", "page" |
depositor | string | The part of the slug before the first "." |
label | string | Label currently copied from Access IIIF label |


## Optional control fields

field | type | Description |
------|------|---
manifest_noid| string(noid} | noid of manifest, used by type=page |
pkey | string(slug) | Parent slug for issue of a series (its "multi-part" collectin), or pages of a manifest |
plabel | string | Label of parent for issue of a series (lookup when building record) |
seq | Positive Integer | Used to sort issues of a series (currently an array index from multi-part collection) |
pubmin | string | Minimum ISO 8601 date for a publication date range. |
pubmax | string | Maximum ISO 8601 date for a publication date range. |
lang | array of strings | 3-character ISO 639-3 language code |
identifier | array of strings | Displayed array of identifiers |
collection | array of strings | array of the slugs of collections this document is part of (excluding pkey) |
item count | positive integer | |
component_count | positive integer | 
component_count_fulltext | positive integer | 

## Optional Description and content

field | type | Description |
------|------|---
ti | array of text | 
au | array of text |
pu | array of text |
su | array of text |
no | array of text |
ab | array of text |
tx | array of text | 


## Optional Heritage Premium metadata fields

Special data for https://heritage.canadiana.ca/
Data side-loaded from [data/tag](data/tag)


field | type | Description
------|------|----
tag | array of text |
tagPerson | array of text |
tagName | array of text |
tagPlace | array of text | 
tagDate | array of date ranges |
tagNotebook | array of text |
tagDescription | array of text |

## Optional Library of Parliament fields

Special data for https://parl.canadiana.ca/
Data side-loaded from [data/parl](data/parl)


field | type | Description |
------|------|---
parlLabel | string |
parlChamber | array of strings |
parlSession | array of strings |
parlType | string |
parl ReportTitle | array of text |
parlCallNumber | string |
parlPrimeMinisters | string |

