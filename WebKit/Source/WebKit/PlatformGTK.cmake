include(GLib.cmake)
include(InspectorGResources.cmake)

if (ENABLE_PDFJS)
    include(PdfJSGResources.cmake)
endif ()

if (ENABLE_MODERN_MEDIA_CONTROLS)
    include(ModernMediaControlsGResources.cmake)
endif ()

set(WebKit_OUTPUT_NAME webkit2gtk-${WEBKITGTK_API_VERSION})
set(WebProcess_OUTPUT_NAME WebKitWebProcess)
set(NetworkProcess_OUTPUT_NAME WebKitNetworkProcess)
set(GPUProcess_OUTPUT_NAME WebKitGPUProcess)

file(MAKE_DIRECTORY ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit)
file(MAKE_DIRECTORY ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR})
file(MAKE_DIRECTORY ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-${WEBKITGTK_API_VERSION})
file(MAKE_DIRECTORY ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension)

configure_file(Shared/glib/BuildRevision.h.in ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/BuildRevision.h)
configure_file(UIProcess/API/gtk/WebKitVersion.h.in ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitVersion.h)
configure_file(gtk/webkit2gtk.pc.in ${WebKit2_PKGCONFIG_FILE} @ONLY)
configure_file(gtk/webkit2gtk-web-extension.pc.in ${WebKit2WebExtension_PKGCONFIG_FILE} @ONLY)

if (EXISTS "${TOOLS_DIR}/glib/apply-build-revision-to-files.py")
    add_custom_target(WebKit-build-revision
        ${PYTHON_EXECUTABLE} "${TOOLS_DIR}/glib/apply-build-revision-to-files.py" ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/BuildRevision.h ${WebKit2_PKGCONFIG_FILE} ${WebKit2WebExtension_PKGCONFIG_FILE}
        DEPENDS ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/BuildRevision.h ${WebKit2_PKGCONFIG_FILE} ${WebKit2WebExtension_PKGCONFIG_FILE}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} VERBATIM)
    list(APPEND WebKit_DEPENDENCIES
        WebKit-build-revision
    )
endif ()

add_definitions(-DBUILDING_WEBKIT)
add_definitions(-DWEBKIT2_COMPILATION)
add_definitions(-DWEBKIT_DOM_USE_UNSTABLE_API)

add_definitions(-DPKGLIBEXECDIR="${LIBEXEC_INSTALL_DIR}")
add_definitions(-DLOCALEDIR="${CMAKE_INSTALL_FULL_LOCALEDIR}")
add_definitions(-DDATADIR="${CMAKE_INSTALL_FULL_DATADIR}")
add_definitions(-DLIBDIR="${LIB_INSTALL_DIR}")

if (NOT DEVELOPER_MODE AND NOT CMAKE_SYSTEM_NAME MATCHES "Darwin")
    WEBKIT_ADD_TARGET_PROPERTIES(WebKit LINK_FLAGS "-Wl,--version-script,${CMAKE_CURRENT_SOURCE_DIR}/webkitglib-symbols.map")
endif ()

set(WebKit_USE_PREFIX_HEADER ON)

list(APPEND WebKit_UNIFIED_SOURCE_LIST_FILES
    "SourcesGTK.txt"
)

list(APPEND WebKit_MESSAGES_IN_FILES
    UIProcess/ViewGestureController

    WebProcess/gtk/GtkSettingsManagerProxy
    WebProcess/WebPage/ViewGestureGeometryCollector
)

list(APPEND WebKit_DERIVED_SOURCES
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/InspectorGResourceBundle.c
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitDirectoryInputStreamData.cpp
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.c

    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.cpp
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.cpp
)

if (ENABLE_WAYLAND_TARGET)
    list(APPEND WebKit_DERIVED_SOURCES
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitWaylandClientProtocol.c
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/pointer-constraints-unstable-v1-protocol.c
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/relative-pointer-unstable-v1-protocol.c
    )
