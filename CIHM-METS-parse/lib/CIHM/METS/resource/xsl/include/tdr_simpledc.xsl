<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:cmr="http://canadiana.ca/schema/2012/xsd/cmr"
  xmlns:mets="http://www.loc.gov/METS/"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:iso693="http://www.canadiana.ca/XML/cmr-iso693"
  exclude-result-prefixes="iso693 mets dc xlink"
>

  <xsl:import href="iso693.xsl"/>

  <xsl:template name="tdr_simpledc">
    <xsl:param name="type"/>
    <xsl:variable name="dmd" select="key('dmd', @DMDID)/mets:mdWrap/mets:xmlData/simpledc"/>
    <cmr:record>
      <cmr:type><xsl:value-of select="$type"/></cmr:type>
      <cmr:contributor><xsl:value-of select="$contributor"/></cmr:contributor>
      <cmr:key><xsl:value-of select="//mets:mets/@OBJID"/></cmr:key>
      <cmr:label><xsl:value-of select="@LABEL"/></cmr:label>
      <xsl:choose>
        <xsl:when test="count($dmd/dc:date) = 1">
          <cmr:pubdate min="{$dmd/dc:date}" max="{$dmd/dc:date}"/>
        </xsl:when>
        <xsl:when test="count($dmd/dc:date) &gt; 1">
          <cmr:pubdate min="{$dmd/dc:date[position() = 1]}" max="{$dmd/dc:date[position() = 2]}"/>
        </xsl:when>
      </xsl:choose>
      <xsl:apply-templates select="$dmd/dc:language"/>
      <xsl:apply-templates select="$dmd/dc:format"/>
      <cmr:description>
        <xsl:apply-templates select="$dmd/dc:contributor"/>
        <xsl:apply-templates select="$dmd/dc:coverage"/>
        <xsl:apply-templates select="$dmd/dc:creator"/>
        <xsl:apply-templates select="$dmd/dc:description"/>
        <xsl:apply-templates select="$dmd/dc:identifier"/>
        <xsl:apply-templates select="$dmd/dc:publisher"/>
        <xsl:apply-templates select="$dmd/dc:relation"/>
        <xsl:apply-templates select="$dmd/dc:rights"/>
        <xsl:apply-templates select="$dmd/dc:source"/>
        <xsl:apply-templates select="$dmd/dc:subject"/>
        <xsl:apply-templates select="$dmd/dc:title"/>
        <xsl:apply-templates select="$dmd/dc:type"/>
      </cmr:description>
      <cmr:resource>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'canonical']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'master']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'distribution']"/>
      </cmr:resource>
    </cmr:record>
  </xsl:template>

  <xsl:template match="dc:language">
    <cmr:lang><xsl:value-of select="normalize-space(.)"/></cmr:lang>
  </xsl:template>

  <xsl:template match="dc:contributor">
    <cmr:note type="source"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:coverage">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:creator">
    <cmr:author><xsl:value-of select="normalize-space(.)"/></cmr:author>
  </xsl:template>

  <xsl:template match="dc:description">
    <cmr:text type="description"><xsl:value-of select="normalize-space(.)"/></cmr:text>
  </xsl:template>

  <xsl:template match="dc:identifier">
    <cmr:note type="identifier"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:publisher">
    <cmr:publication><xsl:value-of select="normalize-space(.)"/></cmr:publication>
  </xsl:template>

  <xsl:template match="dc:relation">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:rights">
    <cmr:note type="rights"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:source">
    <cmr:note type="source"><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

  <xsl:template match="dc:subject">
    <cmr:subject><xsl:value-of select="normalize-space(.)"/></cmr:subject>
  </xsl:template>

  <xsl:template match="dc:title">
    <cmr:title><xsl:value-of select="normalize-space(.)"/></cmr:title>
  </xsl:template>

  <xsl:template match="dc:type">
    <cmr:note><xsl:value-of select="normalize-space(.)"/></cmr:note>
  </xsl:template>

</xsl:stylesheet>
