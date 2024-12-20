#
# Copyright OpenEmbedded Contributors
#
# SPDX-License-Identifier: MIT
#

##
## Purpose:
## This class is used to update the list of crates in SRC_URI
## by reading Cargo.lock in the source tree.
##
## See meta/recipes-devtools/python/python3-bcrypt_*.bb for an example
##
## To perform the update: bitbake -c update_crates recipe-name

addtask do_update_crates after do_patch
do_update_crates[depends] = "python3-native:do_populate_sysroot"
do_update_crates[nostamp] = "1"
do_update_crates[doc] = "Update the recipe by reading Cargo.lock and write in ${THISDIR}/${BPN}-crates.inc"

RECIPE_UPGRADE_EXTRA_TASKS += "do_update_crates"

# The directory where to search for Cargo.lock files
CARGO_LOCK_SRC_DIR ??= "${S}"

do_update_crates() {
    TARGET_FILE="${THISDIR}/${BPN}-crates.inc"

    nativepython3 - <<EOF

def get_crates(f):
    import tomllib
    c_list = '# from %s' % os.path.relpath(f, '${CARGO_LOCK_SRC_DIR}')
    c_list += '\nSRC_URI += " \\\'
    crates = tomllib.load(open(f, 'rb'))

    # Build a list with crates info that have crates.io in the source
    crates_candidates = list(filter(lambda c: 'crates.io' in c.get('source', ''), crates['package']))

    if not crates_candidates:
        raise ValueError("Unable to find any candidate crates that use crates.io")

    # Update crates uri and their checksum, to avoid name clashing on the checksum
    # we need to rename crates with name and version to have a unique key
    cksum_list = ''
    for c in crates_candidates:
        rename = "%s-%s" % (c['name'], c['version'])
        c_list += '\n    crate://crates.io/%s/%s \\\' % (c['name'], c['version'])
        if 'checksum' in c:
            cksum_list += '\nSRC_URI[%s.sha256sum] = "%s"' % (rename, c['checksum'])

    c_list += '\n"\n'
    c_list += cksum_list
    c_list += '\n'
    return c_list

import os
crates = "# Autogenerated with 'bitbake -c update_crates ${PN}'\n\n"
found = False
for root, dirs, files in os.walk('${CARGO_LOCK_SRC_DIR}'):
    # ignore git and patches directories
    if root.startswith(os.path.join('${CARGO_LOCK_SRC_DIR}', '.pc')):
        continue
    if root.startswith(os.path.join('${CARGO_LOCK_SRC_DIR}', '.git')):
        continue
    for file in files:
        if file == 'Cargo.lock':
            try:
                cargo_lock_path = os.path.join(root, file)
                crates += get_crates(os.path.join(root, file))
            except Exception as e:
                raise ValueError("Cannot parse '%s'" % cargo_lock_path) from e
            else:
                found = True
if not found:
    raise ValueError("Unable to find any Cargo.lock in ${CARGO_LOCK_SRC_DIR}")
open("${TARGET_FILE}", 'w').write(crates)
EOF

    bbnote "Successfully update crates inside '${TARGET_FILE}'"
}