endif ()

if (ENABLE_PDFJS)
    list(APPEND WebKit_DERIVED_SOURCES
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/PdfJSGResourceBundle.c
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/PdfJSGResourceBundleExtras.c
    )

    WEBKIT_BUILD_PDFJS_GRESOURCES(${WebKit2Gtk_DERIVED_SOURCES_DIR})
endif ()

if (ENABLE_MODERN_MEDIA_CONTROLS)
    list(APPEND WebKit_DERIVED_SOURCES
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/ModernMediaControlsGResourceBundle.c
    )

    WEBKIT_BUILD_MODERN_MEDIA_CONTROLS_GRESOURCES(${WebKit2Gtk_DERIVED_SOURCES_DIR})
endif ()

set(WebKit_DirectoryInputStream_DATA
    ${WEBKIT_DIR}/NetworkProcess/soup/Resources/directory.css
    ${WEBKIT_DIR}/NetworkProcess/soup/Resources/directory.js
)

add_custom_command(
    OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitDirectoryInputStreamData.cpp ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitDirectoryInputStreamData.h
    MAIN_DEPENDENCY ${WEBCORE_DIR}/css/make-css-file-arrays.pl
    DEPENDS ${WebKit_DirectoryInputStream_DATA}
    COMMAND ${PERL_EXECUTABLE} ${WEBCORE_DIR}/css/make-css-file-arrays.pl --defines "${FEATURE_DEFINES_WITH_SPACE_SEPARATOR}" --preprocessor "${CODE_GENERATOR_PREPROCESSOR}" ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitDirectoryInputStreamData.h ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitDirectoryInputStreamData.cpp ${WebKit_DirectoryInputStream_DATA}
    VERBATIM
)

if (USE_GTK4)
    set(GTK_API_VERSION 4)
    set(GTK_PKGCONFIG_PACKAGE gtk4)
else ()
    set(GTK_API_VERSION 3)
    set(GTK_PKGCONFIG_PACKAGE gtk+-3.0)
endif ()

set(WebKit2GTK_HEADER_TEMPLATES
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitApplicationInfo.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitAuthenticationRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitAutocleanups.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitAutomationSession.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitBackForwardList.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitBackForwardListItem.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitCredential.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitContextMenu.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitContextMenuActions.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitContextMenuItem.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitCookieManager.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitDefines.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitDeviceInfoPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitDownload.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitEditingCommands.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitEditorState.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitError.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitFaviconDatabase.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitFileChooserRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitFindController.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitFormSubmissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitGeolocationManager.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitGeolocationPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitHitTestResult.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitInputMethodContext.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitInstallMissingMediaPluginsPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitJavascriptResult.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitMediaKeySystemPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitMemoryPressureSettings.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitMimeInfo.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitNavigationAction.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitNavigationPolicyDecision.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitNetworkProxySettings.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitNotificationPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitNotification.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitOptionMenu.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitOptionMenuItem.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitPlugin.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitPolicyDecision.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitResponsePolicyDecision.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitScriptDialog.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitSecurityManager.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitSecurityOrigin.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitSettings.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitURIRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitURIResponse.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitURISchemeRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitURISchemeResponse.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitURIUtilities.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitUserContent.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitUserContentFilterStore.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitUserContentManager.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitUserMediaPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitUserMessage.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebContext.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebResource.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebView.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebViewSessionState.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebsiteData.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebsiteDataAccessPermissionRequest.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebsiteDataManager.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWindowProperties.h.in
    ${WEBKIT_DIR}/UIProcess/API/glib/WebKitWebsitePolicies.h.in
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitWebViewBase.h.in
)

set(WebKit2GTK_INSTALLED_HEADERS
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.h
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitVersion.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitColorChooserRequest.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitPointerLockPermissionRequest.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitPrintCustomWidget.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitPrintOperation.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitWebInspector.h
    ${WEBKIT_DIR}/UIProcess/API/gtk/webkit2.h
)

