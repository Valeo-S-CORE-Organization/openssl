# *******************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Apache License Version 2.0 which is available at
# https://www.apache.org/licenses/LICENSE-2.0
#
# SPDX-License-Identifier: Apache-2.0
# *******************************************************************************

"""Generate OpenSSL FFI metadata from the selected implementation's CcInfo."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _header(headers, name):
    """Return the input artifact and path for a named OpenSSL header.

    Prefer original files over virtual-include symlinks, falling back to the
    known path inside a single include-tree artifact. Fail on missing or
    ambiguous artifacts.
    """
    matches = [header for header in headers if not header.is_directory and header.basename == name]

    # cc_library may also publish virtual-include symlinks to the same headers.
    originals = [header for header in matches if "/_virtual_includes/" not in header.path]
    if originals:
        matches = originals
    if len(matches) == 1:
        return matches[0], matches[0].path
    if not matches:
        directories = [header for header in headers if header.is_directory]
        if len(directories) == 1:
            # rules_foreign_cc exposes the installed include tree as one artifact.
            return directories[0], directories[0].path + "/openssl/" + name
    fail("Expected one OpenSSL {} header (or one include tree) in implementation CcInfo".format(name))

def _openssl_build_info_impl(ctx):
    """Register an action extracting metadata from the selected CcInfo headers."""
    headers = ctx.attr.implementation[CcInfo].compilation_context.headers.to_list()
    version_header, version_path = _header(headers, "opensslv.h")
    configuration_header, configuration_path = _header(headers, "configuration.h")
    output = ctx.actions.declare_file(ctx.label.name + ".txt")

    ctx.actions.run_shell(
        inputs = depset([version_header, configuration_header]),
        outputs = [output],
        arguments = [version_path, configuration_path, output.path],
        command = """
set -eu
export LC_ALL=C
awk '{ sub(/^[[:space:]]*#[[:space:]]*/, "") }
$1 == "define" && $2 == "OPENSSL_VERSION_STR" && $3 ~ /^"[0-9]+[.][0-9]+[.][0-9]+"$/ {
    gsub(/"/, "", $3)
    print $3
    found = 1
}
END {
    if (!found) {
        print "ERROR: OPENSSL_VERSION_STR missing or invalid in selected OpenSSL implementation" > "/dev/stderr"
        exit 1
    }
}' "$1" > "$3"
features=$(awk '{ sub(/^[[:space:]]*#[[:space:]]*/, "") }
$1 == "define" && $2 ~ /^OPENSSL_NO_[A-Z0-9_]+$/ { print $2 }' "$2")
printf '%s\n' "$features" | sort -u | paste -sd, >> "$3"
""",
        mnemonic = "OpenSSLBuildInfo",
    )
    return [DefaultInfo(files = depset([output]))]

openssl_build_info = rule(
    implementation = _openssl_build_info_impl,
    attrs = {
        "implementation": attr.label(
            mandatory = True,
            providers = [CcInfo],
        ),
    },
)
