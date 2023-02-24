# Issueinfo (Custom Canadiana Schema) to CMR crosswalk


* Issueinfo XML Schema Definitions: [issueinfo.xsd](https://github.com/crkn-rcdr/Digital-Preservation/blob/main/xml/published/schema/2012/xsd/issueinfo/issueinfo.xsd
* [Canadiana Metadata Repository (CMR) fields](cmr.md)
* [Source code (perl)](../CIHM-Normalise/lib/CIHM/Normalise/issueinfo.pm)

XML file is processed in XML order, meaning if an array of values are being added to a single CMR field then they will be added in the order that they appeared in the XML file.


## Crosswalk

Issueinfo field | CMR field(s) | Description
----------------|--------------|-----------
series | | unused
title | ti | add to array
sequence | | unused
language | lang | filered through normalise_lang() to return 3 letter ISO693 language codes.
coverage | | unused
published | pubmin, pubmax | Depending on the length of string, different rules are used.  4 characters assumes "yyyy" format and appends "-01-01" to create pubmin and "-12-31" to create pubmax. 7 letters assumed "yyyy-mm" and appends "-01" to create pubmin and the correct number of days per month to create pubmax. 10 characters is assumed "yyyy-mm-dd" and puts the same content for pubmin and pubmax. If that fails, try the iso8601() used for MARC, and don't set if that still fails.
pubstatement | pu | add to array
source | no_source | add to array
identifier | identifier | add to array
note | no | add to array


