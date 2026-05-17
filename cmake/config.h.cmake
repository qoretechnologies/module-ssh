/* config.h.cmake

   Configure-time feature probes for the Qore ssh module.

   Copyright (C) 2026 Qore Technologies, s.r.o.
*/

#ifndef _QORE_MODULE_SSH_CONFIG_H
#define _QORE_MODULE_SSH_CONFIG_H

/* Defined when the linked libssh provides the >= 0.11.0 file-format export
   API (ssh_file_format_e and the *_format() export functions). Probed with
   check_symbol_exists() against ssh_pki_export_privkey_file_format. */
#cmakedefine HAVE_SSH_FILE_FORMAT

#endif