set(WebKit2WebExtension_INSTALLED_HEADERS
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.h
)

set(WebKit2WebExtension_HEADER_TEMPLATES
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitConsoleMessage.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitFrame.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitScriptWorld.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitWebEditor.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitWebExtension.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitWebExtensionAutocleanups.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitWebHitTestResult.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitWebPage.h.in
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/webkit-web-extension.h.in
)

set(WebKitDOM_INSTALLED_HEADERS
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/webkitdomautocleanups.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/webkitdomdefines.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/webkitdom.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMAttr.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMBlob.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCDATASection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCharacterData.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMClientRect.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMClientRectList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMComment.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSRule.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSRuleList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSStyleDeclaration.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSStyleSheet.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSValue.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCustom.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCustomUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDeprecated.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentFragment.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentFragmentUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocument.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentType.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMImplementation.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMSelection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMTokenList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMWindow.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMWindowUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMElementUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMEventTarget.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMFile.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMFileList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAnchorElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAppletElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAreaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBaseElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBodyElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBRElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLButtonElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLCanvasElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLCollection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDirectoryElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDivElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDocument.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLElementUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLEmbedElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFieldSetElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFontElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFormElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFrameElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFrameSetElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHeadElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHeadingElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHRElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHtmlElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLIFrameElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLImageElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLInputElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLabelElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLegendElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLIElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLinkElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMapElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMarqueeElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMenuElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMetaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLModElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLObjectElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptGroupElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptionsCollection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLParagraphElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLParamElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLPreElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLQuoteElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLScriptElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLSelectElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLStyleElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableCaptionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableCellElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableColElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableRowElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableSectionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTextAreaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTitleElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLUListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMKeyboardEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMMediaList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMMouseEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNamedNodeMap.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeFilter.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNode.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeIterator.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMObject.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMProcessingInstruction.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMRange.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMRangeUnstable.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMStyleSheet.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMStyleSheetList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMText.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMTreeWalker.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMUIEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMWheelEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathExpression.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathNSResolver.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathResult.h
)

set(WebKitDOM_GTKDOC_HEADERS
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMAttr.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMBlob.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCDATASection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCharacterData.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMClientRect.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMClientRectList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMComment.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSRule.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSRuleList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSStyleDeclaration.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSStyleSheet.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCSSValue.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMCustom.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDeprecated.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentFragment.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocument.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDocumentType.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMImplementation.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMSelection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMTokenList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMDOMWindow.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMEventTarget.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMFile.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMFileList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAnchorElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAppletElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLAreaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBaseElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBodyElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLBRElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLButtonElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLCanvasElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLCollection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDirectoryElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDivElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLDocument.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLEmbedElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFieldSetElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFontElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFormElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFrameElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLFrameSetElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHeadElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHeadingElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHRElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLHtmlElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLIFrameElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLImageElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLInputElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLabelElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLegendElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLIElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLLinkElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMapElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMarqueeElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMenuElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLMetaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLModElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLObjectElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptGroupElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLOptionsCollection.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLParagraphElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLParamElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLPreElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLQuoteElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLScriptElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLSelectElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLStyleElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableCaptionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableCellElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableColElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableRowElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTableSectionElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTextAreaElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLTitleElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMHTMLUListElement.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMKeyboardEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMMediaList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMMouseEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNamedNodeMap.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeFilter.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNode.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeIterator.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMNodeList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMObject.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMProcessingInstruction.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMRange.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMStyleSheet.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMStyleSheetList.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMText.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMTreeWalker.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMUIEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMWheelEvent.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathExpression.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathNSResolver.h
    ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM/WebKitDOMXPathResult.h
)

