#! /usr/bin/env perl
#
#   This file is part of the WebKit project
#
#   Copyright (C) 1999 Waldo Bastian (bastian@kde.org)
#   Copyright (C) 2007-2018 Apple Inc. All rights reserved.
#   Copyright (C) 2008 Nokia Corporation and/or its subsidiary(-ies)
#   Copyright (C) 2010 Andras Becsi (abecsi@inf.u-szeged.hu), University of Szeged
#   Copyright (C) 2013 Google Inc. All rights reserved.
#
#   This library is free software; you can redistribute it and/or
#   modify it under the terms of the GNU Library General Public
#   License as published by the Free Software Foundation; either
#   version 2 of the License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   Library General Public License for more details.
#
#   You should have received a copy of the GNU Library General Public License
#   along with this library; see the file COPYING.LIB.  If not, write to
#   the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.

use strict;
use warnings;

use English;
use File::Spec;
use Getopt::Long;
use JSON::PP;

sub isLogical;
sub skippedFromComputedStyle;
sub isPropertyEnabled($$);
sub addProperty($$);
sub removeInactiveCodegenProperties($$);

my $inputFile = "CSSProperties.json";

my $defines = "";
my $gperf;
GetOptions('defines=s' => \$defines,
           'gperf-executable=s' => \$gperf);

my $input;
{
    local $INPUT_RECORD_SEPARATOR; # No separator; read through until end-of-file.
    open(JSON, "<", $inputFile) or die "Cannot open $inputFile.\n";
    $input = <JSON>;
    close(JSON);
}

my $jsonDecoder = JSON::PP->new->utf8;
my $jsonHashRef = $jsonDecoder->decode($input);
my $propertiesHashRef = $jsonHashRef->{properties};
my @allNames = sort keys(%$propertiesHashRef);
die "We've reached more than 1024 CSS properties, please make sure to update CSSProperty/StylePropertyMetadata accordingly" if @allNames > 1024;

my %defines = map { $_ => 1 } split(/ /, $defines);

my @names;
my @internalProperties;
my %runtimeFlags;
my %settingsFlags;
my $numPredefinedProperties = 2;
my %nameIsColorProperty;
my %nameIsDescriptorOnly;
my %nameIsTopPriority;
my %nameIsHighPriority;
my %nameIsDeferred;
my %nameIsInherited;
my %namePriorityShouldSink;
my %logicalPropertyGroups;
my %logicalPropertyGroupResolvers = (
    "logical" => {
        # Order matches LogicalBoxAxis enum in Source/WebCore/platform/text/WritingMode.h.
        "axis" => ["inline", "block"],
        # Order matches LogicalBoxSide enum in Source/WebCore/platform/text/WritingMode.h.
        "side" => ["block-start", "inline-end", "block-end", "inline-start"],
        # Order matches LogicalBoxCorner enum in Source/WebCore/platform/text/WritingMode.h.
        "corner" => ["start-start", "start-end", "end-start", "end-end"],
    },
    "physical" => {
        # Order matches BoxAxis enum in Source/WebCore/platform/text/WritingMode.h.
        "axis" => ["horizontal", "vertical"],
        # Order matches BoxSide enum in Source/WebCore/platform/text/WritingMode.h.
        "side" => ["top", "right", "bottom", "left"],
        # Order matches BoxCorner enum in Source/WebCore/platform/text/WritingMode.h.
        "corner" => ["top-left", "top-right", "bottom-right", "bottom-left"],
    },
);
my %propertiesWithStyleBuilderOptions;
my %styleBuilderOptions = (
    "animatable" => 1, # Defined in Source/WebCore/style/StyleBuilderConverter.h
    "auto-functions" => 1,
    "computable" => 1,
    "conditional-converter" => 1,
    "converter" => 1,
    "custom" => 1,
    "fast-path-inherited" => 1,
    "fill-layer-property" => 1,
    "font-property" => 1,
    "getter" => 1,
    "initial" => 1,
    "longhands" => 1,
    "name-for-methods" => 1,
    "svg" => 1,
    "skip-builder" => 1,
    "setter" => 1,
    "visited-link-color-support" => 1,
);
my %nameToId;
my %nameToAliases;
my %synonyms;
my %namesToSynonyms;
my %relatedProperty;

for my $name (@allNames) {
    my $value = $propertiesHashRef->{$name};
    my $valueType = ref($value);
    
    if ($valueType eq "HASH") {
        removeInactiveCodegenProperties($name, \%$value);
        if (isPropertyEnabled($name, $value)) {
            addProperty($name, $value);
        }
    } else {
        die "$name does not have a supported value type. Only dictionary types are supported.";
    }
}

while (my ($groupName, $logicalPropertyGroup) = each %logicalPropertyGroups) {
    my $kind = $logicalPropertyGroup->{"kind"};
    while (my ($logic, $resolversForLogic) = each %logicalPropertyGroupResolvers) {
        my $properties = $logicalPropertyGroup->{$logic};
        if (!$properties) {
            die "Logical property group \"$groupName\" has no \"$logic\" property.";
        }
        for my $resolver (@{ $resolversForLogic->{$kind} }) {
            if (!$properties->{$resolver}) {
                die "Logical property group \"$groupName\" requires a \"$resolver\" property.";
            }
        }
    }
}

sub matchEnableFlags($)
{
    my ($enable_flag) = @_;
    
    if (exists($defines{$enable_flag})) {
        return 1;
    }

    if (substr($enable_flag, 0, 1) eq "!" && !exists($defines{substr($enable_flag, 1)})) {
        return 1;
    }
    
    return 0;
}

sub removeInactiveCodegenProperties($$)
{
    my ($name, $propertyValue) = @_;

    if (!exists($propertyValue->{"codegen-properties"})) {
        return;
    }
    
    my $codegen_properties = $propertyValue->{"codegen-properties"};
    my $valueType = ref($codegen_properties);

    if ($valueType ne "ARRAY") {
        return;
    }

    # Pick one based on "enable-if"
    my $matching_codegen_options;
    foreach my $entry (@{$codegen_properties}) {
        if (!exists($entry->{"enable-if"})) {
            print "Found 'codegen-properties' array with an unconditional entry under '$name'. This is probably unintentional.\n";
            $matching_codegen_options = $entry;
            last;
        }

        my $enable_flags = $entry->{"enable-if"};
        if (matchEnableFlags($enable_flags)) {
            $matching_codegen_options = $entry;
            last;
        }

        $matching_codegen_options = $entry;
    }
    
    $propertyValue->{"codegen-properties"} = $matching_codegen_options;
}

sub skippedFromComputedStyle
{
  my $name = shift;
  my $options = $propertiesWithStyleBuilderOptions{$name};

  if (grep { $_ eq $name } @internalProperties) {
    die "$name can't be computable since it's internal" if $options->{"computable"};
    return 1;
  }

  return !$options->{"computable"} if exists($options->{"computable"});

  return 1 if exists($options->{"skip-builder"}) and not isLogical($name);

  if (exists($options->{"longhands"})) {
    my @longhands = @{$options->{"longhands"}};
    # Skip properties if they have a non-internal longhand property.
    foreach my $longhand (@longhands) {
      return 1 if !skippedFromComputedStyle($longhand);
    }
  }

  return 0;
}


sub isLogical
{
    my $name = shift;
    my $logicalPropertyGroup = $propertiesHashRef->{$name}->{"codegen-properties"}->{"logical-property-group"};

    if (!$logicalPropertyGroup) {
        return 0;
    }

    my $resolver = $logicalPropertyGroup->{"resolver"};
    for my $logicalResolvers (values %{ $logicalPropertyGroupResolvers{"logical"} }) {
        for my $logicalResolver (@{ $logicalResolvers }) {
            if ($resolver eq $logicalResolver) {
                return 1;
            }
        }
    }

    return 0;
}

sub isPropertyEnabled($$)
{
    my ($name, $propertyValue) = @_;

    if (!exists($propertyValue->{"codegen-properties"})) {
        return 1;
    }
    
    my $codegen_properties = $propertyValue->{"codegen-properties"};
    if ($codegen_properties->{"skip-codegen"}) {
        return 0;
    }

    if (!exists($codegen_properties->{"enable-if"})) {
        return 1;
    }

    return matchEnableFlags($codegen_properties->{"enable-if"});
}

sub nameToId
{
    my $name = shift;
    $name =~ s/(^[^-])|-(.)/uc($1||$2)/ge;
    return $name;
}

