/*
 * Copyright (C) 2018-2021 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "CSSParserContext.h"

#include "CSSImageValue.h"
#include "DeprecatedGlobalSettings.h"
#include "Document.h"
#include "DocumentLoader.h"
#include "Page.h"
#include "Settings.h"
#include <wtf/NeverDestroyed.h>

namespace WebCore {

const CSSParserContext& strictCSSParserContext()
{
    static MainThreadNeverDestroyed<CSSParserContext> strictContext(HTMLStandardMode);
    return strictContext;
}

CSSParserContext::CSSParserContext(CSSParserMode mode, const URL& baseURL)
    : baseURL(baseURL)
    , mode(mode)
{
    // FIXME: We should turn all of the features on from their WebCore Settings defaults.
    if (mode == UASheetMode) {
        individualTransformPropertiesEnabled = true;
        focusVisibleEnabled = true;
        inputSecurityEnabled = true;
        containmentEnabled = true;
#if ENABLE(CSS_TRANSFORM_STYLE_OPTIMIZED_3D)
        transformStyleOptimized3DEnabled = true;
#endif
    }
}

#if ENABLE(OVERFLOW_SCROLLING_TOUCH)
static bool shouldEnableLegacyOverflowScrollingTouch(const Document& document)
{
    // The legacy -webkit-overflow-scrolling: touch behavior may have been disabled through the website policy,
    // in that case we want to disable the legacy behavior regardless of what the setting says.
    if (auto* loader = document.loader()) {
        if (loader->legacyOverflowScrollingTouchPolicy() == LegacyOverflowScrollingTouchPolicy::Disable)
            return false;
    }
    return document.settings().legacyOverflowScrollingTouchEnabled();
}
#endif

CSSParserContext::CSSParserContext(const Document& document, const URL& sheetBaseURL, const String& charset)
    : baseURL { sheetBaseURL.isNull() ? document.baseURL() : sheetBaseURL }
    , charset { charset }
    , mode { document.inQuirksMode() ? HTMLQuirksMode : HTMLStandardMode }
    , isHTMLDocument { document.isHTMLDocument() }
    , hasDocumentSecurityOrigin { sheetBaseURL.isNull() || document.securityOrigin().canRequest(baseURL) }
    , useSystemAppearance { document.page() ? document.page()->useSystemAppearance() : false }
    , accentColorEnabled { document.settings().accentColorEnabled() }
    , aspectRatioEnabled { document.settings().aspectRatioEnabled() }
    , colorContrastEnabled { document.settings().cssColorContrastEnabled() }
    , colorFilterEnabled { document.settings().colorFilterEnabled() }
    , colorMixEnabled { document.settings().cssColorMixEnabled() }
    , constantPropertiesEnabled { document.settings().constantPropertiesEnabled() }
    , containmentEnabled { document.settings().cssContainmentEnabled() }
    , counterStyleAtRulesEnabled { document.settings().cssCounterStyleAtRulesEnabled() }
    , counterStyleAtRuleImageSymbolsEnabled { document.settings().cssCounterStyleAtRuleImageSymbolsEnabled() }
    , cssColor4 { document.settings().cssColor4() }
    , individualTransformPropertiesEnabled { document.settings().cssIndividualTransformPropertiesEnabled() }
#if ENABLE(OVERFLOW_SCROLLING_TOUCH)
    , legacyOverflowScrollingTouchEnabled { shouldEnableLegacyOverflowScrollingTouch(document) }
#endif
    , overscrollBehaviorEnabled { document.settings().overscrollBehaviorEnabled() }
    , relativeColorSyntaxEnabled { document.settings().cssRelativeColorSyntaxEnabled() }
    , scrollBehaviorEnabled { document.settings().CSSOMViewSmoothScrollingEnabled() }
    , springTimingFunctionEnabled { document.settings().springTimingFunctionEnabled() }
#if ENABLE(TEXT_AUTOSIZING)
    , textAutosizingEnabled { document.settings().textAutosizingEnabled() }
#endif
#if ENABLE(CSS_TRANSFORM_STYLE_OPTIMIZED_3D)
    , transformStyleOptimized3DEnabled { document.settings().cssTransformStyleOptimized3DEnabled() }
#endif
    , useLegacyBackgroundSizeShorthandBehavior { document.settings().useLegacyBackgroundSizeShorthandBehavior() }
    , focusVisibleEnabled { document.settings().focusVisibleEnabled() }
    , hasPseudoClassEnabled { document.settings().hasPseudoClassEnabled() }
    , cascadeLayersEnabled { document.settings().cssCascadeLayersEnabled() }
    , containerQueriesEnabled { document.settings().cssContainerQueriesEnabled() }
    , overflowClipEnabled { document.settings().overflowClipEnabled() }
    , gradientPremultipliedAlphaInterpolationEnabled { document.settings().cssGradientPremultipliedAlphaInterpolationEnabled() }
    , gradientInterpolationColorSpacesEnabled { document.settings().cssGradientInterpolationColorSpacesEnabled() }
    , inputSecurityEnabled { document.settings().cssInputSecurityEnabled() }
    , subgridEnabled { document.settings().subgridEnabled() }
    , containIntrinsicSizeEnabled { document.settings().cssContainIntrinsicSizeEnabled() }
    , motionPathEnabled { document.settings().cssMotionPathEnabled() }
    , cssTextAlignLastEnabled { document.settings().cssTextAlignLastEnabled() }
    , cssTextJustifyEnabled { document.settings().cssTextJustifyEnabled() }
#if ENABLE(ATTACHMENT_ELEMENT)
    , attachmentEnabled { DeprecatedGlobalSettings::attachmentElementEnabled() }
#endif
{
}

bool operator==(const CSSParserContext& a, const CSSParserContext& b)
{
    return a.baseURL == b.baseURL
        && a.charset == b.charset
        && a.mode == b.mode
        && a.enclosingRuleType == b.enclosingRuleType
        && a.isHTMLDocument == b.isHTMLDocument
        && a.hasDocumentSecurityOrigin == b.hasDocumentSecurityOrigin
        && a.isContentOpaque == b.isContentOpaque
        && a.useSystemAppearance == b.useSystemAppearance
        && a.accentColorEnabled == b.accentColorEnabled
        && a.aspectRatioEnabled == b.aspectRatioEnabled
        && a.colorContrastEnabled == b.colorContrastEnabled
        && a.colorFilterEnabled == b.colorFilterEnabled
        && a.colorMixEnabled == b.colorMixEnabled
        && a.constantPropertiesEnabled == b.constantPropertiesEnabled
        && a.containmentEnabled == b.containmentEnabled
        && a.counterStyleAtRulesEnabled == b.counterStyleAtRulesEnabled
        && a.counterStyleAtRuleImageSymbolsEnabled == b.counterStyleAtRuleImageSymbolsEnabled
        && a.cssColor4 == b.cssColor4
        && a.individualTransformPropertiesEnabled == b.individualTransformPropertiesEnabled
#if ENABLE(OVERFLOW_SCROLLING_TOUCH)
        && a.legacyOverflowScrollingTouchEnabled == b.legacyOverflowScrollingTouchEnabled
#endif
        && a.overscrollBehaviorEnabled == b.overscrollBehaviorEnabled
        && a.relativeColorSyntaxEnabled == b.relativeColorSyntaxEnabled
        && a.scrollBehaviorEnabled == b.scrollBehaviorEnabled
        && a.springTimingFunctionEnabled == b.springTimingFunctionEnabled
#if ENABLE(TEXT_AUTOSIZING)
        && a.textAutosizingEnabled == b.textAutosizingEnabled
#endif
#if ENABLE(CSS_TRANSFORM_STYLE_OPTIMIZED_3D)
        && a.transformStyleOptimized3DEnabled == b.transformStyleOptimized3DEnabled
#endif
        && a.useLegacyBackgroundSizeShorthandBehavior == b.useLegacyBackgroundSizeShorthandBehavior
        && a.focusVisibleEnabled == b.focusVisibleEnabled
        && a.hasPseudoClassEnabled == b.hasPseudoClassEnabled
        && a.cascadeLayersEnabled == b.cascadeLayersEnabled
        && a.containerQueriesEnabled == b.containerQueriesEnabled
        && a.overflowClipEnabled == b.overflowClipEnabled
        && a.gradientPremultipliedAlphaInterpolationEnabled == b.gradientPremultipliedAlphaInterpolationEnabled
        && a.gradientInterpolationColorSpacesEnabled == b.gradientInterpolationColorSpacesEnabled
        && a.inputSecurityEnabled == b.inputSecurityEnabled
#if ENABLE(ATTACHMENT_ELEMENT)
        && a.attachmentEnabled == b.attachmentEnabled
#endif
        && a.subgridEnabled == b.subgridEnabled
        && a.containIntrinsicSizeEnabled == b.containIntrinsicSizeEnabled
        && a.motionPathEnabled == b.motionPathEnabled
        && a.cssTextAlignLastEnabled == b.cssTextAlignLastEnabled
        && a.cssTextJustifyEnabled == b.cssTextJustifyEnabled
    ;
}

void add(Hasher& hasher, const CSSParserContext& context)
{
    uint64_t bits = context.isHTMLDocument                  << 0
        | context.hasDocumentSecurityOrigin                 << 1
        | context.isContentOpaque                           << 2
        | context.useSystemAppearance                       << 3
        | context.aspectRatioEnabled                        << 4
        | context.colorContrastEnabled                      << 5
        | context.colorFilterEnabled                        << 6
        | context.colorMixEnabled                           << 7
        | context.constantPropertiesEnabled                 << 8
        | context.containmentEnabled                        << 9
        | context.cssColor4                                 << 10
        | context.individualTransformPropertiesEnabled      << 11
#if ENABLE(OVERFLOW_SCROLLING_TOUCH)
        | context.legacyOverflowScrollingTouchEnabled       << 12
#endif
        | context.overscrollBehaviorEnabled                 << 13
        | context.relativeColorSyntaxEnabled                << 14
        | context.scrollBehaviorEnabled                     << 15
        | context.springTimingFunctionEnabled               << 16
#if ENABLE(TEXT_AUTOSIZING)
        | context.textAutosizingEnabled                     << 17
#endif
#if ENABLE(CSS_TRANSFORM_STYLE_OPTIMIZED_3D)
        | context.transformStyleOptimized3DEnabled          << 18
#endif
        | context.useLegacyBackgroundSizeShorthandBehavior  << 19
        | context.focusVisibleEnabled                       << 20
        | context.hasPseudoClassEnabled                     << 21
        | context.cascadeLayersEnabled                      << 22
        | context.containerQueriesEnabled                   << 23
        | context.overflowClipEnabled                       << 24
        | context.gradientPremultipliedAlphaInterpolationEnabled << 25
        | context.gradientInterpolationColorSpacesEnabled   << 27
#if ENABLE(ATTACHMENT_ELEMENT)
        | context.attachmentEnabled                         << 28
#endif
        | context.accentColorEnabled                        << 29
        | context.inputSecurityEnabled                      << 30
        | context.subgridEnabled                            << 31
        | (uint64_t)context.containIntrinsicSizeEnabled     << 32
        | (uint64_t)context.motionPathEnabled               << 33
        | (uint64_t)context.cssTextAlignLastEnabled         << 34
        | (uint64_t)context.cssTextJustifyEnabled           << 35
        | (uint64_t)context.mode                            << 36; // This is multiple bits, so keep it last.

    add(hasher, context.baseURL, context.charset, bits);
}

bool CSSParserContext::isPropertyRuntimeDisabled(CSSPropertyID property) const
{
    switch (property) {
    case CSSPropertyAdditiveSymbols:
    case CSSPropertyFallback:
    case CSSPropertyPad:
    case CSSPropertySymbols:
    case CSSPropertyNegative:
    case CSSPropertyPrefix:
    case CSSPropertyRange:
    case CSSPropertySuffix:
    case CSSPropertySystem:
        return !counterStyleAtRulesEnabled;
    case CSSPropertyAccentColor:
        return !accentColorEnabled;
    case CSSPropertyAspectRatio:
        return !aspectRatioEnabled;
    case CSSPropertyContain:
        return !containmentEnabled;
    case CSSPropertyAppleColorFilter:
        return !colorFilterEnabled;
    case CSSPropertyInputSecurity:
        return !inputSecurityEnabled;
    case CSSPropertyTranslate:
    case CSSPropertyRotate:
    case CSSPropertyScale:
        return !individualTransformPropertiesEnabled;
    case CSSPropertyOverscrollBehavior:
    case CSSPropertyOverscrollBehaviorBlock:
    case CSSPropertyOverscrollBehaviorInline:
    case CSSPropertyOverscrollBehaviorX:
    case CSSPropertyOverscrollBehaviorY:
        return !overscrollBehaviorEnabled;
    case CSSPropertyScrollBehavior:
        return !scrollBehaviorEnabled;
#if ENABLE(TEXT_AUTOSIZING) && !PLATFORM(IOS_FAMILY)
    case CSSPropertyWebkitTextSizeAdjust:
        return !textAutosizingEnabled;
#endif
#if ENABLE(OVERFLOW_SCROLLING_TOUCH)
    case CSSPropertyWebkitOverflowScrolling:
        return !legacyOverflowScrollingTouchEnabled;
#endif
    case CSSPropertyContainIntrinsicSize:
    case CSSPropertyContainIntrinsicHeight:
    case CSSPropertyContainIntrinsicWidth:
    case CSSPropertyContainIntrinsicBlockSize:
    case CSSPropertyContainIntrinsicInlineSize:
        return !containIntrinsicSizeEnabled;
    case CSSPropertyOffset:
    case CSSPropertyOffsetPath:
    case CSSPropertyOffsetDistance:
    case CSSPropertyOffsetPosition:
    case CSSPropertyOffsetAnchor:
    case CSSPropertyOffsetRotate:
        return !motionPathEnabled;
    case CSSPropertyTextAlignLast:
        return !cssTextAlignLastEnabled;
    case CSSPropertyTextJustify:
        return !cssTextJustifyEnabled;
    default:
        return false;
    }
}

ResolvedURL CSSParserContext::completeURL(const String& string) const
{
    auto result = [&] () -> ResolvedURL {
        // See also Document::completeURL(const String&)
        if (string.isNull())
            return { };

        if (CSSValue::isCSSLocalURL(string))
            return { string, URL { string } };

        if (charset.isEmpty())
            return { string, { baseURL, string } };
        auto encodingForURLParsing = PAL::TextEncoding { charset }.encodingForFormSubmissionOrURLParsing();
        return { string, { baseURL, string, encodingForURLParsing == PAL::UTF8Encoding() ? nullptr : &encodingForURLParsing } };
    }();

    if (mode == WebVTTMode && !result.resolvedURL.protocolIsData())
        return { };

    return result;
}

}