# This is necessary because of a conflict between the GTK+ API WebKitVersion.h and one generated by WebCore.
list(INSERT WebKit_INCLUDE_DIRECTORIES 0
    "${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}"
    "${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-${WEBKITGTK_API_VERSION}"
    "${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension"
    "${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit"
    "${WebKit2Gtk_DERIVED_SOURCES_DIR}"
)

list(APPEND WebKit_INCLUDE_DIRECTORIES
    "${WEBKIT_DIR}/NetworkProcess/glib"
    "${WEBKIT_DIR}/NetworkProcess/gtk"
    "${WEBKIT_DIR}/NetworkProcess/soup"
    "${WEBKIT_DIR}/Platform/IPC/glib"
    "${WEBKIT_DIR}/Platform/IPC/unix"
    "${WEBKIT_DIR}/Platform/classifier"
    "${WEBKIT_DIR}/Platform/generic"
    "${WEBKIT_DIR}/Shared/API/c/gtk"
    "${WEBKIT_DIR}/Shared/API/glib"
    "${WEBKIT_DIR}/Shared/CoordinatedGraphics"
    "${WEBKIT_DIR}/Shared/CoordinatedGraphics/threadedcompositor"
    "${WEBKIT_DIR}/Shared/glib"
    "${WEBKIT_DIR}/Shared/gtk"
    "${WEBKIT_DIR}/Shared/linux"
    "${WEBKIT_DIR}/Shared/soup"
    "${WEBKIT_DIR}/UIProcess/API/C/cairo"
    "${WEBKIT_DIR}/UIProcess/API/C/glib"
    "${WEBKIT_DIR}/UIProcess/API/C/gtk"
    "${WEBKIT_DIR}/UIProcess/API/glib"
    "${WEBKIT_DIR}/UIProcess/API/gtk"
    "${WEBKIT_DIR}/UIProcess/CoordinatedGraphics"
    "${WEBKIT_DIR}/UIProcess/Inspector/glib"
    "${WEBKIT_DIR}/UIProcess/Inspector/gtk"
    "${WEBKIT_DIR}/UIProcess/geoclue"
    "${WEBKIT_DIR}/UIProcess/glib"
    "${WEBKIT_DIR}/UIProcess/gstreamer"
    "${WEBKIT_DIR}/UIProcess/gtk"
    "${WEBKIT_DIR}/UIProcess/linux"
    "${WEBKIT_DIR}/UIProcess/soup"
    "${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib"
    "${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/DOM"
    "${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk"
    "${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM"
    "${WEBKIT_DIR}/WebProcess/Inspector/gtk"
    "${WEBKIT_DIR}/WebProcess/glib"
    "${WEBKIT_DIR}/WebProcess/gtk"
    "${WEBKIT_DIR}/WebProcess/soup"
    "${WEBKIT_DIR}/WebProcess/WebCoreSupport/gtk"
    "${WEBKIT_DIR}/WebProcess/WebCoreSupport/soup"
    "${WEBKIT_DIR}/WebProcess/WebPage/CoordinatedGraphics"
    "${WEBKIT_DIR}/WebProcess/WebPage/gtk"
)

list(APPEND WebKit_SYSTEM_INCLUDE_DIRECTORIES
    ${ENCHANT_INCLUDE_DIRS}
    ${GIO_UNIX_INCLUDE_DIRS}
    ${GLIB_INCLUDE_DIRS}
    ${GSTREAMER_INCLUDE_DIRS}
    ${GSTREAMER_PBUTILS_INCLUDE_DIRS}
    ${GTK_INCLUDE_DIRS}
    ${LIBSOUP_INCLUDE_DIRS}
)

if (USE_WPE_RENDERER)
    list(APPEND WebKit_INCLUDE_DIRECTORIES
        "${WEBKIT_DIR}/WebProcess/WebPage/libwpe"
    )
    list(APPEND WebKit_SYSTEM_INCLUDE_DIRECTORIES
        ${WPEBACKEND_FDO_INCLUDE_DIRS}
    )