sub addProperty($$)
{
    my ($name, $optionsHashRef) = @_;

    push @names, $name;

    $nameToId{$name} = nameToId($name);

    for my $optionName (keys %{$optionsHashRef}) {
        if ($optionName eq "codegen-properties") {
            my $codegenProperties = $optionsHashRef->{"codegen-properties"};
            for my $codegenOptionName (keys %$codegenProperties) {
                if ($codegenOptionName eq "enable-if") {
                    next;
                } elsif ($codegenOptionName eq "skip-codegen") {
                    next;
                } elsif ($codegenOptionName eq "comment") {
                    next;
                } elsif ($codegenOptionName eq "top-priority") {
                    die "$name has top priority, but no comment to justify" if not (exists $codegenProperties->{"comment"});
                    die "$name is a shorthand, but has top-priority" if exists $codegenProperties->{"longhands"};
                    $nameIsTopPriority{$name} = 1;
                } elsif ($codegenOptionName eq "high-priority") {
                    die "$name can't have conflicting top/high priority" if !!$nameIsTopPriority{$name};
                    die "$name is a shorthand, but has high-priority" if exists $codegenProperties->{"longhands"};
                    $nameIsHighPriority{$name} = 1;
                } elsif ($codegenOptionName eq "sink-priority") {
                    die "$name is a shorthand, but has sink-priority" if exists $codegenProperties->{"longhands"};
                    $namePriorityShouldSink{$name} = 1;
                } elsif ($codegenOptionName eq "related-property") {
                    $nameIsDeferred{$name} = 1;
                    $relatedProperty{$name} = $codegenProperties->{"related-property"}
                } elsif ($codegenOptionName eq "aliases") {
                    $nameToAliases{$name} = $codegenProperties->{"aliases"};
                } elsif ($codegenOptionName eq "synonym") {
                    $synonyms{$name} = 1;
                    push @{$namesToSynonyms{$codegenProperties->{"synonym"}}}, $name;
                } elsif ($styleBuilderOptions{$codegenOptionName}) {
                    $propertiesWithStyleBuilderOptions{$name}{$codegenOptionName} = $codegenProperties->{$codegenOptionName};
                } elsif ($codegenOptionName eq "internal-only") {
                    # internal-only properties exist to make it easier to parse compound properties (e.g. background-repeat) as if they were shorthands.
                    push @internalProperties, $name
                } elsif ($codegenOptionName eq "runtime-flag") {
                    $runtimeFlags{$name} = $codegenProperties->{"runtime-flag"};
                } elsif ($codegenOptionName eq "settings-flag") {
                    $settingsFlags{$name} = $codegenProperties->{"settings-flag"};
                } elsif ($codegenOptionName eq "color-property") {
                    $nameIsColorProperty{$name} = 1;
                } elsif ($codegenOptionName eq "logical-property-group") {
                    die "Shorthand property $name can't belong to a logical property group\n" if exists $codegenProperties->{"longhands"};
                    $nameIsDeferred{$name} = 1;
                    my $groupName = $codegenProperties->{$codegenOptionName}{"name"};
                    my $resolver = $codegenProperties->{$codegenOptionName}{"resolver"};
                    my $kind;
                    my $logic;
                    while (my ($currentLogic, $resolversForLogic) = each %logicalPropertyGroupResolvers) {
                        while (my ($currentKind, $resolverList) = each %{ $resolversForLogic }) {
                            for my $currentResolver (@{ $resolverList }) {
                                if ($currentResolver eq $resolver) {
                                    $kind = $currentKind;
                                    $logic = $currentLogic;
                                }
                            }
                        }
                    }
                    if (!$kind) {
                        die "Unrecognized resolver \"$resolver\" for codegen property \"$codegenOptionName\" for $name property.";
                    }
                    my $otherKind = $logicalPropertyGroups{$groupName}{"kind"};
                    if ($otherKind && $otherKind ne $kind) {
                        die "Logical property group \"$groupName\" has resolvers of different kinds: $kind and $otherKind.";
                    }
                    $logicalPropertyGroups{$groupName}{"kind"} = $kind;
                    my $otherName = $logicalPropertyGroups{$groupName}{$logic}{$resolver};
                    if ($otherName) {
                        die "Logical property group \"$groupName\" has multiple \"$resolver\" properties: $name and $otherName.";
                    }
                    $logicalPropertyGroups{$groupName}{$logic}{$resolver} = $name;
                } elsif ($codegenOptionName eq "descriptor-only") {
                    $nameIsDescriptorOnly{$name} = 1;
                } else {
                    die "Unrecognized codegen property \"$codegenOptionName\" for $name property.";
                }
            }
        } elsif ($optionName eq "animatable") {
            $propertiesWithStyleBuilderOptions{$name}{"animatable"} = $optionsHashRef->{"animatable"};
        } elsif ($optionName eq "inherited") {
            $nameIsInherited{$name} = $optionsHashRef->{"inherited"};
        } elsif ($optionName eq "values") {
            # FIXME: Implement.
        }
        # We allow unrecognized options to pass through without error to support annotation.
    }
}

sub sortByDescendingPriorityAndName
{
    # Sort shorthands to the back
    if (exists $propertiesWithStyleBuilderOptions{$a}{"longhands"} < exists $propertiesWithStyleBuilderOptions{$b}{"longhands"}) {
        return -1;
    }
    if (exists $propertiesWithStyleBuilderOptions{$a}{"longhands"} > exists $propertiesWithStyleBuilderOptions{$b}{"longhands"}) {
        return 1;
    }
    # Sort longhands with top priority to the front
    if (!!$nameIsTopPriority{$a} < !!$nameIsTopPriority{$b}) {
        return 1;
    }
    if (!!$nameIsTopPriority{$a} > !!$nameIsTopPriority{$b}) {
        return -1;
    }
    # Sort longhands with high priority to the front
    if (!!$nameIsHighPriority{$a} < !!$nameIsHighPriority{$b}) {
        return 1;
    }
    if (!!$nameIsHighPriority{$a} > !!$nameIsHighPriority{$b}) {
        return -1;
    }
    # Sort deferred longhands to the back, before shorthands
    if (!!$nameIsDeferred{$a} < !!$nameIsDeferred{$b}) {
        return -1;
    }
    if (!!$nameIsDeferred{$a} > !!$nameIsDeferred{$b}) {
        return 1;
    }
    # Sort sunken names at the end of their priority bucket
    if (!!$namePriorityShouldSink{$a} < !!$namePriorityShouldSink{$b}) {
        return -1;
    }
    if (!!$namePriorityShouldSink{$a} > !!$namePriorityShouldSink{$b}) {
        return 1;
    }
    # Sort names without leading '-' to the front
    if (substr($a, 0, 1) eq "-" && substr($b, 0, 1) ne "-") {
        return 1;
    }
    if (substr($a, 0, 1) ne "-" && substr($b, 0, 1) eq "-") {
        return -1;
    }
    return $a cmp $b;
}

@names = sort sortByDescendingPriorityAndName @names;

