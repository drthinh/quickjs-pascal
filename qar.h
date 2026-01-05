/*
 * QuickJS Archive (QAR) Reader
 * 
 * Header file for reading QAR files
 *
 * Copyright (c) 2024
 */

#ifndef QAR_H
#define QAR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QarFile QarFile;
typedef struct QarEntry QarEntry;

/* Open a QAR file */
QarFile *qar_open(const char *filename);

/* Close a QAR file */
void qar_close(QarFile *qar);

/* Get number of entries in QAR */
int qar_get_entry_count(QarFile *qar);

/* Get entry by index */
const QarEntry *qar_get_entry(QarFile *qar, int index);

/* Find entry by path */
const QarEntry *qar_find_entry(QarFile *qar, const char *path);

/* Get entry path */
const char *qar_entry_get_path(const QarEntry *entry);

/* Get entry type (1 = module, 0 = script) */
int qar_entry_get_type(const QarEntry *entry);

/* Get bytecode data */
const uint8_t *qar_entry_get_bytecode(const QarEntry *entry, size_t *len);

/* Get source code data */
const uint8_t *qar_entry_get_source(const QarEntry *entry, size_t *len);

/* Load entry data (bytecode and source) into cache */
int qar_entry_load_data(QarFile *qar, const QarEntry *entry);

/* Get manifest JSON as string */
const char *qar_get_manifest(QarFile *qar, size_t *len);

/* Get QuickJS version from manifest */
const char *qar_get_quickjs_version(QarFile *qar);

#ifdef __cplusplus
}
#endif

#endif /* QAR_H */

