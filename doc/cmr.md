# What is CMR

The Canadiana Metadata Repository (CMR) record was created to have a single normalised record that contained simple features that other record types had in common.
The idea was that metadata from a variety of institutions would be crosswalked to this format and made searchable via the Canadiana Discovery Portal.
(See [History of software stack](stack.md)).

While some details have changed since, a good place to start is [CMR version 1.2](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/cmr/cmr.xsd) XML Schema Definition (XSD)

# Key changes

* We moved from expressing the format in XML to JSON
* We use the field names as they are expressed within the Solr schema, saving an additional crosswalk
* There are additional fields added from sources other than a descriptive metadata crosswalk
* The file [cmr.xml is no longer stored in an AIP](https://github.com/crkn-rcdr/Digital-Preservation/blob/71310c6161a049712cbcef311da0beb804e8d8a1/xml/published/schema/2012/txt/aip.txt#L54) with the crosswalks happening at ingest time, but where the (regularly enhanced) crosswalks are done as part of creating records to be indexed in Solr and made available to CAP for presentation.

# Crosswalks

In the past there were many crosswalks depending on source of data.  This has been reduced to 3, and we only support metadata which Canadiana/CRKN loads that has been encoded using fields, data types and other aspects of these remaining crosswalks.

* [Simple Dublin Core](dc-crosswalk.md)
* [IssueInfo](issueinfo-crosswalk.md)
* [MARC](marc-crosswalk.md)


It is important to note that [Solr search](https://github.com/crkn-rcdr/solr) and [CAP](https://github.com/crkn-rcdr/cap) do not support Dublin Core, Issueinfo or MARC. These only support CMR, where most of the semantics or richer metadata formats like MARC are lost in the crosswalks and unavailable to search as facets.

# Simple lookup table of currently used fields

## Required Control fields

field | type | Description
------|------|----
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
seq | Positive Integer | Used to sort issues of a series (currently an array index from multi-part collection)

Note on `identifier`:  The {slug} and the part of the {slug} after the first "." are appended to the array that is built from the descriptive metadata crosswalks.  These are a legacy from earlier iterations of the software stack when "depositors" and "CIHM numbers" had meaning.


## Optional Description

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


## Search-only fields

field | type | Description
------|------|---
depositor | string | The part of the slug before the first "." (calculated, deprecated)
pubmax | string | Maximum ISO 8601 date for a publication date range.
pubmin | string | Minimum ISO 8601 date for a publication date range.
tx | array of text | Text (added from OCR data)


## Presentation-only fields

field | type | Description
------|------|---
components | object | JSON object containing information about each component of the item. Key-value pair looks like: $id: {label: $label, canonicalMaster: $canonicalMaster, canonicalDownload: $canonicalDownload, hasTags: $(true if component has tag metadata), noid: $canvasNoid }
canonicalMaster | string | old-style reference to image (see 'file' field)
canonicalMasterExtension | string |
canonicalMasterSize | positive integer | 
canonicalMasterMime | string |
canonicalMasterMD5 | string |
canonicalMasterWidth | positive integer | 
canonicalMasterHeight | positive integer | 
canonicalDownload | string | old-style reference to PDF download (see 'ocrPdf' field)
canonicalDownloadExtension | string |
canonicalDownloadSize | positive integer |
canonicalDownloadMime | string |
canonicalDownloadMD5 | string |
items | object | JSON object containing information about each issue of the series. Key-value pair looks like: $id: {label: $label, pubmin: $pubmin}. Items that are not approved will not be included.
order | array | Array containing child (item/component) IDs in the correct order.
file | object | [FileRef{}](https://github.com/crkn-rcdr/Access-Platform/blob/main/packages/data/src/util/FileRef.ts) for other (possibly born digital?)  download.
ocrPdf | object | [FileRef{}](https://github.com/crkn-rcdr/Access-Platform/blob/main/packages/data/src/util/FileRef.ts) for multi-page OCR PDF download.
collectiontree | object | **experimental** - See: [CAP issue 138](https://github.com/crkn-rcdr/cap/issues/138)
updated | string | date string of last time cache was updated

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


## Deprecated/unknown fields

These are things discovered while documenting that are leftovers from previous revisions.

field | type | Description |
------|------|---
pg_label | deprecate | Mentioned in Hammer for cosearch, but doesn't exist in any current documentation
media | deprecate | Mentioned in Hammer for copresentation, but was removed from documentation years ago.
canonicalUri | deprecate | Mentioned in Hammer for copresentation, but hasn't existed for years?
repos | deprecate | Was used in the past in presentation, but should be removed.