open GPERF, ">CSSPropertyNames.gperf" || die "Could not open CSSPropertyNames.gperf for writing";
print GPERF << "EOF";
%{
/* This file is automatically generated from $inputFile by makeprop, do not edit */
#include "config.h"
#include \"CSSProperty.h\"
#include \"CSSPropertyNames.h\"
#include \"HashTools.h\"
#include "DeprecatedGlobalSettings.h"
#include "Settings.h"
#include <wtf/ASCIICType.h>
#include <wtf/text/AtomString.h>
#include <wtf/text/WTFString.h>
#include <string.h>

IGNORE_WARNINGS_BEGIN(\"implicit-fallthrough\")

// Older versions of gperf like to use the `register` keyword.
#define register

namespace WebCore {

// Using std::numeric_limits<uint16_t>::max() here would be cleaner,
// but is not possible due to missing constexpr support in MSVC 2013.
static_assert(numCSSProperties + 1 <= 65535, "CSSPropertyID should fit into uint16_t.");

EOF

print GPERF "constexpr ASCIILiteral propertyNameStrings[numCSSProperties] = {\n";
foreach my $name (@names) {
  print GPERF "    \"$name\"_s,\n";
}
print GPERF "};\n\n";

print GPERF << "EOF";
%}
%struct-type
struct Property;
%omit-struct-type
%language=C++
%readonly-tables
%global-table
%compare-strncmp
%define class-name CSSPropertyNamesHash
%define lookup-function-name findPropertyImpl
%define hash-function-name propery_hash_function
%define word-array-name property_wordlist
%enum
%%
EOF

foreach my $name (@names) {
  print GPERF $name . ", CSSProperty" . $nameToId{$name} . "\n";
}

for my $name (@names) {
    if (!$nameToAliases{$name}) {
        next;
    }
    for my $alias (@{$nameToAliases{$name}}) {
        print GPERF $alias . ", CSSProperty" . $nameToId{$name} . "\n";
    }
}

print GPERF << "EOF";
%%
const Property* findProperty(const char* str, unsigned int len)
{
    return CSSPropertyNamesHash::findPropertyImpl(str, len);
}

bool isInternalCSSProperty(const CSSPropertyID id)
{
    switch (id) {
EOF

foreach my $name (sort @internalProperties) {
  print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
}

print GPERF << "EOF";
        return true;
    default:
        return false;
    }
}

EOF

if (%runtimeFlags) {
  print GPERF << "EOF";
bool isEnabledCSSProperty(const CSSPropertyID id)
{
    switch (id) {
EOF
  foreach my $name (sort keys %runtimeFlags) {
    print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
    print GPERF "        return DeprecatedGlobalSettings::" . $runtimeFlags{$name} . "Enabled();\n";
  }
  print GPERF << "EOF";
    default:
        return true;
    }
EOF
} else {
  print GPERF << "EOF";
bool isEnabledCSSProperty(const CSSPropertyID)
{
    return true;
EOF
}

print GPERF << "EOF";
}

bool isCSSPropertyEnabledBySettings(const CSSPropertyID id, const Settings* settings)
{
    if (!settings)
        return true;

    switch (id) {
EOF

foreach my $name (sort keys %settingsFlags) {
  print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
  print GPERF "        return settings->" . $settingsFlags{$name} . "();\n";
}

print GPERF << "EOF";
    default:
        return true;
    }
    return true;
}

ASCIILiteral getPropertyName(CSSPropertyID id)
{
    if (id < firstCSSProperty)
        return { };
    int index = id - firstCSSProperty;
    if (index >= numCSSProperties)
        return { };
    return propertyNameStrings[index];
}

const AtomString& getPropertyNameAtomString(CSSPropertyID id)
{
    if (id < firstCSSProperty)
        return nullAtom();
    int index = id - firstCSSProperty;
    if (index >= numCSSProperties)
        return nullAtom();

    static AtomString* propertyStrings = new AtomString[numCSSProperties]; // Intentionally never destroyed.
    AtomString& propertyString = propertyStrings[index];
    if (propertyString.isNull())
        propertyString = propertyNameStrings[index];
    return propertyString;
}

String getPropertyNameString(CSSPropertyID id)
{
    // We share the StringImpl with the AtomStrings.
    return getPropertyNameAtomString(id).string();
}

String getJSPropertyName(CSSPropertyID id)
{
    char result[maxCSSPropertyNameLength + 1];
    const char* cssPropertyName = getPropertyName(id);
    const char* propertyNamePointer = cssPropertyName;
    if (!propertyNamePointer)
        return emptyString();

    char* resultPointer = result;
    while (char character = *propertyNamePointer++) {
        if (character == '-') {
            char nextCharacter = *propertyNamePointer++;
            if (!nextCharacter)
                break;
            character = (propertyNamePointer - 2 != cssPropertyName) ? toASCIIUpper(nextCharacter) : nextCharacter;
        }
        *resultPointer++ = character;
    }
    *resultPointer = '\\0';
    return String::fromLatin1(result);
}

static const bool isInheritedPropertyTable[numCSSProperties + $numPredefinedProperties] = {
    false, // CSSPropertyInvalid
    true, // CSSPropertyCustom
EOF

foreach my $name (@names) {
  my $id = $nameToId{$name};
  my $value = $nameIsInherited{$name} ? "true " : "false";
  print GPERF "    $value, // CSSProperty$id\n";
}

print GPERF<< "EOF";
};

bool CSSProperty::isInheritedProperty(CSSPropertyID id)
{
    ASSERT(id <= lastCSSProperty);
    ASSERT(id != CSSPropertyInvalid);
    return isInheritedPropertyTable[id];
}

EOF

if (%relatedProperty) {
    print GPERF << "EOF";
CSSPropertyID getRelatedPropertyId(const CSSPropertyID id)
{
    switch (id) {
EOF
    for my $name (@names) {
        if (!$relatedProperty{$name}) {
            next;
        }
        my $related = $relatedProperty{$name};
        die "Property $name has an unknown related property: $related\n" if !exists($nameToId{$related});
        die "High priority property $name can't have a related property: $related\n" if $nameIsHighPriority{$name};
        die "Shorthand property $name can't have a related property: $related\n" if exists $propertiesWithStyleBuilderOptions{$name}{"longhands"};
        die "Property $name can't have itself as a related property\n" if $related eq $name;
        die "Property $name has $related as a related property, but it's not reciprocal\n" if $relatedProperty{$related} ne $name;
        print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
        print GPERF "        return CSSPropertyID::CSSProperty" . $nameToId{$related} . ";\n";
    }
    print GPERF << "EOF";
    default:
        return CSSPropertyID::CSSPropertyInvalid;
    }
EOF
} else {
    print GPERF << "EOF";
CSSPropertyID getRelatedPropertyId(const CSSPropertyID)
{
    return CSSPropertyID::CSSPropertyInvalid;
EOF
}

print GPERF << "EOF";
}

Vector<String> CSSProperty::aliasesForProperty(CSSPropertyID id)
{
    switch (id) {
EOF

for my $name (@names) {
    if (!$nameToAliases{$name}) {
        next;
    }
    print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
    print GPERF "        return { \"" . join("\"_s, \"", @{$nameToAliases{$name}}) . "\"_s };\n";
}

print GPERF << "EOF";
    default:
        return { };
    }
}

bool CSSProperty::isColorProperty(CSSPropertyID id)
{
    switch (id) {
EOF
for my $name (@names) {
    if (!$nameIsColorProperty{$name}) {
        next;
    }
    print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
}

print GPERF << "EOF";
        return true;
    default:
        return false;
    }
}

bool CSSProperty::isDirectionAwareProperty(CSSPropertyID id)
{
    switch (id) {
EOF
for my $groupName (sort keys %logicalPropertyGroups) {
    my $logicalPropertyGroup = $logicalPropertyGroups{$groupName};
    for my $name (sort values %{ $logicalPropertyGroup->{"logical"} }) {
        print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
    }
}

print GPERF << "EOF";
        return true;
    default:
        return false;
    }
}

bool CSSProperty::isInLogicalPropertyGroup(CSSPropertyID id)
{
    switch (id) {
EOF

for my $groupName (sort keys %logicalPropertyGroups) {
    my $logicalPropertyGroup = $logicalPropertyGroups{$groupName};
    for my $kind ("logical", "physical") {
        for my $name (sort values %{ $logicalPropertyGroup->{$kind} }) {
            print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
        }
    }
}

print GPERF << "EOF";
        return true;
    default:
        return false;
    }
}

bool CSSProperty::areInSameLogicalPropertyGroupWithDifferentMappingLogic(CSSPropertyID id1, CSSPropertyID id2)
{
    switch (id1) {
EOF

for my $groupName (sort keys %logicalPropertyGroups) {
    my $logicalPropertyGroup = $logicalPropertyGroups{$groupName};
    my $logical = $logicalPropertyGroup->{"logical"};
    my $physical = $logicalPropertyGroup->{"physical"};
    for my $first ($logical, $physical) {
        my $second = $first eq $logical ? $physical : $logical;
        for my $resolver (sort keys %{ $first }) {
            my $name = $first->{$resolver};
            print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
        }
        print GPERF "        switch (id2) {\n";
        for my $resolver (sort keys %{ $second }) {
            my $name = $second->{$resolver};
            print GPERF "        case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
        }
        print GPERF << "EOF";
            return true;
        default:
            return false;
        }
EOF
    }
}

print GPERF << "EOF";
    default:
        return false;
    }
}

CSSPropertyID CSSProperty::resolveDirectionAwareProperty(CSSPropertyID propertyID, TextDirection direction, WritingMode writingMode)
{
    auto textflow = makeTextFlow(writingMode, direction);
    switch (propertyID) {
EOF

for my $groupName (sort keys %logicalPropertyGroups) {
    my $logicalPropertyGroup = $logicalPropertyGroups{$groupName};
    for my $resolver (sort keys %{ $logicalPropertyGroup->{"logical"} }) {
        my $name = $logicalPropertyGroup->{"logical"}->{$resolver};
        my $kind = $logicalPropertyGroup->{"kind"};
        my $kindId = nameToId($kind);
        my $resolverEnum = "LogicalBox" . $kindId . "::" . nameToId($resolver);
        my $physicals = $logicalPropertyGroupResolvers{"physical"}->{$kind};
        my @properties = map { "CSSProperty" . $nameToId{$logicalPropertyGroup->{"physical"}{$_}} } @{ $physicals };
        print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ": {\n";
        print GPERF "        static constexpr CSSPropertyID properties[" . scalar(@properties) . "] = { " . join(", ", @properties) . " };\n";
        print GPERF "        return properties[static_cast<size_t>(mapLogical" . $kindId . "ToPhysical" . $kindId . "(textflow, " . $resolverEnum . "))];\n";
        print GPERF "    }\n";
    }
}

print GPERF << "EOF";
    default:
        return propertyID;
    }
}

CSSPropertyID CSSProperty::unresolvePhysicalProperty(CSSPropertyID propertyID, TextDirection direction, WritingMode writingMode)
{
    auto textflow = makeTextFlow(writingMode, direction);
    switch (propertyID) {
EOF

for my $groupName (sort keys %logicalPropertyGroups) {
    my $logicalPropertyGroup = $logicalPropertyGroups{$groupName};
    for my $resolver (sort keys %{ $logicalPropertyGroup->{"physical"} }) {
        my $name = $logicalPropertyGroup->{"physical"}->{$resolver};
        my $kind = $logicalPropertyGroup->{"kind"};
        my $kindId = nameToId($kind);
        my $resolverEnum = "Box" . $kindId . "::" . nameToId($resolver);
        my $logicals = $logicalPropertyGroupResolvers{"logical"}->{$kind};
        my @properties = map { "CSSProperty" . $nameToId{$logicalPropertyGroup->{"logical"}{$_}} } @{ $logicals };
        print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ": {\n";
        print GPERF "        static constexpr CSSPropertyID properties[" . scalar(@properties) . "] = { " . join(", ", @properties) . " };\n";
        print GPERF "        return properties[static_cast<size_t>(mapPhysical" . $kindId . "ToLogical" . $kindId . "(textflow, " . $resolverEnum . "))];\n";
        print GPERF "    }\n";
    }
}

print GPERF << "EOF";
    default:
        return propertyID;
    }
}

bool CSSProperty::isDescriptorOnly(CSSPropertyID id)
{
    switch (id) {
EOF
for my $name (@names) {
    if (!$nameIsDescriptorOnly{$name}) {
        next;
    }
    print GPERF "    case CSSPropertyID::CSSProperty" . $nameToId{$name} . ":\n";
}

print GPERF << "EOF";
        return true;
    default:
        return false;
    }
}

} // namespace WebCore

IGNORE_WARNINGS_END
EOF

close GPERF;

open HEADER, ">CSSPropertyNames.h" || die "Could not open CSSPropertyNames.h for writing";
print HEADER << "EOF";
/* This file is automatically generated from $inputFile by makeprop, do not edit */

#pragma once

#include <string.h>
#include <wtf/Forward.h>
#include <wtf/HashFunctions.h>
#include <wtf/HashTraits.h>

namespace WebCore {

class Settings;

enum CSSPropertyID : uint16_t {
    CSSPropertyInvalid = 0,
    CSSPropertyCustom = 1,
EOF

my $first = $numPredefinedProperties;
my $i = $numPredefinedProperties;
my $maxLen = 0;
my $firstTopPriorityPropertyName;
my $lastTopPriorityPropertyName;
my $firstHighPriorityPropertyName;
my $lastHighPriorityPropertyName;
my $firstLowPriorityPropertyName;
my $lastLowPriorityPropertyName;
my $firstDeferredPropertyName;
my $lastDeferredPropertyName;
my $firstShorthandPropertyName;
my $lastShorthandPropertyName;
foreach my $name (@names) {
  # Assumes that @names is sorted by descending priorities.
  if (exists $propertiesWithStyleBuilderOptions{$name}{"longhands"}) {
    $firstShorthandPropertyName = $name if !$firstShorthandPropertyName;
    $lastShorthandPropertyName = $name;
  } elsif ($nameIsTopPriority{$name}) {
    $firstTopPriorityPropertyName = $name if !$firstTopPriorityPropertyName;
    $lastTopPriorityPropertyName = $name;
  } elsif ($nameIsHighPriority{$name}) {
    $firstHighPriorityPropertyName = $name if !$firstHighPriorityPropertyName;
    $lastHighPriorityPropertyName = $name;
  } elsif (!$nameIsDeferred{$name}) {
    $firstLowPriorityPropertyName = $name if !$firstLowPriorityPropertyName;
    $lastLowPriorityPropertyName = $name;
  } else {
    $firstDeferredPropertyName = $name if !$firstDeferredPropertyName;
    $lastDeferredPropertyName = $name;
  }
  print HEADER "    CSSProperty" . $nameToId{$name} . " = " . $i . ",\n";
  $i = $i + 1;
  if (length($name) > $maxLen) {
    $maxLen = length($name);
  }
}
my $num = $i - $first;
my $last = $i - 1;

print HEADER "};\n\n";
print HEADER "const int firstCSSProperty = $first;\n";
print HEADER "const int numCSSProperties = $num;\n";
print HEADER "const int lastCSSProperty = $last;\n";
print HEADER "const size_t maxCSSPropertyNameLength = $maxLen;\n";
print HEADER "const CSSPropertyID firstTopPriorityProperty = CSSProperty" . $nameToId{$firstTopPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID lastTopPriorityProperty = CSSProperty" . $nameToId{$lastTopPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID firstHighPriorityProperty = CSSProperty" . $nameToId{$firstHighPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID lastHighPriorityProperty = CSSProperty" . $nameToId{$lastHighPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID firstLowPriorityProperty = CSSProperty" . $nameToId{$firstLowPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID lastLowPriorityProperty = CSSProperty" . $nameToId{$lastLowPriorityPropertyName} . ";\n";
print HEADER "const CSSPropertyID firstDeferredProperty = CSSProperty" . $nameToId{$firstDeferredPropertyName} . ";\n";
print HEADER "const CSSPropertyID lastDeferredProperty = CSSProperty" . $nameToId{$lastDeferredPropertyName} . ";\n";
print HEADER "const CSSPropertyID firstShorthandProperty = CSSProperty" . $nameToId{$firstShorthandPropertyName} . ";\n";
print HEADER "const CSSPropertyID lastShorthandProperty = CSSProperty" . $nameToId{$lastShorthandPropertyName} . ";\n\n";

print HEADER "static const CSSPropertyID computedPropertyIDs[] = {\n";
my $numComputedPropertyIDs = 0;
sub sortWithPrefixedPropertiesLast
{
    my $aStartsWithPrefix = substr($a, 0, 1) eq "-";
    my $bStartsWithPrefix = substr($b, 0, 1) eq "-";
    if ($aStartsWithPrefix && !$bStartsWithPrefix) {
        return 1;
    }
    if (!$aStartsWithPrefix && $bStartsWithPrefix) {
        return -1;
    }
    return $a cmp $b;
}

foreach my $name (sort sortWithPrefixedPropertiesLast @names) {
  next if skippedFromComputedStyle($name);
  print HEADER "    CSSProperty" . $nameToId{$name} . ",\n";
  $numComputedPropertyIDs += 1;
}
print HEADER "};\n";
print HEADER "const size_t numComputedPropertyIDs = $numComputedPropertyIDs;\n";

print HEADER << "EOF";

bool isInternalCSSProperty(const CSSPropertyID);
bool isEnabledCSSProperty(const CSSPropertyID);
bool isCSSPropertyEnabledBySettings(const CSSPropertyID, const Settings* = nullptr);
ASCIILiteral getPropertyName(CSSPropertyID);
const AtomString& getPropertyNameAtomString(CSSPropertyID id);
String getPropertyNameString(CSSPropertyID id);
String getJSPropertyName(CSSPropertyID);
CSSPropertyID getRelatedPropertyId(CSSPropertyID id);

inline CSSPropertyID convertToCSSPropertyID(int value)
{
    ASSERT((value >= firstCSSProperty && value <= lastCSSProperty) || value == CSSPropertyInvalid || value == CSSPropertyCustom);
    return static_cast<CSSPropertyID>(value);
}

} // namespace WebCore

namespace WTF {
template<> struct DefaultHash<WebCore::CSSPropertyID> : IntHash<unsigned> { };
template<> struct HashTraits<WebCore::CSSPropertyID> : GenericHashTraits<WebCore::CSSPropertyID> {
    static const bool emptyValueIsZero = true;
    static void constructDeletedValue(WebCore::CSSPropertyID& slot) { slot = static_cast<WebCore::CSSPropertyID>(WebCore::lastCSSProperty + 1); }
    static bool isDeletedValue(WebCore::CSSPropertyID value) { return value == (WebCore::lastCSSProperty + 1); }
};
} // namespace WTF

EOF

close HEADER;

#
# StyleBuilderGenerated.cpp generator.
#

sub getScopeForFunction {
  my $name = shift;
  my $builderFunction = shift;

  return $propertiesWithStyleBuilderOptions{$name}{"custom"}{$builderFunction} ? "BuilderCustom" : "BuilderFunctions";
}

sub getNameForMethods {
  my $name = shift;

  my $nameForMethods = $nameToId{$name};
  $nameForMethods =~ s/Webkit//g;
  if (exists($propertiesWithStyleBuilderOptions{$name}{"name-for-methods"})) {
    $nameForMethods = $propertiesWithStyleBuilderOptions{$name}{"name-for-methods"};
  }
  return $nameForMethods;
}

sub getAutoGetter {
  my $name = shift;
  my $renderStyle = shift;

  return $renderStyle . ".hasAuto" . getNameForMethods($name) . "()";
}

sub getAutoSetter {
  my $name = shift;
  my $renderStyle = shift;

  return $renderStyle . ".setHasAuto" . getNameForMethods($name) . "()";
}

sub getVisitedLinkSetter {
  my $name = shift;
  my $renderStyle = shift;

  return $renderStyle . ".setVisitedLink" . getNameForMethods($name);
}

sub getClearFunction {
  my $name = shift;

  return "clear" . getNameForMethods($name);
}

sub getEnsureAnimationsOrTransitionsMethod {
  my $name = shift;

  return "ensureAnimations" if $name =~ /animation-/;
  return "ensureTransitions" if $name =~ /transition-/;
  die "Unrecognized animation property name.";
}

sub getAnimationsOrTransitionsMethod {
  my $name = shift;

  return "animations" if $name =~ /animation-/;
  return "transitions" if $name =~ /transition-/;
  die "Unrecognized animation property name.";
}

sub getTestFunction {
  my $name = shift;

  return "is" . getNameForMethods($name) . "Set";
}

sub getAnimationMapfunction {
  my $name = shift;

  return "mapAnimation" . getNameForMethods($name);
}

sub getLayersFunction {
  my $name = shift;

  return "backgroundLayers" if $name =~ /background-/;
  return "maskLayers" if $name =~ /mask-/;
  die "Unrecognized FillLayer property name.";
}

sub getLayersAccessorFunction {
  my $name = shift;

  return "ensureBackgroundLayers" if $name =~ /background-/;
  return "ensureMaskLayers" if $name =~ /mask-/;
  die "Unrecognized FillLayer property name.";
}

sub getFillLayerType {
my $name = shift;

  return "FillLayerType::Background" if $name =~ /background-/;
  return "FillLayerType::Mask" if $name =~ /mask-/;
}

sub getFillLayerMapfunction {
  my $name = shift;

  return "mapFill" . getNameForMethods($name);
}


foreach my $name (@names) {
  my $nameForMethods = getNameForMethods($name);
  $nameForMethods =~ s/Webkit//g;
  if (exists($propertiesWithStyleBuilderOptions{$name}{"name-for-methods"})) {
    $nameForMethods = $propertiesWithStyleBuilderOptions{$name}{"name-for-methods"};
  }

  if (!exists($propertiesWithStyleBuilderOptions{$name}{"getter"})) {
    $propertiesWithStyleBuilderOptions{$name}{"getter"} = lcfirst($nameForMethods);
  }
  if (!exists($propertiesWithStyleBuilderOptions{$name}{"setter"})) {
    $propertiesWithStyleBuilderOptions{$name}{"setter"} = "set" . $nameForMethods;
  }
  if (!exists($propertiesWithStyleBuilderOptions{$name}{"initial"})) {
    if (exists($propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"})) {
      $propertiesWithStyleBuilderOptions{$name}{"initial"} = "initialFill" . $nameForMethods;
    } else {
      $propertiesWithStyleBuilderOptions{$name}{"initial"} = "initial" . $nameForMethods;
    }
  }
  # FIXME: Convert option custom from a string to an array.
  if (!exists($propertiesWithStyleBuilderOptions{$name}{"custom"})) {
    $propertiesWithStyleBuilderOptions{$name}{"custom"} = "";
  } elsif ($propertiesWithStyleBuilderOptions{$name}{"custom"} eq "All") {
    $propertiesWithStyleBuilderOptions{$name}{"custom"} = "Initial|Inherit|Value";
  }
  my %customValues = map { $_ => 1 } split(/\|/, $propertiesWithStyleBuilderOptions{$name}{"custom"});
  $propertiesWithStyleBuilderOptions{$name}{"custom"} = \%customValues;
}

use constant {
  NOT_FOR_VISITED_LINK => 0,
  FOR_VISITED_LINK => 1,
};

sub colorFromPrimitiveValue {
  my $primitiveValue = shift;
  my $forVisitedLink = @_ ? shift : NOT_FOR_VISITED_LINK;

  return "builderState.colorFromPrimitiveValue(" . $primitiveValue . ", ForVisitedLink::" . ($forVisitedLink ? "Yes" : "No") . ")";
}

use constant {
  VALUE_IS_COLOR => 0,
  VALUE_IS_PRIMITIVE => 1,
};

sub generateColorValueSetter {
  my $name = shift;
  my $value = shift;
  my $indent = shift;
  my $valueIsPrimitive = @_ ? shift : VALUE_IS_COLOR;

  my $style = "builderState.style()";
  my $setterContent .= $indent . "if (builderState.applyPropertyToRegularStyle())\n";
  my $setValue = $style . "." . $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $color = $valueIsPrimitive ? colorFromPrimitiveValue($value) : $value;
  $setterContent .= $indent . "    " . $setValue . "(" . $color . ");\n";
  $setterContent .= $indent . "if (builderState.applyPropertyToVisitedLinkStyle())\n";
  $color = $valueIsPrimitive ? colorFromPrimitiveValue($value, FOR_VISITED_LINK) : $value;
  $setterContent .= $indent . "    " . getVisitedLinkSetter($name, $style) . "(" . $color . ");\n";

  return $setterContent;
}

sub generateAnimationPropertyInitialValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setterContent = "";
  $setterContent .= $indent . "AnimationList& list = builderState.style()." . getEnsureAnimationsOrTransitionsMethod($name) . "();\n";
  $setterContent .= $indent . "if (list.isEmpty())\n";
  $setterContent .= $indent . "    list.append(Animation::create());\n";
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $initial = $propertiesWithStyleBuilderOptions{$name}{"initial"};
  $setterContent .= $indent . "list.animation(0)." . $setter . "(Animation::" . $initial . "());\n";
  $setterContent .= $indent . "for (auto& animation : list)\n";
  $setterContent .= $indent . "    animation->" . getClearFunction($name) . "();\n";

  return $setterContent;
}

sub generateAnimationPropertyInheritValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setterContent = "";
  $setterContent .= $indent . "auto& list = builderState.style()." . getEnsureAnimationsOrTransitionsMethod($name) . "();\n";
  $setterContent .= $indent . "auto* parentList = builderState.parentStyle()." . getAnimationsOrTransitionsMethod($name) . "();\n";
  $setterContent .= $indent . "size_t i = 0, parentSize = parentList ? parentList->size() : 0;\n";
  $setterContent .= $indent . "for ( ; i < parentSize && parentList->animation(i)." . getTestFunction($name) . "(); ++i) {\n";
  $setterContent .= $indent . "    if (list.size() <= i)\n";
  $setterContent .= $indent . "        list.append(Animation::create());\n";
  my $getter = $propertiesWithStyleBuilderOptions{$name}{"getter"};
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  $setterContent .= $indent . "    list.animation(i)." . $setter . "(parentList->animation(i)." . $getter . "());\n";
  $setterContent .= $indent . "}\n";
  $setterContent .= "\n";
  $setterContent .= $indent . "// Reset any remaining animations to not have the property set.\n";
  $setterContent .= $indent . "for ( ; i < list.size(); ++i)\n";
  $setterContent .= $indent . "    list.animation(i)." . getClearFunction($name) . "();\n";

  return $setterContent;
}

sub generateAnimationPropertyValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setterContent = "";
  $setterContent .= $indent . "AnimationList& list = builderState.style()." . getEnsureAnimationsOrTransitionsMethod($name) . "();\n";
  $setterContent .= $indent . "size_t childIndex = 0;\n";
  $setterContent .= $indent . "if (is<CSSValueList>(value)) {\n";
  $setterContent .= $indent . "    /* Walk each value and put it into an animation, creating new animations as needed. */\n";
  $setterContent .= $indent . "    for (auto& currentValue : downcast<CSSValueList>(value)) {\n";
  $setterContent .= $indent . "        if (childIndex <= list.size())\n";
  $setterContent .= $indent . "            list.append(Animation::create());\n";
  $setterContent .= $indent . "        builderState.styleMap()." . getAnimationMapfunction($name) . "(list.animation(childIndex), currentValue);\n";
  $setterContent .= $indent . "        ++childIndex;\n";
  $setterContent .= $indent . "    }\n";
  $setterContent .= $indent . "} else {\n";
  $setterContent .= $indent . "    if (list.isEmpty())\n";
  $setterContent .= $indent . "        list.append(Animation::create());\n";
  $setterContent .= $indent . "    builderState.styleMap()." . getAnimationMapfunction($name) . "(list.animation(childIndex), value);\n";
  $setterContent .= $indent . "    childIndex = 1;\n";
  $setterContent .= $indent . "}\n";
  $setterContent .= $indent . "for ( ; childIndex < list.size(); ++childIndex) {\n";
  $setterContent .= $indent . "    /* Reset all remaining animations to not have the property set. */\n";
  $setterContent .= $indent . "    list.animation(childIndex)." . getClearFunction($name) . "();\n";
  $setterContent .= $indent . "}\n";

  return $setterContent;
}

sub generateFillLayerPropertyInitialValueSetter {
  my $name = shift;
  my $indent = shift;

  my $getter = $propertiesWithStyleBuilderOptions{$name}{"getter"};
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $clearFunction = getClearFunction($name);
  my $testFunction = getTestFunction($name);
  my $initial = "FillLayer::" . $propertiesWithStyleBuilderOptions{$name}{"initial"} . "(" . getFillLayerType($name) . ")";

  my $setterContent = "";
  $setterContent .= $indent . "// Check for (single-layer) no-op before clearing anything.\n";
  $setterContent .= $indent . "auto& layers = builderState.style()." . getLayersFunction($name) . "();\n";
  $setterContent .= $indent . "if (!layers.next() && (!layers." . $testFunction . "() || layers." . $getter . "() == $initial))\n";
  $setterContent .= $indent . "    return;\n";
  $setterContent .= "\n";
  $setterContent .= $indent . "auto* child = &builderState.style()." . getLayersAccessorFunction($name) . "();\n";
  $setterContent .= $indent . "child->" . $setter . "(" . $initial . ");\n";
  $setterContent .= $indent . "for (child = child->next(); child; child = child->next())\n";
  $setterContent .= $indent . "    child->" . $clearFunction . "();\n";

  return $setterContent;
}

sub generateFillLayerPropertyInheritValueSetter {
  my $name = shift;
  my $indent = shift;

  my $getter = $propertiesWithStyleBuilderOptions{$name}{"getter"};
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $clearFunction = getClearFunction($name);
  my $testFunction = getTestFunction($name);

  my $setterContent = "";
  $setterContent .= $indent . "// Check for no-op before copying anything.\n";
  $setterContent .= $indent . "if (builderState.parentStyle()." . getLayersFunction($name) ."() == builderState.style()." . getLayersFunction($name) . "())\n";
  $setterContent .= $indent . "    return;\n";
  $setterContent .= "\n";
  $setterContent .= $indent . "auto* child = &builderState.style()." . getLayersAccessorFunction($name) . "();\n";
  $setterContent .= $indent . "FillLayer* previousChild = nullptr;\n";
  $setterContent .= $indent . "for (auto* parent = &builderState.parentStyle()." . getLayersFunction($name) . "(); parent && parent->" . $testFunction . "(); parent = parent->next()) {\n";
  $setterContent .= $indent . "    if (!child) {\n";
  $setterContent .= $indent . "        previousChild->setNext(FillLayer::create(" . getFillLayerType($name) . "));\n";
  $setterContent .= $indent . "        child = previousChild->next();\n";
  $setterContent .= $indent . "    }\n";
  $setterContent .= $indent . "    child->" . $setter . "(parent->" . $getter . "());\n";
  $setterContent .= $indent . "    previousChild = child;\n";
  $setterContent .= $indent . "    child = previousChild->next();\n";
  $setterContent .= $indent . "}\n";
  $setterContent .= $indent . "for (; child; child = child->next())\n";
  $setterContent .= $indent . "    child->" . $clearFunction . "();\n";

  return $setterContent;
}

sub generateFillLayerPropertyValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setterContent = "";
  $setterContent .= $indent . "auto* child = &builderState.style()." . getLayersAccessorFunction($name) . "();\n";
  $setterContent .= $indent . "FillLayer* previousChild = nullptr;\n";
  $setterContent .= $indent . "if (is<CSSValueList>(value) && !is<CSSImageSetValue>(value)) {\n";
  $setterContent .= $indent . "    // Walk each value and put it into a layer, creating new layers as needed.\n";
  $setterContent .= $indent . "    for (auto& item : downcast<CSSValueList>(value)) {\n";
  $setterContent .= $indent . "        if (!child) {\n";
  $setterContent .= $indent . "            previousChild->setNext(FillLayer::create(" . getFillLayerType($name) . "));\n";
  $setterContent .= $indent . "            child = previousChild->next();\n";
  $setterContent .= $indent . "        }\n";
  $setterContent .= $indent . "        builderState.styleMap()." . getFillLayerMapfunction($name) . "(propertyID, *child, item);\n";
  $setterContent .= $indent . "        previousChild = child;\n";
  $setterContent .= $indent . "        child = child->next();\n";
  $setterContent .= $indent . "    }\n";
  $setterContent .= $indent . "} else {\n";
  $setterContent .= $indent . "    builderState.styleMap()." . getFillLayerMapfunction($name) . "(propertyID, *child, value);\n";
  $setterContent .= $indent . "    child = child->next();\n";
  $setterContent .= $indent . "}\n";
  $setterContent .= $indent . "for (; child; child = child->next())\n";
  $setterContent .= $indent . "    child->" . getClearFunction($name) . "();\n";

  return $setterContent;
}

sub generateSetValueStatement
{
  my $name = shift;
  my $value = shift;

  my $isSVG = exists $propertiesWithStyleBuilderOptions{$name}{"svg"};
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  return "builderState.style()." .  ($isSVG ? "accessSVGStyle()." : "") . $setter . "(" . $value . ")";
}

sub generateInitialValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $initial = $propertiesWithStyleBuilderOptions{$name}{"initial"};
  my $isSVG = exists $propertiesWithStyleBuilderOptions{$name}{"svg"};
  my $setterContent = "";
  $setterContent .= $indent . "static void applyInitial" . $nameToId{$name} . "(BuilderState& builderState)\n";
  $setterContent .= $indent . "{\n";
  my $style = "builderState.style()";
  if (exists $propertiesWithStyleBuilderOptions{$name}{"auto-functions"}) {
    $setterContent .= $indent . "    " . getAutoSetter($name, $style) . ";\n";
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"visited-link-color-support"}) {
      my $initialColor = "RenderStyle::" . $initial . "()";
      $setterContent .= generateColorValueSetter($name, $initialColor, $indent . "    ");
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"animatable"}) {
    $setterContent .= generateAnimationPropertyInitialValueSetter($name, $indent . "    ");
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"font-property"}) {
    $setterContent .= $indent . "    auto fontDescription = builderState.fontDescription();\n";
    $setterContent .= $indent . "    fontDescription." . $setter . "(FontCascadeDescription::" . $initial . "());\n";
    $setterContent .= $indent . "    builderState.setFontDescription(WTFMove(fontDescription));\n";
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"}) {
    $setterContent .= generateFillLayerPropertyInitialValueSetter($name, $indent . "    ");
  } else {
    my $initialValue = ($isSVG ? "SVGRenderStyle" : "RenderStyle") . "::" . $initial . "()";
    $setterContent .= $indent . "    " . generateSetValueStatement($name, $initialValue) . ";\n";
  }
  if (exists($propertiesWithStyleBuilderOptions{$name}{"fast-path-inherited"})) {
    $setterContent .= $indent . "    builderState.style().setDisallowsFastPathInheritance();\n";
  }

  $setterContent .= $indent . "}\n";

  return $setterContent;
}

