<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:cmr="http://canadiana.ca/schema/2012/xsd/cmr"
  xmlns:mets="http://www.loc.gov/METS/"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:issue="http://canadiana.ca/schema/2012/xsd/issueinfo"
  exclude-result-prefixes="mets xlink issue"
>

  <xsl:template name="tdr_issue">
    <xsl:variable name="dmd" select="key('dmd', @DMDID)/mets:mdWrap/mets:xmlData/descendant::issue:issueinfo"/>
    <xsl:variable name="pubmin">
      <xsl:choose>
        <xsl:when test="string-length($dmd/issue:published) = 4">
          <xsl:value-of select="concat($dmd/issue:published, '-01-01')"/>
        </xsl:when>
        <xsl:when test="string-length($dmd/issue:published) = 7">
          <xsl:value-of select="concat($dmd/issue:published, '-01')"/>
        </xsl:when>
        <xsl:when test="string-length($dmd/issue:published) = 10">
          <xsl:value-of select="$dmd/issue:published"/>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>
    <xsl:variable name="pubmax">
      <xsl:choose>
        <xsl:when test="string-length($dmd/issue:published) = 4">
          <xsl:value-of select="concat($dmd/issue:published, '-12-31')"/>
        </xsl:when>
        <xsl:when test="string-length($dmd/issue:published) = 7">
          <xsl:choose>
            <xsl:when test="substring($dmd/issue:published, 6) = '02'">
              <xsl:value-of select="concat($dmd/issue:published, '-28')"/>
            </xsl:when>
            <xsl:when test="
              substring($dmd/issue:published, 6) = '01' or
              substring($dmd/issue:published, 6) = '03' or
              substring($dmd/issue:published, 6) = '05' or
              substring($dmd/issue:published, 6) = '07' or
              substring($dmd/issue:published, 6) = '08' or
              substring($dmd/issue:published, 6) = '10' or
              substring($dmd/issue:published, 6) = '12'
            ">
              <xsl:value-of select="concat($dmd/issue:published, '-31')"/>
            </xsl:when>
            <xsl:when test="
              substring($dmd/issue:published, 6) = '04' or
              substring($dmd/issue:published, 6) = '06' or
              substring($dmd/issue:published, 6) = '09' or
              substring($dmd/issue:published, 6) = '11'
            ">
              <xsl:value-of select="concat($dmd/issue:published, '-30')"/>
            </xsl:when>
          </xsl:choose>
        </xsl:when>
        <xsl:when test="string-length($dmd/issue:published) = 10">
          <xsl:value-of select="$dmd/issue:published"/>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>
    <cmr:record>
      <cmr:type>document</cmr:type>
      <cmr:contributor><xsl:value-of select="$contributor"/></cmr:contributor>
      <cmr:key><xsl:value-of select="//mets:mets/@OBJID"/></cmr:key>
      <cmr:label><xsl:value-of select="@LABEL"/></cmr:label>
      <cmr:pkey><xsl:apply-templates select="$dmd/issue:series"/></cmr:pkey>
      <cmr:seq><xsl:apply-templates select="$dmd/issue:sequence"/></cmr:seq>
      <cmr:pubdate min="{$pubmin}" max="{$pubmax}"/>
      <xsl:apply-templates select="$dmd/issue:language"/>
      <cmr:description>
        <cmr:title><xsl:apply-templates select="$dmd/issue:title"/></cmr:title>
        <xsl:apply-templates select="$dmd/issue:pubstatement"/>
        <xsl:apply-templates select="$dmd/issue:source"/>
        <xsl:apply-templates select="$dmd/issue:note"/>
        <xsl:apply-templates select="$dmd/issue:identifier"/>
      </cmr:description>
      <cmr:resource>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'canonical']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'master']"/>
        <xsl:apply-templates select="mets:fptr[key('file', @FILEID)/../@USE = 'distribution']"/>
      </cmr:resource>
    </cmr:record>
  </xsl:template>

  <xsl:template match="issue:language">
    <cmr:lang><xsl:apply-templates/></cmr:lang>
  </xsl:template>

  <xsl:template match="issue:pubstatement">
    <cmr:publication><xsl:apply-templates/></cmr:publication>
  </xsl:template>

  <xsl:template match="issue:source">
    <cmr:note type="source"><xsl:apply-templates/></cmr:note>
  </xsl:template>

  <xsl:template match="issue:note">
    <cmr:note><xsl:apply-templates/></cmr:note>
  </xsl:template>

  <xsl:template match="issue:identifier">
    <cmr:note type="identifier"><xsl:apply-templates/></cmr:note>
  </xsl:template>


</xsl:stylesheet>