endif ()

if (USE_LIBNOTIFY)
list(APPEND WebKit_SYSTEM_INCLUDE_DIRECTORIES
    ${LIBNOTIFY_INCLUDE_DIRS}
)
endif ()

set(WebKitCommonIncludeDirectories ${WebKit_INCLUDE_DIRECTORIES})
set(WebKitCommonSystemIncludeDirectories ${WebKit_SYSTEM_INCLUDE_DIRECTORIES})

list(APPEND WebProcess_SOURCES
    WebProcess/EntryPoint/unix/WebProcessMain.cpp
)

list(APPEND NetworkProcess_SOURCES
    NetworkProcess/EntryPoint/unix/NetworkProcessMain.cpp
)

list(APPEND GPUProcess_SOURCES
    GPUProcess/EntryPoint/unix/GPUProcessMain.cpp
)

if (USE_WPE_RENDERER)
    list(APPEND WebKit_LIBRARIES
      WPE::libwpe
      ${WPEBACKEND_FDO_LIBRARIES}
    )
endif ()

if (GTK_UNIX_PRINT_FOUND)
    list(APPEND WebKit_LIBRARIES GTK::UnixPrint)
endif ()

if (LIBNOTIFY_FOUND)
    list(APPEND WebKit_PRIVATE_LIBRARIES
        ${LIBNOTIFY_LIBRARIES}
    )
endif ()

if (USE_LIBWEBRTC)
    list(APPEND WebKit_SYSTEM_INCLUDE_DIRECTORIES
        "${THIRDPARTY_DIR}/libwebrtc/Source/"
        "${THIRDPARTY_DIR}/libwebrtc/Source/webrtc"
    )
endif ()

if (ENABLE_MEDIA_STREAM)
    list(APPEND WebKit_SOURCES
        UIProcess/glib/UserMediaPermissionRequestManagerProxyGLib.cpp

        WebProcess/glib/UserMediaCaptureManager.cpp
    )
    list(APPEND WebKit_MESSAGES_IN_FILES
        WebProcess/glib/UserMediaCaptureManager
    )
endif ()

GENERATE_API_HEADERS(WebKit2GTK_HEADER_TEMPLATES
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit
    WebKit2GTK_INSTALLED_HEADERS
    "-DPLATFORM(GTK)=1"
    "-DPLATFORM(WPE)=0"
    "-DUSE(GTK4)=$<BOOL:${USE_GTK4}>"
)

GENERATE_API_HEADERS(WebKit2WebExtension_HEADER_TEMPLATES
    ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit
    WebKit2WebExtension_INSTALLED_HEADERS
    "-DPLATFORM(GTK)=1"
    "-DPLATFORM(WPE)=0"
    "-DUSE(GTK4)=$<BOOL:${USE_GTK4}>"
)

# To generate WebKitEnumTypes.h we want to use all installed headers, except WebKitEnumTypes.h itself.
set(WebKit2GTK_ENUM_GENERATION_HEADERS ${WebKit2GTK_INSTALLED_HEADERS})
list(REMOVE_ITEM WebKit2GTK_ENUM_GENERATION_HEADERS ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.h)
add_custom_command(
    OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.h
           ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.cpp
    DEPENDS ${WebKit2GTK_ENUM_GENERATION_HEADERS}

    COMMAND glib-mkenums --template ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitEnumTypes.h.template ${WebKit2GTK_ENUM_GENERATION_HEADERS} | sed s/web_kit/webkit/ | sed s/WEBKIT_TYPE_KIT/WEBKIT_TYPE/ > ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.h

    COMMAND glib-mkenums --template ${WEBKIT_DIR}/UIProcess/API/gtk/WebKitEnumTypes.cpp.template ${WebKit2GTK_ENUM_GENERATION_HEADERS} | sed s/web_kit/webkit/ > ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitEnumTypes.cpp
    VERBATIM
)