sub generateInheritValueSetter {
  my $name = shift;
  my $indent = shift;

  my $setterContent = "";
  $setterContent .= $indent . "static void applyInherit" . $nameToId{$name} . "(BuilderState& builderState)\n";
  $setterContent .= $indent . "{\n";
  my $isSVG = exists $propertiesWithStyleBuilderOptions{$name}{"svg"};
  my $parentStyle = "builderState.parentStyle()";
  my $style = "builderState.style()";
  my $getter = $propertiesWithStyleBuilderOptions{$name}{"getter"};
  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $didCallSetValue = 0;
  if (exists $propertiesWithStyleBuilderOptions{$name}{"auto-functions"}) {
    $setterContent .= $indent . "    if (" . getAutoGetter($name, $parentStyle) . ") {\n";
    $setterContent .= $indent . "        " . getAutoSetter($name, $style) . ";\n";
    $setterContent .= $indent . "        return;\n";
    $setterContent .= $indent . "    }\n";
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"visited-link-color-support"}) {
    $setterContent .= $indent . "    auto color = " . $parentStyle . "." . $getter . "();\n";
    $setterContent .= generateColorValueSetter($name, "color", $indent . "    ");
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"animatable"}) {
    $setterContent .= generateAnimationPropertyInheritValueSetter($name, $indent . "    ");
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"font-property"}) {
    $setterContent .= $indent . "    auto fontDescription = builderState.fontDescription();\n";
    $setterContent .= $indent . "    fontDescription." . $setter . "(builderState.parentFontDescription()." . $getter . "());\n";
    $setterContent .= $indent . "    builderState.setFontDescription(WTFMove(fontDescription));\n";
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"}) {
    $setterContent .= generateFillLayerPropertyInheritValueSetter($name, $indent . "    ");
    $didCallSetValue = 1;
  }
  if (!$didCallSetValue) {
    my $inheritedValue = $parentStyle . "." . ($isSVG ? "svgStyle()." : "") .  $getter . "()";
    $setterContent .= $indent . "    " . generateSetValueStatement($name, "forwardInheritedValue(" . $inheritedValue . ")") . ";\n";
  }
  if (exists($propertiesWithStyleBuilderOptions{$name}{"fast-path-inherited"})) {
    $setterContent .= $indent . "    builderState.style().setDisallowsFastPathInheritance();\n";
  }
  $setterContent .= $indent . "}\n";

  return $setterContent;
}

