# Simple Dublin Core to CMR crosswalk


* Simple Dublin Core XML Schema Definitions: [simpledc.xsd](https://www.dublincore.org/schemas/xmls/qdc/2008/02/11/simpledc.xsd) , [dc.xsd](https://www.dublincore.org/schemas/xmls/qdc/2008/02/11/dc.xsd)
* [Canadiana Metadata Repository (CMR) fields](cmr.md)
* [Source code (perl)](../CIHM-Normalise/lib/CIHM/Normalise/dc.pm)

XML file is processed in XML order, meaning if an array of values are being added to a single CMR field then they will be added in the order that they appeared in the XML file.


## Crosswalk

DC field | CMR field(s) | Description
---------|------------|-----------
title | ti | added to array
creator | au | added to array
subject | su | added to array
description | ab | added to array
publisher | pu | added to array
contributor | no_source | added to array
date | pubmin, pubmax | Supports date ranges (2 dates separated by '/'), as well as an older style where 2 separate dates became a range.
type | no | added to array
format | | unused
identifier | identifier | added to array
source | no_source | added to array
language | lang | filered through normalise_lang() to return 3 letter ISO693 language codes.
relation | no | added to array
coverage | no | added to array
rights | no | added to array