set(WebKit2GTK_WEB_PROCESS_ENUM_GENERATION_HEADERS ${WebKit2WebExtension_INSTALLED_HEADERS})
list(REMOVE_ITEM WebKit2GTK_WEB_PROCESS_ENUM_GENERATION_HEADERS ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.h)
add_custom_command(
    OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.h
           ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.cpp
    DEPENDS ${WebKit2GTK_WEB_PROCESS_ENUM_GENERATION_HEADERS}

    COMMAND glib-mkenums --template ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/WebKitWebProcessEnumTypes.h.template ${WebKit2GTK_WEB_PROCESS_ENUM_GENERATION_HEADERS} | sed s/web_kit/webkit/ | sed s/WEBKIT_TYPE_KIT/WEBKIT_TYPE/ > ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.h

    COMMAND glib-mkenums --template ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/WebKitWebProcessEnumTypes.cpp.template ${WebKit2GTK_WEB_PROCESS_ENUM_GENERATION_HEADERS} | sed s/web_kit/webkit/ > ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitWebProcessEnumTypes.cpp
    VERBATIM
)

WEBKIT_BUILD_INSPECTOR_GRESOURCES(${WebKit2Gtk_DERIVED_SOURCES_DIR})

set(WebKitResources "")
list(APPEND WebKitResources "<file alias=\"css/gtk-theme.css\">gtk-theme.css</file>\n")
list(APPEND WebKitResources "<file alias=\"images/missingImage\">missingImage.png</file>\n")
list(APPEND WebKitResources "<file alias=\"images/missingImage@2x\">missingImage@2x.png</file>\n")
list(APPEND WebKitResources "<file alias=\"images/missingImage@3x\">missingImage@3x.png</file>\n")
list(APPEND WebKitResources "<file alias=\"images/panIcon\">panIcon.png</file>\n")
list(APPEND WebKitResources "<file alias=\"images/textAreaResizeCorner\">textAreaResizeCorner.png</file>\n")
list(APPEND WebKitResources "<file alias=\"images/textAreaResizeCorner@2x\">textAreaResizeCorner@2x.png</file>\n")

if (ENABLE_WEB_AUDIO)
    list(APPEND WebKitResources
        "        <file alias=\"audio/Composite\">Composite.wav</file>\n"
    )
endif ()

file(WRITE ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.xml
    "<?xml version=1.0 encoding=UTF-8?>\n"
    "<gresources>\n"
    "    <gresource prefix=\"/org/webkitgtk/resources\">\n"
    ${WebKitResources}
    "    </gresource>\n"
    "</gresources>\n"
)