sub generateValueSetter {
  my $name = shift;
  my $indent = shift;

  my $valueApplierFirstArgument = "";
  if (exists $propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"}) {
    $valueApplierFirstArgument = "CSSPropertyID propertyID, ";
  }

  my $setterContent = "";
  $setterContent .= $indent . "static void applyValue" . $nameToId{$name} . "(" . $valueApplierFirstArgument . "BuilderState& builderState, CSSValue& value)\n";
  $setterContent .= $indent . "{\n";

  my $convertedValue;
  if (exists($propertiesWithStyleBuilderOptions{$name}{"converter"})) {
    $convertedValue = "BuilderConverter::convert" . $propertiesWithStyleBuilderOptions{$name}{"converter"} . "(builderState, value)";
  } elsif (exists($propertiesWithStyleBuilderOptions{$name}{"conditional-converter"})) {
    $setterContent .= $indent . "    auto convertedValue = BuilderConverter::convert" . $propertiesWithStyleBuilderOptions{$name}{"conditional-converter"} . "(builderState, value);\n";
    $convertedValue = "WTFMove(convertedValue.value())";
  } elsif ($nameIsColorProperty{$name}) {
    $convertedValue = colorFromPrimitiveValue("downcast<CSSPrimitiveValue>(value)");
  } else {
    $convertedValue = "downcast<CSSPrimitiveValue>(value)";
  }

  my $setter = $propertiesWithStyleBuilderOptions{$name}{"setter"};
  my $style = "builderState.style()";
  my $didCallSetValue = 0;
  if (exists $propertiesWithStyleBuilderOptions{$name}{"auto-functions"}) {
    $setterContent .= $indent . "    if (downcast<CSSPrimitiveValue>(value).valueID() == CSSValueAuto) {\n";
    $setterContent .= $indent . "        ". getAutoSetter($name, $style) . ";\n";
    $setterContent .= $indent . "        return;\n";
    $setterContent .= $indent . "    }\n";
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"visited-link-color-support"}) {
    $setterContent .= $indent . "    auto& primitiveValue = downcast<CSSPrimitiveValue>(value);\n";
    $setterContent .= generateColorValueSetter($name, "primitiveValue", $indent . "    ", VALUE_IS_PRIMITIVE);
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"animatable"}) {
    $setterContent .= generateAnimationPropertyValueSetter($name, $indent . "    ");
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"font-property"}) {
    $setterContent .= $indent . "    auto fontDescription = builderState.fontDescription();\n";
    $setterContent .= $indent . "    fontDescription." . $setter . "(" . $convertedValue . ");\n";
    $setterContent .= $indent . "    builderState.setFontDescription(WTFMove(fontDescription));\n";
    $didCallSetValue = 1;
  } elsif (exists $propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"}) {
    $setterContent .= generateFillLayerPropertyValueSetter($name, $indent . "    ");
    $didCallSetValue = 1;
  }
  if (!$didCallSetValue) {
    if (exists($propertiesWithStyleBuilderOptions{$name}{"conditional-converter"})) {
      $setterContent .= $indent . "    if (convertedValue)\n";
      $setterContent .= "    ";
    }
    $setterContent .= $indent . "    " . generateSetValueStatement($name, $convertedValue) . ";\n";
  }
  if (exists($propertiesWithStyleBuilderOptions{$name}{"fast-path-inherited"})) {
    $setterContent .= $indent . "    builderState.style().setDisallowsFastPathInheritance();\n";
  }
  $setterContent .= $indent . "}\n";

  return $setterContent;
}

