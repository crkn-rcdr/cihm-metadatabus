# MARC 21 XML to CMR crosswalk


* MARC 21 XML Schema Definitions: [MARC21slim-v1-2.xsd](https://www.loc.gov/standards/marcxml/schema/MARC21slim-v1-2.xsd)
* [MARC 21 documentation (LOC)](https://www.loc.gov/marc/bibliographic/) describing fields
* [Canadiana Metadata Repository (CMR) fields](cmr.md)
* [Source code (perl)](../CIHM-Normalise/lib/CIHM/Normalise/marc.pm)

XML file isn't currently processed in XML order, meaning if an array of values are being added to a single CMR field then they will be added in the order that they appeared in the software source code (replicated in table below).


## Crosswalk

MARC field | CMR field(s) | Description
---------|------------|-----------
264 | pu, pubmin, pubmax | All subfields used for "pu" statement. Subfield $c used to create pubmin and pubmax
260 | pu, pubmin, pubmax | If 264 didn't exist, use same logic with 260
008 | lang | copy 3 letters starting form the 35'th character of entire field expressed as a string.
041 | lang | Using all subfields, collect as many groups of 3 letters as exist in value, and pass through normalise_lang() to return an array of 3 letter ISO693 values
090 | identifier | Add any $a subfields to array.
500, 250, 300, 362, 504, 505, 510, 515, 520, 534, 540, 546, 580, 787, 800, 811 | no | String of all subfields added to array
533 | no_source | Subfield $a added to array
600, 610, 630, 650, 651 | su | Loop through all subfields. For any $b, separate with space. For any $v, $x, $y, $z separate with " -- ".  All subfields become part of value.
100, 700, 710, 711 | au | String of all subfields added to array
110, 111, 130, 246, 440, 730, 740, 830, 840 | ti | String of all subfields added to array
245 | ti | Start with $a and a space. I $h has a "]" then append everything after the "]" and a space. Then append $b. Add new string to array
