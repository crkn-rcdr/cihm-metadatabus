<?xml version="1.0" encoding="UTF-8"?>

<!--

  Convert cmr version 1.1.1 and earlier to the CanadianaOnline-1.4.3 Solr schema

-->

<xsl:stylesheet
  version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:cmr="http://canadiana.ca/schema/2012/xsd/cmr"
  exclude-result-prefixes="cmr"
>

<xsl:output method="xml" encoding="UTF-8" indent="yes"/>

<xsl:key name="id" match="cmr:key" use="."/>

<xsl:template match="cmr:recordset">
  <add commitWithin="60000">
    <xsl:apply-templates select="cmr:record"/>
  </add>
</xsl:template>

<xsl:template match="cmr:record">
  <doc>
    <!-- Get the record key -->
    <xsl:variable name="key" select="cmr:key"/>
    <field name="identifier"><xsl:value-of select="$key"/></field>

    <!-- Map deprecated types into new onese -->
    <xsl:variable name="type">
      <xsl:choose>
        <xsl:when test="cmr:type = 'serial' or cmr:type = 'collection'">series</xsl:when>
        <xsl:when test="cmr:type = 'monograph' or cmr:type = 'issue'">document</xsl:when>
        <xsl:otherwise><xsl:value-of select="cmr:type"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>

    <!-- Required control fields -->
    <field name="key"><xsl:value-of select="concat(cmr:contributor, '.', $key)"/></field>
    <field name="type"><xsl:value-of select="$type"/></field>
    <field name="contributor"><xsl:value-of select="cmr:contributor"/></field>
    <field name="label"><xsl:value-of select="cmr:label"/></field>

    <!-- Optional control fields -->
    <xsl:apply-templates select="cmr:pkey"/>
    <xsl:apply-templates select="cmr:seq"/>

    <!--
      Use the record's own pubdate, if it has one. Otherwise, use the
      pubdate of the parent record, if there is one.
    -->
    <xsl:choose>
      <xsl:when test="cmr:pubdate">
        <xsl:apply-templates select="cmr:pubdate"/>
      </xsl:when>
      <xsl:when test="key('id', cmr:pkey)">
        <xsl:apply-templates select="key('id', cmr:pkey)/../cmr:pubdate"/>
      </xsl:when>
    </xsl:choose>

    <!--
      If the record specifies language elements, use them. Otherwise, use
      the parent record's, if present.
    -->
    <xsl:choose>
      <xsl:when test="cmr:lang">
        <xsl:apply-templates select="cmr:lang"/>
      </xsl:when>
      <xsl:when test="key('id', cmr:pkey)">
        <xsl:apply-templates select="key('id', cmr:pkey)/../cmr:lang"/>
      </xsl:when>
    </xsl:choose>

    <!-- Description and content -->
    <xsl:apply-templates select="cmr:description"/>

    <!-- Description and content from child pages -->
    <xsl:if test="$type = 'document'">
      <xsl:apply-templates select="//cmr:recordset/cmr:record/cmr:pkey[text() = $key]/following-sibling::cmr:description/*"/>
    </xsl:if>

    <!-- TODO: Issue labels and keys -->

    <!-- Resources and links -->
    <xsl:apply-templates select="cmr:resource"/>
  </doc>
</xsl:template>

<xsl:template match="cmr:description">
  <xsl:apply-templates/>
</xsl:template>

<xsl:template match="cmr:pkey">
  <field name="{local-name()}"><xsl:value-of select="concat(ancestor::cmr:record/descendant::cmr:contributor, '.', text())"/></field>
</xsl:template>

<xsl:template match="cmr:pubdate">
  <field name="pubmin"><xsl:value-of select="@min"/></field>
  <field name="pubmax"><xsl:value-of select="@max"/></field>
</xsl:template>

<xsl:template match="cmr:seq|cmr:lang">
  <field name="{local-name()}"><xsl:apply-templates/></field>
</xsl:template>

<xsl:template match="cmr:title|cmr:author|cmr:publication|cmr:subject|cmr:note|cmr:descriptor|cmr:text">
  <xsl:variable name="field">
    <xsl:choose>
      <xsl:when test="local-name() = 'title'">ti</xsl:when>
      <xsl:when test="local-name() = 'author'">au</xsl:when>
      <xsl:when test="local-name() = 'publication'">pu</xsl:when>
      <xsl:when test="local-name() = 'subject'">su</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'identifier'">identifier</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'continued'">no_continued</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'continues'">no_continues</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'frequency'">no_frequency</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'missing'">no_missing</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'rights'">no_rights</xsl:when>
      <xsl:when test="local-name() = 'note' and @type = 'source'">no_source</xsl:when>
      <xsl:when test="local-name() = 'note'">no</xsl:when>
      <xsl:when test="local-name() = 'descriptor'">de</xsl:when>
      <xsl:when test="local-name() = 'text' and @type = 'content'">tx</xsl:when>
      <xsl:when test="local-name() = 'text' and @type = 'description'">ab</xsl:when>
    </xsl:choose>
  </xsl:variable>
  <field name="{$field}"><xsl:value-of select="."/></field>
</xsl:template>

<xsl:template match="cmr:resource">
  <xsl:if test="cmr:canonicalUri">
    <field name="canonicalUri"><xsl:value-of select="cmr:canonicalUri"/></field>
  </xsl:if>
  <xsl:if test="cmr:canonicalPreviewUri">
    <field name="canonicalPreviewUri"><xsl:value-of select="cmr:canonicalPreviewUri"/></field>
  </xsl:if>
  <xsl:apply-templates select="cmr:canonicalMaster"/>
  <xsl:apply-templates select="cmr:canonicalDownload"/>
</xsl:template>

<xsl:template match="cmr:canonicalMaster|cmr:canonicalDownload">
  <field name="{local-name()}"><xsl:value-of select="."/></field>
  <xsl:if test="@size"><field name="{local-name()}Size"><xsl:value-of select="@size"/></field></xsl:if>
  <xsl:if test="@mime"><field name="{local-name()}Mime"><xsl:value-of select="@mime"/></field></xsl:if>
  <xsl:if test="@md5"><field name="{local-name()}MD5"><xsl:value-of select="@md5"/></field></xsl:if>
</xsl:template>

</xsl:stylesheet>