open STYLEBUILDER, ">StyleBuilderGenerated.cpp" || die "Could not open StyleBuilderGenerated.cpp for writing";
print STYLEBUILDER << "EOF";
/* This file is automatically generated from $inputFile by makeprop, do not edit */

#include "config.h"
#include "StyleBuilderGenerated.h"

#include "CSSPrimitiveValueMappings.h"
#include "CSSProperty.h"
#include "RenderStyle.h"
#include "StyleBuilderState.h"
#include "StyleBuilderConverter.h"
#include "StyleBuilderCustom.h"
#include "StylePropertyShorthand.h"

namespace WebCore {
namespace Style {

class BuilderFunctions {
public:
EOF

foreach my $name (@names) {
  # Skip Shorthand properties and properties that do not use the StyleBuilder.
  next if (exists $propertiesWithStyleBuilderOptions{$name}{"longhands"});
  next if (exists $propertiesWithStyleBuilderOptions{$name}{"skip-builder"});
  next if (exists $synonyms{$name});
  die "Property $name is logical but doesn't have skip-builder\n" if isLogical($name);

  my $indent = "    ";
  if (!$propertiesWithStyleBuilderOptions{$name}{"custom"}{"Initial"}) {
    print STYLEBUILDER generateInitialValueSetter($name, $indent);
  }
  if (!$propertiesWithStyleBuilderOptions{$name}{"custom"}{"Inherit"}) {
    print STYLEBUILDER generateInheritValueSetter($name, $indent);
  }
  if (!$propertiesWithStyleBuilderOptions{$name}{"custom"}{"Value"}) {
    print STYLEBUILDER generateValueSetter($name, $indent);
  }
}

print STYLEBUILDER << "EOF";
};

void BuilderGenerated::applyProperty(CSSPropertyID property, BuilderState& builderState, CSSValue& value, bool isInitial, bool isInherit, const CSSRegisteredCustomProperty* registered)
{
    switch (property) {
    case CSSPropertyInvalid:
        break;
    case CSSPropertyCustom: {
        auto& customProperty = downcast<CSSCustomPropertyValue>(value);
        if (isInitial)
            BuilderCustom::applyInitialCustomProperty(builderState, registered, customProperty.name());
        else if (isInherit)
            BuilderCustom::applyInheritCustomProperty(builderState, registered, customProperty.name());
        else
            BuilderCustom::applyValueCustomProperty(builderState, registered, customProperty);
        break;
    }
EOF

foreach my $name (@names) {
  next if (exists $synonyms{$name});

  print STYLEBUILDER "    case CSSProperty" . $nameToId{$name} . ":\n";

  my $valueApplierFirstArgument = "";
  if (exists $propertiesWithStyleBuilderOptions{$name}{"fill-layer-property"}) {
    $valueApplierFirstArgument = "property, ";
  }
  foreach my $synonym (@{$namesToSynonyms{$name}}) {
    print STYLEBUILDER "    case CSSProperty" . $nameToId{$synonym} . ":\n";
  }

  if (exists $propertiesWithStyleBuilderOptions{$name}{"longhands"}) {
    print STYLEBUILDER "        ASSERT(isShorthandCSSProperty(property));\n";
    print STYLEBUILDER "        ASSERT_NOT_REACHED();\n";
  } elsif (!exists $propertiesWithStyleBuilderOptions{$name}{"skip-builder"}) {
    print STYLEBUILDER "        if (isInitial)\n";
    print STYLEBUILDER "            " . getScopeForFunction($name, "Initial") . "::applyInitial" . $nameToId{$name} . "(builderState);\n";
    print STYLEBUILDER "        else if (isInherit)\n";
    print STYLEBUILDER "            " . getScopeForFunction($name, "Inherit") . "::applyInherit" . $nameToId{$name} . "(builderState);\n";
    print STYLEBUILDER "        else\n";
    print STYLEBUILDER "            " . getScopeForFunction($name, "Value") . "::applyValue" . $nameToId{$name} . "(" . $valueApplierFirstArgument . "builderState, value);\n";
  }
  print STYLEBUILDER "        break;\n";
}

print STYLEBUILDER << "EOF";
    };
}

} // namespace Style
} // namespace WebCore
EOF

