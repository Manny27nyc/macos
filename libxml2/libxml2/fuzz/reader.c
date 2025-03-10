/*
 * reader.c: a libFuzzer target to test the XML Reader interface.
 *
 * See Copyright for the status of this software.
 */

#include <libxml/catalog.h>
#include <libxml/xmlreader.h>
#include "fuzz.h"

static void run_xmlTextReaderReadInnerXml(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderReadInnerXml(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderReadOuterXml(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderReadOuterXml(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderReadString(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderReadString(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderReadAttributeValue(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderReadAttributeValue(reader);
}

static void run_xmlTextReaderAttributeCount(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderAttributeCount(reader);
}

static void run_xmlTextReaderDepth(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderDepth(reader);
}

static void run_xmlTextReaderHasAttributes(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderHasAttributes(reader);
}

static void run_xmlTextReaderHasValue(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderHasValue(reader);
}

static void run_xmlTextReaderIsDefault(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderIsDefault(reader);
}

static void run_xmlTextReaderIsEmptyElement(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderIsEmptyElement(reader);
}

static void run_xmlTextReaderNodeType(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderNodeType(reader);
}

static void run_xmlTextReaderQuoteChar(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderQuoteChar(reader);
}

static void run_xmlTextReaderReadState(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderReadState(reader);
}

static void run_xmlTextReaderIsNamespaceDecl(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderIsNamespaceDecl(reader);
}

static void run_xmlTextReaderConstBaseUri(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstBaseUri(reader);
}

static void run_xmlTextReaderConstLocalName(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstLocalName(reader);
}

static void run_xmlTextReaderConstName(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstName(reader);
}

static void run_xmlTextReaderConstNamespaceUri(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstNamespaceUri(reader);
}

static void run_xmlTextReaderConstPrefix(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstPrefix(reader);
}

static void run_xmlTextReaderConstXmlLang(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstXmlLang(reader);
}

static void run_xmlTextReaderConstString(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstString(reader, (const xmlChar*)"fuzzstring");
}

static void run_xmlTextReaderConstValue(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstValue(reader);
}

static void run_xmlTextReaderBaseUri(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderBaseUri(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderLocalName(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderLocalName(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderName(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderName(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderNamespaceUri(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderNamespaceUri(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderPrefix(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderPrefix(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderXmlLang(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderXmlLang(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderValue(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderValue(reader);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderGetAttributeNo(xmlTextReaderPtr reader, unsigned v)
{
    int attrCount = xmlTextReaderAttributeCount(reader);
    if (!attrCount)
        return;
    xmlChar *s = xmlTextReaderGetAttributeNo(reader, v % attrCount);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderLookupNamespace(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    xmlChar *s = xmlTextReaderLookupNamespace(reader, NULL);
    if (s)
        xmlFree(s);
}

static void run_xmlTextReaderMoveToAttributeNo(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    int attrCount = xmlTextReaderAttributeCount(reader);
    if (!attrCount)
        return;
    (void)xmlTextReaderMoveToAttributeNo(reader, v % attrCount);
}

static void run_xmlTextReaderMoveToFirstAttribute(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderMoveToFirstAttribute(reader);
}

static void run_xmlTextReaderMoveToNextAttribute(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderMoveToNextAttribute(reader);
}

static void run_xmlTextReaderMoveToElement(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderMoveToElement(reader);
}

static void run_xmlTextReaderNormalization(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderNormalization(reader);
}

static void run_xmlTextReaderConstEncoding(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstEncoding(reader);
}

static void run_xmlTextReaderCurrentNode(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderCurrentNode(reader);
}

static void run_xmlTextReaderGetParserLineNumber(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderGetParserLineNumber(reader);
}

static void run_xmlTextReaderGetParserColumnNumber(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderGetParserColumnNumber(reader);
}

static void run_xmlTextReaderExpand(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderExpand(reader);
}

static void run_xmlTextReaderNext(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderNext(reader);
}

static void run_xmlTextReaderNextSibling(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderNextSibling(reader);
}

static void run_xmlTextReaderIsValid(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderIsValid(reader);
}

static void run_xmlTextReaderConstXmlVersion(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderConstXmlVersion(reader);
}

static void run_xmlTextReaderStandalone(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderStandalone(reader);
}

static void run_xmlTextReaderByteConsumed(xmlTextReaderPtr reader, unsigned v)
{
    (void)v;
    (void)xmlTextReaderByteConsumed(reader);
}

typedef void (*readerFuzzFunctionType)(xmlTextReaderPtr, unsigned);

static readerFuzzFunctionType readerFuzzFunctions[] = {
    run_xmlTextReaderReadInnerXml,
    run_xmlTextReaderReadOuterXml,
    run_xmlTextReaderReadString,
    run_xmlTextReaderReadAttributeValue,
    run_xmlTextReaderAttributeCount,
    run_xmlTextReaderDepth,
    run_xmlTextReaderHasAttributes,
    run_xmlTextReaderHasValue,
    run_xmlTextReaderIsDefault,
    run_xmlTextReaderIsEmptyElement,
    run_xmlTextReaderNodeType,
    run_xmlTextReaderQuoteChar,
    run_xmlTextReaderReadState,
    run_xmlTextReaderIsNamespaceDecl,
    run_xmlTextReaderConstBaseUri,
    run_xmlTextReaderConstLocalName,
    run_xmlTextReaderConstName,
    run_xmlTextReaderConstNamespaceUri,
    run_xmlTextReaderConstPrefix,
    run_xmlTextReaderConstXmlLang,
    run_xmlTextReaderConstString,
    run_xmlTextReaderConstValue,
    run_xmlTextReaderBaseUri,
    run_xmlTextReaderLocalName,
    run_xmlTextReaderName,
    run_xmlTextReaderNamespaceUri,
    run_xmlTextReaderPrefix,
    run_xmlTextReaderXmlLang,
    run_xmlTextReaderValue,
    run_xmlTextReaderGetAttributeNo,
    run_xmlTextReaderLookupNamespace,
    run_xmlTextReaderMoveToAttributeNo,
    run_xmlTextReaderMoveToFirstAttribute,
    run_xmlTextReaderMoveToNextAttribute,
    run_xmlTextReaderMoveToElement,
    run_xmlTextReaderNormalization,
    run_xmlTextReaderConstEncoding,
    run_xmlTextReaderCurrentNode,
    run_xmlTextReaderGetParserLineNumber,
    run_xmlTextReaderGetParserColumnNumber,
    run_xmlTextReaderExpand,
    run_xmlTextReaderNext,
    run_xmlTextReaderNextSibling,
    run_xmlTextReaderIsValid,
    run_xmlTextReaderConstXmlVersion,
    run_xmlTextReaderStandalone,
    run_xmlTextReaderByteConsumed,
};

const unsigned readerFuzzFunctionsCount = sizeof(readerFuzzFunctions) / sizeof(readerFuzzFunctionType);

int
LLVMFuzzerInitialize(int *argc ATTRIBUTE_UNUSED,
                     char ***argv ATTRIBUTE_UNUSED) {
    xmlInitParser();
#ifdef LIBXML_CATALOG_ENABLED
    xmlInitializeCatalog();
#endif
    xmlSetGenericErrorFunc(NULL, xmlFuzzErrorFunc);
    xmlSetExternalEntityLoader(xmlFuzzEntityLoader);

    return 0;
}

int
LLVMFuzzerTestOneInput(const char *data, size_t size) {
    xmlDocPtr preservedReaderDoc = NULL;
    xmlTextReaderPtr reader;
    const char *docBuffer;
    size_t maxSize, docSize;
    int opts;

    xmlFuzzDataInit(data, size);
    opts = xmlFuzzReadInt();

    /* Lower maximum size when processing entities for now. */
    maxSize = opts & XML_PARSE_NOENT ? 50000 : 500000;
    if (size > maxSize)
        goto exit;

    xmlFuzzReadEntities();
    docBuffer = xmlFuzzMainEntity(&docSize);
    if (docBuffer == NULL)
        goto exit;

    reader = xmlReaderForMemory(docBuffer, docSize, NULL, NULL, opts);
    if (reader == NULL)
        goto exit;
    if (docSize % 2 == 1)
        xmlTextReaderSetParserProp(reader, XML_PARSER_VALIDATE, 1);
    if (docSize % 5 == 0)
        preservedReaderDoc = xmlTextReaderCurrentDoc(reader);
    for (unsigned i = 0; xmlTextReaderRead(reader) == 1; i = (i + 1) % docSize) {
        unsigned charValue = (unsigned)docBuffer[i];
        /* Run 1 to 3 functions for each node. */
        switch (((unsigned)docBuffer[i]) % 3) {
        case 2:
            (*readerFuzzFunctions[charValue % readerFuzzFunctionsCount])(reader, charValue);
            i = (i + 1) % docSize;
            /* Fall through */
        case 1:
            (*readerFuzzFunctions[charValue % readerFuzzFunctionsCount])(reader, charValue);
            i = (i + 1) % docSize;
            /* Fall through */
        case 0:
            (*readerFuzzFunctions[charValue % readerFuzzFunctionsCount])(reader, charValue);
        }
        if (xmlTextReaderNodeType(reader) == XML_ELEMENT_NODE) {
            int attrIndex, n = xmlTextReaderAttributeCount(reader);
            for (attrIndex=0; attrIndex<n; attrIndex++) {
                xmlTextReaderMoveToAttributeNo(reader, attrIndex);
                while (xmlTextReaderReadAttributeValue(reader) == 1);
            }
        }
    }
    if (docSize % 3 == 0)
        xmlTextReaderClose(reader);
    xmlFreeTextReader(reader);
    if (docSize % 5 == 0 && preservedReaderDoc)
        xmlFreeDoc(preservedReaderDoc);

exit:
    xmlFuzzDataCleanup();
    xmlResetLastError();
    return(0);
}

