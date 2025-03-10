/*
 * xml.c: a libFuzzer target to test several XML parser interfaces.
 *
 * See Copyright for the status of this software.
 */

#include <libxml/catalog.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/tree.h>
#include <libxml/xmlerror.h>
#include <libxml/xinclude.h>
#include <libxml/xmlreader.h>
#include "fuzz.h"

static void errorCallback(void* ctx, const char* msg ATTRIBUTE_UNUSED, ...) {
  xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
  xmlErrorPtr error = xmlCtxtGetLastError(ctxt);
  if (error != NULL && error->level == XML_ERR_FATAL)
      xmlStopParser(ctxt);
}

static xmlSAXHandler xmlSAXHandlerStruct = {
    NULL, /* internalSubset */
    NULL, /* isStandalone */
    NULL, /* hasInternalSubset */
    NULL, /* hasExternalSubset */
    NULL, /* resolveEntity */
    NULL, /* getEntity */
    NULL, /* entityDecl */
    NULL, /* notationDecl */
    NULL, /* attributeDecl */
    NULL, /* elementDecl */
    NULL, /* unparsedEntityDecl */
    NULL, /* setDocumentLocator */
    NULL, /* startDocument */
    NULL, /* endDocument */
    NULL, /* startElement */
    NULL, /* endElement */
    NULL, /* reference */
    NULL, /* characters */
    NULL, /* ignorableWhitespace */
    NULL, /* processingInstruction */
    NULL, /* comment */
    NULL, /* warning */
    NULL, /* error */
    NULL, /* fatalError */
    NULL, /* getParameterEntity */
    NULL, /* cdataBlock; */
    NULL, /* externalSubset; */
    XML_SAX2_MAGIC,
    NULL, /* _private (unused) */
    NULL, /* startElementNs */
    NULL, /* endElementNs */
    NULL  /* serror */
};

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
    xmlDocPtr doc;
    xmlDocPtr preservedReaderDoc = NULL;
    xmlParserCtxtPtr ctxt;
    xmlParserInputBufferPtr inputBuffer;
    xmlTextReaderPtr reader;
    xmlChar *out;
    const char *docBuffer, *docUrl;
    size_t maxSize, docSize, consumed, initialChunkSize, chunkSize, maxChunkSize;
    int opts, outSize;

    xmlFuzzDataInit(data, size);
    opts = xmlFuzzReadInt();

    /* Lower maximum size when processing entities for now. */
    maxSize = opts & XML_PARSE_NOENT ? 50000 : 500000;
    if (size > maxSize)
        goto exit;

    xmlFuzzReadEntities();
    docBuffer = xmlFuzzMainEntity(&docSize);
    docUrl = xmlFuzzMainUrl();
    if (docBuffer == NULL)
        goto exit;

    initialChunkSize = xmlMin(xmlFuzzDataHash() % 5, docSize);
    maxChunkSize = xmlMax(128, xmlMin(xmlFuzzDataHash() % 1024, docSize));

    /* Pull parser */

    doc = xmlReadMemory(docBuffer, docSize, docUrl, NULL, opts);
    if (opts & XML_PARSE_XINCLUDE)
        xmlXIncludeProcessFlags(doc, opts);
    /* Also test the serializer. */
    xmlDocDumpMemory(doc, &out, &outSize);
    xmlFree(out);
    xmlFreeDoc(doc);

    /* Push parser */

    ctxt = xmlCreatePushParserCtxt(NULL, NULL, NULL, initialChunkSize, docUrl);
    if (ctxt == NULL)
        goto exit;
    xmlCtxtUseOptions(ctxt, opts);

    for (consumed = initialChunkSize; consumed < docSize; consumed += chunkSize) {
        chunkSize = docSize - consumed;
        if (chunkSize > maxChunkSize)
            chunkSize = maxChunkSize;
        xmlParseChunk(ctxt, docBuffer + consumed, chunkSize, 0);
    }

    xmlParseChunk(ctxt, NULL, 0, 1);

    /* Also test the serializer. */
    xmlDocDumpMemory(ctxt->myDoc, &out, &outSize);
    xmlFree(out);

    if (opts & XML_PARSE_XINCLUDE)
        xmlXIncludeProcessFlags(ctxt->myDoc, opts);
    xmlFreeDoc(ctxt->myDoc);
    xmlFreeParserCtxt(ctxt);

    /* Reader */

    reader = xmlReaderForMemory(docBuffer, docSize, NULL, NULL, opts);
    if (reader == NULL)
        goto exit;
    while (xmlTextReaderRead(reader) == 1) {
        if (xmlTextReaderNodeType(reader) == XML_ELEMENT_NODE) {
            int i, n = xmlTextReaderAttributeCount(reader);
            for (i=0; i<n; i++) {
                xmlTextReaderMoveToAttributeNo(reader, i);
                while (xmlTextReaderReadAttributeValue(reader) == 1);
            }
        }
    }
    if (xmlFuzzDataHash() % 5 == 0)
        preservedReaderDoc = xmlTextReaderCurrentDoc(reader);
    if (xmlFuzzDataHash() % 3 == 0)
        xmlTextReaderClose(reader);
    xmlFreeTextReader(reader);
    if (xmlFuzzDataHash() % 5 == 0 && preservedReaderDoc) {
        xmlFreeDoc(preservedReaderDoc);
    }

    /* SAX parser */

    inputBuffer = xmlParserInputBufferCreateMem((const char*)data, (int)size, XML_CHAR_ENCODING_NONE);
    if (inputBuffer) {
        ctxt = xmlNewParserCtxt();
        if (ctxt) {
            xmlCtxtUseOptions(ctxt, opts);
            xmlSAXHandlerPtr handler = &xmlSAXHandlerStruct;
            if (xmlFuzzDataHash() % 5 == 0)
                handler->error = &errorCallback;
            xmlSAXHandlerPtr old_sax = ctxt->sax;
            ctxt->sax = handler;
            ctxt->userData = ctxt;
            xmlParserInputPtr inputStream = xmlNewIOInputStream(ctxt, inputBuffer, XML_CHAR_ENCODING_NONE);
            if (inputStream) {
                inputPush(ctxt, inputStream);
                xmlParseDocument(ctxt);
                doc = ctxt->myDoc;
                if (doc) {
                    ctxt->myDoc = NULL;
                    /* Also test the serializer. */
                    xmlDocDumpMemory(doc, &out, &outSize);
                    xmlFree(out);
                    xmlFreeDoc(doc);
                }
            }
            ctxt->sax = old_sax;
            xmlFreeParserCtxt(ctxt);
            if (xmlFuzzDataHash() % 5 == 0)
                handler->error = NULL;
        }
    }

exit:
    xmlFuzzDataCleanup();
    xmlResetLastError();
    return(0);
}