close STYLEBUILDER;

# Generate StylePropertyShorthandsFunctions.
open SHORTHANDS_H, ">", "StylePropertyShorthandFunctions.h" or die "Could not open StylePropertyShorthandFunctions.h for writing\n";
print SHORTHANDS_H << "EOF";
// This file is automatically generated from $inputFile by the makeprop.pl script. Do not edit it.

#pragma once

namespace WebCore {

class StylePropertyShorthand;

EOF

foreach my $name (@names) {
  # Skip non-Shorthand properties.
  next if (!exists $propertiesWithStyleBuilderOptions{$name}{"longhands"});

  print SHORTHANDS_H "StylePropertyShorthand " . lcfirst($nameToId{$name}) . "Shorthand();\n";
}

print SHORTHANDS_H << "EOF";

} // namespace WebCore
EOF

close SHORTHANDS_H;

open SHORTHANDS_CPP, ">", "StylePropertyShorthandFunctions.cpp" or die "Could not open StylePropertyShorthandFunctions.cpp for writing\n";
print SHORTHANDS_CPP << "EOF";
// This file is automatically generated from $inputFile by the makeprop.pl script. Do not edit it.

#include "config.h"
#include "StylePropertyShorthandFunctions.h"

#include "StylePropertyShorthand.h"

namespace WebCore {

EOF

my %longhandToShorthands = ();

foreach my $name (@names) {
  # Skip non-Shorthand properties.
  next if (!exists $propertiesWithStyleBuilderOptions{$name}{"longhands"});

  my $lowercaseId = lcfirst($nameToId{$name});
  my @longhands = @{$propertiesWithStyleBuilderOptions{$name}{"longhands"}};

  print SHORTHANDS_CPP "StylePropertyShorthand " . $lowercaseId . "Shorthand()\n";
  print SHORTHANDS_CPP "{\n";
  print SHORTHANDS_CPP "    static const CSSPropertyID " . $lowercaseId . "Properties[] = {\n";
  foreach (@longhands) {
    if ($_ eq "all") {
        foreach my $propname (@names) {
            next if (exists $propertiesWithStyleBuilderOptions{$propname}{"longhands"});
            next if ($propname eq "direction" || $propname eq "unicode-bidi");
            die "Unknown CSS property used in all shorthand: $propname" if !exists($nameToId{$propname});
            push(@{$longhandToShorthands{$propname}}, $name);
            print SHORTHANDS_CPP "        CSSProperty" . $nameToId{$propname} . ",\n";
        }
    } else {
        die "Unknown CSS property used in longhands: $_" if !exists($nameToId{$_});
        push(@{$longhandToShorthands{$_}}, $name);
        print SHORTHANDS_CPP "        CSSProperty" . $nameToId{$_} . ",\n";
    }
  }
  print SHORTHANDS_CPP "    };\n";
  print SHORTHANDS_CPP "    return StylePropertyShorthand(CSSProperty" . $nameToId{$name} . ", " . $lowercaseId . "Properties);\n";
  print SHORTHANDS_CPP "}\n\n";
}

print SHORTHANDS_CPP << "EOF";
StylePropertyShorthand shorthandForProperty(CSSPropertyID propertyID)
{
    switch (propertyID) {
EOF

foreach my $name (@names) {
  # Skip non-Shorthand properties.
  next if (!exists $propertiesWithStyleBuilderOptions{$name}{"longhands"});

  print SHORTHANDS_CPP "    case CSSProperty" . $nameToId{$name} . ":\n";
  print SHORTHANDS_CPP "        return " . lcfirst($nameToId{$name}) . "Shorthand();\n";
}

print SHORTHANDS_CPP << "EOF";
    default:
        return { };
    }
}
EOF

print SHORTHANDS_CPP << "EOF";
StylePropertyShorthandVector matchingShorthandsForLonghand(CSSPropertyID propertyID)
{
    switch (propertyID) {
EOF

sub constructShorthandsVector {
  my $shorthands = shift;

  my $vector = "StylePropertyShorthandVector{";
  foreach my $i (0 .. $#$shorthands) {
    $vector .= ", " unless $i == 0;
    $vector .= lcfirst($nameToId{$shorthands->[$i]}) . "Shorthand()";
  }
  $vector .= "}";
  return $vector;
}

my %vectorToLonghands = ();
for my $longhand (sort keys %longhandToShorthands) {
  my @shorthands = sort(@{$longhandToShorthands{$longhand}});
  push(@{$vectorToLonghands{constructShorthandsVector(\@shorthands)}}, $longhand);
}

for my $vector (sort keys %vectorToLonghands) {
  foreach (@{$vectorToLonghands{$vector}}) {
    print SHORTHANDS_CPP "    case CSSProperty" . $nameToId{$_} . ":\n";
  }
  print SHORTHANDS_CPP "        return " . $vector . ";\n";
}

print SHORTHANDS_CPP << "EOF";
    default:
        return { };
    }
}
EOF

print SHORTHANDS_CPP << "EOF";
} // namespace WebCore
EOF

