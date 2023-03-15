# What is CMR

The Canadiana Metadata Repository (CMR) record was created to have a single normalised record that contained simple features that other record types had in common.
The idea was that metadata from a variety of institutions would be crosswalked to this format and made searchable via the Canadiana Discovery Portal.
(See [History of software stack](stack.md)).

While some details have changed since, a good place to start is [CMR version 1.2](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) XML Schema Definition (XSD)

# Key changes

* We moved from expressing the format in XML to JSON
* We use the field names as they are expressed within the Solr schema, saving an additional crosswalk
* There are additional fields added from sources other than a descriptive metadata crosswalk

# Crosswalks

In the past there were many crosswalks depending on source of data.  This has been reduced to 3, and we only support metadata which Canadiana/CRKN loads.

* Simple Dublin Core (link to be added)
* IssueInfo (link to be added)
* MARC (link to be added)

# Simple lookup table of currently used fields

## Required Control fields

field | type | Description
------|------|----
depositor | string | The part of the slug before the first "." (calculated)
key | string | slug for this record
label | string | Label currently copied from Access IIIF label (Not a IIIF string, so no language support)
noid | string | noid for this record
type | string | One of "series", "document", "page"


## Optional control fields

field | type | Description
------|------|---
collection | array of strings | array of the slugs of collections this document is part of (excluding pkey)
component_count | positive integer | Number of images in a manifest
component_count_fulltext | positive integer | Number of images which have XML OCR data
identifier | array of strings | Displayed array of identifiers.
item_count | positive integer | Number of members in a collection
lang | array of strings | 3-character ISO 639-3 language code
manifest_noid| string(noid} | noid of manifest, used by type=page
pkey | string(slug) | Parent slug for issue of a series (its "multi-part" collectin), or pages of a manifest
plabel | string | Label of parent for issue of a series (lookup when building record)
pubmax | string | Maximum ISO 8601 date for a publication date range.
pubmin | string | Minimum ISO 8601 date for a publication date range.
seq | Positive Integer | Used to sort issues of a series (currently an array index from multi-part collection)

Note on `identifier`:  The {slug} and the part of the {slug} after the first "." are appended to the array that is built from the descriptive metadata crosswalks.  These are a legacy from earlier iterations of the software stack when "depositors" and "CIHM numbers" had meaning.


## Optional Description and content

field | type | Description
------|------|---
ab | array of text | Description
au | array of text | Author/Creator
no | array of text | Notes
no_rights | array of text | Notes
no_source | array of text | Notes
pu | array of text | Published
su | array of text | Subject
ti | array of text | Title
tx | array of text | Text (added from OCR data)

## Optional Presentation-only fields

field | type | Description
------|------|---
components | object | JSON object containing information about each component of the item. Key-value pair looks like: $id: {label: $label, canonicalMaster: $canonicalMaster, canonicalDownload: $canonicalDownload, hasTags: $(true if component has tag metadata), noid: $canvasNoid }
canonicalMaster | string | old-style reference to image
canonicalMasterSize | positive integer | 
canonicalMasterMime | string |
canonicalMasterMD5 | string |
canonicalMasterWidth | positive integer | 
canonicalMasterHeight | positive integer | 
canonicalMasterDownload | string | old-style reference to PDF download
canonicalMasterDownloadSize | positive integer | 
canonicalMasterDownloadMime | string |
canonicalMasterDownloadMD5 | string |
items | object | JSON object containing information about each issue of the series. Key-value pair looks like: $id: {label: $label, pubmin: $pubmin}. Items that are not approved will not be included.
order | array | Array containing child (item/component) IDs in the correct order.

## Optional Heritage Premium metadata fields

Special data for https://heritage.canadiana.ca/
Data side-loaded from [data/tag](../data/tag)

Hack to make use of tags generated through contract for the Heritage Premium project.
Tags are used in search, but display was removed because data was dirty.


field | type | Description
------|------|----
tag | array of text |
tagDate | array of date ranges |
tagDescription | array of text |
tagName | array of text |
tagNotebook | array of text |
tagPerson | array of text |
tagPlace | array of text | 
hasTags | boolean | flag set in manifest to indicate some image has tags.

## Optional Library of Parliament fields

Special data for https://parl.canadiana.ca/
Data side-loaded from [data/parl](../data/parl)

Hack to enable the browse tree, and portal-specific search facets.

field | type | Description |
------|------|---
parlCallNumber | string
parlChamber | array of strings | Chamber
parlLabel | string
parlPrimeMinisters | string
parlReportTitle | array of text
parlSession | array of strings | Session
parlType | string |
parlNode | string |
pubmin | string | Replaces field in descriptive metadata
pubmax | string | Replaces descriptive metadata
