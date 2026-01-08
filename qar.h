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

/* Export declarations for DLL */
#ifdef _WIN32
    #ifdef BUILD_QJS_DLL
        #define QAR_EXPORT __declspec(dllexport)
    #elif defined(USE_QJS_DLL)
        #define QAR_EXPORT __declspec(dllimport)
    #else
        #define QAR_EXPORT
    #endif
#elif defined(__GNUC__) || defined(__clang__)
    #ifdef BUILD_QJS_DLL
        #define QAR_EXPORT __attribute__((visibility("default")))
    #else
        #define QAR_EXPORT
    #endif
#else
    #define QAR_EXPORT
#endif

typedef struct QarFile QarFile;
typedef struct QarEntry QarEntry;

/* Open a QAR file */
QAR_EXPORT QarFile *qar_open(const char *filename);

/* Close a QAR file */
QAR_EXPORT void qar_close(QarFile *qar);

/* Get number of entries in QAR */
QAR_EXPORT int qar_get_entry_count(QarFile *qar);

/* Get entry by index */
QAR_EXPORT const QarEntry *qar_get_entry(QarFile *qar, int index);

/* Find entry by path */
QAR_EXPORT const QarEntry *qar_find_entry(QarFile *qar, const char *path);

/* Get entry path */
QAR_EXPORT const char *qar_entry_get_path(const QarEntry *entry);

/* Get entry type (1 = module, 0 = script, 2 = asset) */
QAR_EXPORT int qar_entry_get_type(const QarEntry *entry);

/* Get bytecode data */
QAR_EXPORT const uint8_t *qar_entry_get_bytecode(const QarEntry *entry, size_t *len);

/* Get source code data */
QAR_EXPORT const uint8_t *qar_entry_get_source(const QarEntry *entry, size_t *len);

/* Load entry data (bytecode and source) into cache */
QAR_EXPORT int qar_entry_load_data(QarFile *qar, const QarEntry *entry);

/* Get manifest JSON as string */
QAR_EXPORT const char *qar_get_manifest(QarFile *qar, size_t *len);

/* Get QuickJS version from manifest */
QAR_EXPORT const char *qar_get_quickjs_version(QarFile *qar);

#ifdef __cplusplus
}
#endif

#endif /* QAR_H */