close SHORTHANDS_CPP;

if (not $gperf) {
    $gperf = $ENV{GPERF} ? $ENV{GPERF} : "gperf";
}
system("\"$gperf\" --key-positions=\"*\" -D -n -s 2 CSSPropertyNames.gperf --output-file=CSSPropertyNames.cpp") == 0 || die "calling gperf failed: $?";

# Generate CSSStyleDeclaration+PropertyNames.idl

# https://drafts.csswg.org/cssom/#css-property-to-idl-attribute
sub cssPropertyToIDLAttribute($$$)
{
    my $property = shift;
    my $lowercaseFirst = shift;
    my $uppercaseFirst = shift;

    my $output = "";
    my $uppercaseNext = $uppercaseFirst;

    if ($lowercaseFirst) {
        $property = substr($property, 1);
    }

    foreach my $character (split //, $property) {
        if ($character eq "-") {
            $uppercaseNext = 1;
        } elsif ($uppercaseNext) {
            $uppercaseNext = 0;
            $output .= uc $character;
        } else {
            $output .= $character;
        }
    }

    return $output;
}

my %namesAndAliasesToName;
foreach my $name (@names) {
    if (grep { $_ eq $name } @internalProperties) {
        next;
    }
    $namesAndAliasesToName{$name} = $name;
    for my $alias (@{$nameToAliases{$name}}) {
        $namesAndAliasesToName{$alias} = $name;
    }
}
my @namesAndAliases = sort keys(%namesAndAliasesToName);

open CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL, ">", "CSSStyleDeclaration+PropertyNames.idl" or die "Could not open CSSStyleDeclaration+PropertyNames.idl for writing\n";
print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";
// This file is automatically generated from $inputFile by the makeprop.pl script. Do not edit it.

typedef USVString CSSOMString;

partial interface CSSStyleDeclaration {

EOF

print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";
    // For each CSS property property that is a supported CSS property, the following
    // partial interface applies where camel-cased attribute is obtained by running the
    // CSS property to IDL attribute algorithm for property.
    // Example: font-size -> element.style.fontSize
    // Example: -webkit-transform -> element.style.WebkitTransform
    // [CEReactions] attribute [LegacyNullToEmptyString] CSSOMString _camel_cased_attribute;
EOF

foreach my $nameOrAlias (@namesAndAliases) {
    my $camelCasedAttributeName = cssPropertyToIDLAttribute($nameOrAlias, 0, 0);
    my $name = $namesAndAliasesToName{$nameOrAlias};
    my $propertyId = $nameToId{$namesAndAliasesToName{$name}};

    my @extendedAttributeValues = ("DelegateToSharedSyntheticAttribute=propertyValueForCamelCasedIDLAttribute", "CallWith=PropertyName");
    push(@extendedAttributeValues, "EnabledBySetting=${settingsFlags{$name}}") if $settingsFlags{$name};
    push(@extendedAttributeValues, "EnabledByDeprecatedGlobalSetting=Enabled${runtimeFlags{$name}}") if $runtimeFlags{$name};
    my $extendedAttributes = join(", ", @extendedAttributeValues);

    print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL "    [CEReactions, ${extendedAttributes}] attribute [LegacyNullToEmptyString] CSSOMString ${camelCasedAttributeName};\n";
}

print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";

    // For each CSS property property that is a supported CSS property and that begins
    // with the string -webkit-, the following partial interface applies where webkit-cased
    // attribute is obtained by running the CSS property to IDL attribute algorithm for
    // property, with the lowercase first flag set.
    // Example: -webkit-transform -> element.style.webkitTransform
    // [CEReactions] attribute [LegacyNullToEmptyString] CSSOMString _webkit_cased_attribute;
EOF

foreach my $nameOrAlias (grep { $_ =~ /^\-webkit\-/ } @namesAndAliases) {
    my $webkitCasedAttributeName = cssPropertyToIDLAttribute($nameOrAlias, 1, 0);
    my $name = $namesAndAliasesToName{$nameOrAlias};
    my $propertyId = $nameToId{$namesAndAliasesToName{$name}};

    my @extendedAttributeValues = ("DelegateToSharedSyntheticAttribute=propertyValueForWebKitCasedIDLAttribute", "CallWith=PropertyName");
    push(@extendedAttributeValues, "EnabledBySetting=${settingsFlags{$name}}") if $settingsFlags{$name};
    push(@extendedAttributeValues, "EnabledByDeprecatedGlobalSetting=Enabled${runtimeFlags{$name}}") if $runtimeFlags{$name};
    my $extendedAttributes = join(", ", @extendedAttributeValues);

    print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL "    [CEReactions, ${extendedAttributes}] attribute [LegacyNullToEmptyString] CSSOMString ${webkitCasedAttributeName};\n";
}

print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";

    // For each CSS property property that is a supported CSS property, except for
    // properties that have no "-" (U+002D) in the property name, the following partial
    // interface applies where dashed attribute is property.
    // Example: font-size -> element.style['font-size']
    // Example: -webkit-transform -> element.style.['-webkit-transform']
    // [CEReactions] attribute [LegacyNullToEmptyString] CSSOMString _dashed_attribute;
EOF
foreach my $nameOrAlias (grep { $_ =~ /\-/ } @namesAndAliases) {
    my $dashedAttributeName = $nameOrAlias;
    my $name = $namesAndAliasesToName{$nameOrAlias};
    my $propertyId = $nameToId{$namesAndAliasesToName{$name}};

    my @extendedAttributeValues = ("DelegateToSharedSyntheticAttribute=propertyValueForDashedIDLAttribute", "CallWith=PropertyName");
    push(@extendedAttributeValues, "EnabledBySetting=${settingsFlags{$name}}") if $settingsFlags{$name};
    push(@extendedAttributeValues, "EnabledByDeprecatedGlobalSetting=Enabled${runtimeFlags{$name}}") if $runtimeFlags{$name};
    my $extendedAttributes = join(", ", @extendedAttributeValues);

    print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL "    [CEReactions, ${extendedAttributes}] attribute [LegacyNullToEmptyString] CSSOMString ${dashedAttributeName};\n";
}

# Everything below here is non-standard.

print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";

    // Non-standard. Special case properties starting with -epub- like is done for
    // -webkit-, where attribute is obtained by running the CSS property to IDL attribute
    // algorithm for property, with the lowercase first flag set.
    // Example: -epub-caption-side -> element.style.epubCaptionSide
EOF
foreach my $nameOrAlias (grep { $_ =~ /^\-epub\-/ } @namesAndAliases) {
    my $epubCasedAttributeName = cssPropertyToIDLAttribute($nameOrAlias, 1, 0);
    my $name = $namesAndAliasesToName{$nameOrAlias};
    my $propertyId = $nameToId{$namesAndAliasesToName{$name}};

    my @extendedAttributeValues = ("DelegateToSharedSyntheticAttribute=propertyValueForEpubCasedIDLAttribute", "CallWith=PropertyName");
    push(@extendedAttributeValues, "EnabledBySetting=${settingsFlags{$name}}") if $settingsFlags{$name};
    push(@extendedAttributeValues, "EnabledByDeprecatedGlobalSetting=Enabled${runtimeFlags{$name}}") if $runtimeFlags{$name};
    my $extendedAttributes = join(", ", @extendedAttributeValues);

    print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL "    [CEReactions, ${extendedAttributes}] attribute [LegacyNullToEmptyString] CSSOMString ${epubCasedAttributeName};\n";
}

print CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL << "EOF";
};

EOF

close CSS_STYLE_DECLARATION_PROPERTY_NAMES_IDL;