add_custom_command(
    OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.c ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.deps
    DEPENDS ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.xml
    DEPFILE ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.deps
    COMMAND glib-compile-resources --generate --sourcedir=${CMAKE_SOURCE_DIR}/Source/WebCore/Resources --sourcedir=${CMAKE_SOURCE_DIR}/Source/WebCore/platform/audio/resources --sourcedir=${CMAKE_SOURCE_DIR}/Source/WebKit/Resources/gtk --target=${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.c --dependency-file=${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.deps ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitResourcesGResourceBundle.xml
    VERBATIM
)

if (ENABLE_WAYLAND_TARGET)
    # Wayland protocol extension.
    add_custom_command(
        OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitWaylandClientProtocol.c
        DEPENDS ${WEBKIT_DIR}/Shared/gtk/WebKitWaylandProtocol.xml
        COMMAND ${WAYLAND_SCANNER} server-header ${WEBKIT_DIR}/Shared/gtk/WebKitWaylandProtocol.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitWaylandServerProtocol.h
        COMMAND ${WAYLAND_SCANNER} client-header ${WEBKIT_DIR}/Shared/gtk/WebKitWaylandProtocol.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitWaylandClientProtocol.h
        COMMAND ${WAYLAND_SCANNER} private-code ${WEBKIT_DIR}/Shared/gtk/WebKitWaylandProtocol.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/WebKitWaylandClientProtocol.c
        VERBATIM
    )

    add_custom_command(
        OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/pointer-constraints-unstable-v1-protocol.c
        DEPENDS ${WAYLAND_PROTOCOLS_DATADIR}/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
        COMMAND ${WAYLAND_SCANNER} private-code ${WAYLAND_PROTOCOLS_DATADIR}/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/pointer-constraints-unstable-v1-protocol.c
        COMMAND ${WAYLAND_SCANNER} client-header ${WAYLAND_PROTOCOLS_DATADIR}/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/pointer-constraints-unstable-v1-client-protocol.h
        VERBATIM
    )

    add_custom_command(
        OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/relative-pointer-unstable-v1-protocol.c
        DEPENDS ${WAYLAND_PROTOCOLS_DATADIR}/unstable/relative-pointer/relative-pointer-unstable-v1.xml
        COMMAND ${WAYLAND_SCANNER} private-code ${WAYLAND_PROTOCOLS_DATADIR}/unstable/relative-pointer/relative-pointer-unstable-v1.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/relative-pointer-unstable-v1-protocol.c
        COMMAND ${WAYLAND_SCANNER} client-header ${WAYLAND_PROTOCOLS_DATADIR}/unstable/relative-pointer/relative-pointer-unstable-v1.xml ${WebKit2Gtk_DERIVED_SOURCES_DIR}/relative-pointer-unstable-v1-client-protocol.h
        VERBATIM
    )
endif ()

# Commands for building the built-in injected bundle.
add_library(webkit2gtkinjectedbundle MODULE "${WEBKIT_DIR}/WebProcess/InjectedBundle/API/glib/WebKitInjectedBundleMain.cpp")
ADD_WEBKIT_PREFIX_HEADER(webkit2gtkinjectedbundle)
target_link_libraries(webkit2gtkinjectedbundle WebKit)

target_include_directories(webkit2gtkinjectedbundle PRIVATE
    $<TARGET_PROPERTY:WebKit,INCLUDE_DIRECTORIES>
    "${DERIVED_SOURCES_DIR}/InjectedBundle"
    "${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}"
    "${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-${WEBKITGTK_API_VERSION}"
    "${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit"
)

target_include_directories(webkit2gtkinjectedbundle SYSTEM PRIVATE
    ${WebKit_SYSTEM_INCLUDE_DIRECTORIES}
)

if (COMPILER_IS_GCC_OR_CLANG)
    WEBKIT_ADD_TARGET_CXX_FLAGS(webkit2gtkinjectedbundle -Wno-unused-parameter)
endif ()

install(TARGETS webkit2gtkinjectedbundle
        DESTINATION "${LIB_INSTALL_DIR}/webkit2gtk-${WEBKITGTK_API_VERSION}/injected-bundle"
)
install(FILES "${CMAKE_BINARY_DIR}/Source/WebKit/webkit2gtk-${WEBKITGTK_API_VERSION}.pc"
              "${CMAKE_BINARY_DIR}/Source/WebKit/webkit2gtk-web-extension-${WEBKITGTK_API_VERSION}.pc"
        DESTINATION "${LIB_INSTALL_DIR}/pkgconfig"
)
install(FILES ${WebKit2GTK_INSTALLED_HEADERS}
              ${WebKit2WebExtension_INSTALLED_HEADERS}
        DESTINATION "${WEBKITGTK_HEADER_INSTALL_DIR}/webkit2"
)
install(FILES ${WebKitDOM_INSTALLED_HEADERS}
        DESTINATION "${WEBKITGTK_HEADER_INSTALL_DIR}/webkitdom"
)

add_custom_target(WebKit-forwarding-headers
    COMMAND ${PERL_EXECUTABLE} ${WEBKIT_DIR}/Scripts/generate-forwarding-headers.pl --include-path ${WEBKIT_DIR} --output ${FORWARDING_HEADERS_DIR} --platform gtk --platform soup
)

# These symbolic link allows includes like #include <webkit2/WebkitWebView.h> which simulates installed headers.
add_custom_command(
    OUTPUT ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2
    DEPENDS ${WEBKIT_DIR}/UIProcess/API/gtk
    COMMAND ln -n -s -f ${WEBKIT_DIR}/UIProcess/API/gtk ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2
)
add_custom_command(
    OUTPUT ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit2
    DEPENDS ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit
    COMMAND ln -n -s -f ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit2
)
add_custom_command(
    OUTPUT ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkit2
    DEPENDS ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk
    COMMAND ln -n -s -f ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkit2
)
add_custom_command(
    OUTPUT ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkitdom
    DEPENDS ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM
    COMMAND ln -n -s -f ${WEBKIT_DIR}/WebProcess/InjectedBundle/API/gtk/DOM ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkitdom
)
add_custom_target(WebKit-fake-api-headers
    DEPENDS ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2
            ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit2
            ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkit2
            ${WebKit2Gtk_FRAMEWORK_HEADERS_DIR}/webkit2gtk-webextension/webkitdom
)

list(APPEND WebKit_DEPENDENCIES
     WebKit-fake-api-headers
     WebKit-forwarding-headers
)

GI_INTROSPECT(WebKit2 ${WEBKITGTK_API_VERSION} webkit2/webkit2.h
    TARGET WebKit
    PACKAGE webkit2gtk
    IDENTIFIER_PREFIX WebKit
    SYMBOL_PREFIX webkit
    DEPENDENCIES
        JavaScriptCore
        Gtk-${GTK_API_VERSION}.0:${GTK_PKGCONFIG_PACKAGE}
        Soup-${SOUP_API_VERSION}:libsoup-${SOUP_API_VERSION}
    SOURCES
        ${WebKit2GTK_INSTALLED_HEADERS}
        Shared/API/glib
        UIProcess/API/glib
        UIProcess/API/gtk
    NO_IMPLICIT_SOURCES
)
GI_DOCGEN(WebKit2 gtk/webkit2gtk.toml.in
    CONTENT_TEMPLATES gtk/urlmap.js
)

GI_INTROSPECT(WebKit2WebExtension ${WEBKITGTK_API_VERSION} webkit2/webkit-web-extension.h
    TARGET WebKit
    PACKAGE webkit2gtk-web-extension
    IDENTIFIER_PREFIX WebKit
    SYMBOL_PREFIX webkit
    DEPENDENCIES
        JavaScriptCore
        Gtk-${GTK_API_VERSION}.0:${GTK_PKGCONFIG_PACKAGE}
        Soup-${SOUP_API_VERSION}:libsoup-${SOUP_API_VERSION}
    SOURCES
        ${WebKitDOM_INSTALLED_HEADERS}
        ${WebKit2WebExtension_INSTALLED_HEADERS}
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitContextMenu.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitContextMenuActions.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitContextMenuItem.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitHitTestResult.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitUserMessage.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitURIRequest.h
        ${WebKit2Gtk_DERIVED_SOURCES_DIR}/webkit/WebKitURIResponse.h
        Shared/API/glib/WebKitContextMenu.cpp
        Shared/API/glib/WebKitContextMenuItem.cpp
        Shared/API/glib/WebKitHitTestResult.cpp
        Shared/API/glib/WebKitUserMessage.cpp
        Shared/API/glib/WebKitURIRequest.cpp
        Shared/API/glib/WebKitURIResponse.cpp
        WebProcess/InjectedBundle/API/glib
        WebProcess/InjectedBundle/API/glib/DOM
    NO_IMPLICIT_SOURCES
)
GI_DOCGEN(WebKit2WebExtension gtk/webkit2gtk-webextension.toml.in
    CONTENT_TEMPLATES gtk/urlmap.js
)
