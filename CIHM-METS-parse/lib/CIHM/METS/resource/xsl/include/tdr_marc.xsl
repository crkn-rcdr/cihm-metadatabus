<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:cmr="http://canadiana.ca/schema/2012/xsd/cmr"
  xmlns:mets="http://www.loc.gov/METS/"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  xmlns:iso693="http://www.canadiana.ca/XML/cmr-iso693"
  exclude-result-prefixes="iso693 mets marc xlink"
>

  <xsl:import href="iso693.xsl"/>

  <xsl:template name="tdr_marc">
    <xsl:param name="type"/>
    <xsl:variable name="dmd" select="key('dmd', @DMDID)/mets:mdWrap/mets:xmlData/descendant::marc:record"/>
    <cmr:record>
      <cmr:type><xsl:value-of select="$type"/></cmr:type>
      <cmr:contributor><xsl:value-of select="$contributor"/></cmr:contributor>
      <cmr:key><xsl:value-of select="//mets:mets/@OBJID"/></cmr:key>
      <cmr:label><xsl:value-of select="@LABEL"/></cmr:label>
      <cmr:pubdate min="{$dmd/marc:datafield[@tag='260']/marc:subfield[@code='c']}" max="{$dmd/marc:datafield[@tag='260']/marc:subfield[@code='c']}"/>

      <!-- Item languages: from the leader and the 041 field -->
      <xsl:call-template name="tdr_marc_lang">
        <xsl:with-param name="arg" select="substring($dmd/marc:controlfield[@tag='008'], 36, 3)"/>
      </xsl:call-template>
      <xsl:apply-templates select="$dmd/marc:datafield[@tag='041']/marc:subfield"/>

      <cmr:description>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '090']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '100']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '110']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '111']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '130']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '245']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '246']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '250']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '260']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '300']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '362']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '500']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '504']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '505']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '510']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '515']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '520']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag='533']/marc:subfield[@code='a']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '534']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '540']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '546']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '580']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '440']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '600']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '610']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '630']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '650']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '651']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '700']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '710']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '711']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '730']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '740']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '787']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '800']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '811']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '830']"/>
        <xsl:apply-templates select="$dmd/marc:datafield[@tag = '840']"/>
      </cmr:description>
      <cmr:resource>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'canonical']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'master']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'distribution']"/>
      </cmr:resource>
    </cmr:record>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='041']/marc:subfield">
    <xsl:call-template name="tdr_marc_lang">
      <xsl:with-param name="arg" select="translate(text(), ' ', '')"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='090']">
    <cmr:note type="identifier"><xsl:value-of select="normalize-space(marc:subfield[@code='a'])"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='100']">
    <cmr:author><xsl:value-of select="normalize-space(.)"/></cmr:author>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='110']">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='111']">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='130']">
    <cmr:title type="uniform"><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='245']">
    <cmr:title type="main">
      <xsl:value-of select="normalize-space(concat(
        marc:subfield[@code='a'], ' ',
        substring-after(marc:subfield[@code='h'], ']'), ' ',
        marc:subfield[@code='b'], ' '
      ))"/>
    </cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='246']">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='250']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='260']">
    <cmr:publication><xsl:value-of select="normalize-space(.)"/></cmr:publication>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='300']">
    <cmr:note type="extent"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='362']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='440']">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='500']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='504']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='505']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='510']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='515']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='520']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='533']/marc:subfield[@code='a']">
    <cmr:note type="source"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='534']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='540']">
    <cmr:note type="rights"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='546']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='580']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='600' or @tag='610' or @tag='630' or @tag='650' or @tag='651']">
    <xsl:variable name="lang">
      <xsl:choose>
        <xsl:when test="@ind2 = '6'">fra</xsl:when>
        <xsl:otherwise>eng</xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <cmr:subject lang="{$lang}">
      <xsl:for-each select="marc:subfield">
        <xsl:if test="@code='b'"><xsl:text> </xsl:text></xsl:if>
        <xsl:if test="@code='v' or @code='x' or @code='y' or @code='z'"> -- </xsl:if>
        <xsl:value-of select="normalize-space(.)"/>
      </xsl:for-each>
    </cmr:subject>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='700']">
    <cmr:author><xsl:value-of select="normalize-space(.)"/></cmr:author>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='710']">
    <cmr:author><xsl:value-of select="normalize-space(.)"/></cmr:author>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='711']">
    <cmr:author><xsl:value-of select="normalize-space(.)"/></cmr:author>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='730']">
    <cmr:title type="uniform"><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='740']">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='787']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='800']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='810']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='811']">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='830']">
    <cmr:title type="uniform"><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="marc:datafield[@tag='840']">
    <cmr:title type="uniform"><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template name="tdr_marc_lang">
    <xsl:param name="arg"/>
    <xsl:if test="string-length($arg) &gt;= 3">
      <cmr:lang>
        <xsl:call-template name="iso693:lang">
          <xsl:with-param name="arg" select="substring($arg, 1, 3)"/>
        </xsl:call-template>
      </cmr:lang>
    </xsl:if>
    <xsl:if test="string-length($arg) &gt;= 6">
      <xsl:call-template name="tdr_marc_lang">
        <xsl:with-param name="arg" select="substring($arg, 4)"/>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>
