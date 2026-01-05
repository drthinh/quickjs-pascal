/*
 * QuickJS Archive (QAR) Reader
 * 
 * Implementation for reading QAR files
 *
 * Copyright (c) 2024
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

#include "cutils.h"
#include "qar.h"

/* Disable unused-function warnings for miniz header */
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#endif
#include "miniz/miniz.h"
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

#define QAR_MAGIC "QAR\x01"
#define QAR_MAGIC_SIZE 4

typedef struct {
    char *path;
    uint32_t path_len;
    uint64_t offset;
    uint64_t bytecode_offset;  // Offset to bytecode data
    uint32_t flags;
    uint64_t bytecode_size;      // Size in file (compressed if flags & 2)
    uint64_t source_size;         // Size in file (compressed if flags & 2)
    uint64_t bytecode_orig_size;  // Original uncompressed size
    uint64_t source_orig_size;    // Original uncompressed size
    uint8_t *bytecode_cache;
    uint8_t *source_cache;
} QarEntryInternal;

struct QarFile {
    FILE *file;
    uint32_t version;
    uint64_t manifest_offset;
    uint64_t manifest_size;
    char *manifest_json;
    char *quickjs_version;
    QarEntryInternal *entries;
    int entry_count;
    uint64_t entries_offset;
};

static uint32_t read_u32(FILE *f)
{
    uint32_t v;
    if (fread(&v, 4, 1, f) != 1)
        return 0;
    return v;
}

static uint64_t read_u64(FILE *f)
{
    uint64_t v;
    if (fread(&v, 8, 1, f) != 1)
        return 0;
    return v;
}


QarFile *qar_open(const char *filename)
{
    FILE *f = fopen(filename, "rb");
    if (!f)
        return NULL;
    
    QarFile *qar = calloc(1, sizeof(QarFile));
    if (!qar) {
        fclose(f);
        return NULL;
    }
    
    qar->file = f;
    
    // Read magic
    char magic[QAR_MAGIC_SIZE];
    if (fread(magic, 1, QAR_MAGIC_SIZE, f) != QAR_MAGIC_SIZE ||
        memcmp(magic, QAR_MAGIC, QAR_MAGIC_SIZE) != 0) {
        free(qar);
        fclose(f);
        return NULL;
    }
    
    // Read version
    qar->version = read_u32(f);
    
    // Read manifest offset and size
    qar->manifest_offset = read_u64(f);
    qar->manifest_size = read_u64(f);
    
    // Read entry count
    qar->entry_count = read_u32(f);
    qar->entries_offset = ftell(f);
    
    if (qar->entry_count < 0 || qar->entry_count > 100000) {
        free(qar);
        fclose(f);
        return NULL;
    }
    
    // Allocate entries
    qar->entries = calloc(qar->entry_count, sizeof(QarEntryInternal));
    if (!qar->entries) {
        free(qar);
        fclose(f);
        return NULL;
    }
    
    // Read entries
    int i;
    for (i = 0; i < qar->entry_count; i++) {
        QarEntryInternal *e = &qar->entries[i];
        e->offset = ftell(f);
        
        // Read path
        uint32_t path_len = read_u32(f);
        e->path_len = path_len;
        if (path_len == 0 || path_len > 65536) {
            // Cleanup
            for (int j = 0; j < i; j++) {
                free(qar->entries[j].path);
            }
            free(qar->entries);
            free(qar);
            fclose(f);
            return NULL;
        }
        e->path = malloc(path_len + 1);
        if (!e->path) {
            // Cleanup
            for (int j = 0; j < i; j++) {
                free(qar->entries[j].path);
            }
            free(qar->entries);
            free(qar);
            fclose(f);
            return NULL;
        }
        if (fread(e->path, 1, path_len, f) != path_len) {
            free(e->path);
            // Cleanup
            for (int j = 0; j < i; j++) {
                free(qar->entries[j].path);
            }
            free(qar->entries);
            free(qar);
            fclose(f);
            return NULL;
        }
        e->path[path_len] = '\0';
        
        e->flags = read_u32(f);
        e->bytecode_size = read_u64(f);
        e->source_size = read_u64(f);
        
        // For compressed entries, read original sizes
        if (e->flags & 2) {
            e->bytecode_orig_size = read_u64(f);
            e->source_orig_size = read_u64(f);
        } else {
            e->bytecode_orig_size = e->bytecode_size;
            e->source_orig_size = e->source_size;
        }
        
        // Save bytecode offset
        e->bytecode_offset = ftell(f);
        
        // Skip to next entry
        fseek(f, e->bytecode_size + e->source_size, SEEK_CUR);
    }
    
    // Read manifest
    fseek(f, qar->manifest_offset, SEEK_SET);
    qar->manifest_json = malloc(qar->manifest_size + 1);
    if (qar->manifest_json) {
        if (fread(qar->manifest_json, 1, qar->manifest_size, f) == qar->manifest_size) {
            qar->manifest_json[qar->manifest_size] = '\0';
            
            // Extract QuickJS version from manifest (simple parsing)
            const char *ver_str = strstr(qar->manifest_json, "\"quickjs_version\"");
            if (ver_str) {
                ver_str = strchr(ver_str, '"');
                if (ver_str) {
                    ver_str++;
                    const char *ver_end = strchr(ver_str, '"');
                    if (ver_end) {
                        size_t ver_len = ver_end - ver_str;
                        qar->quickjs_version = malloc(ver_len + 1);
                        if (qar->quickjs_version) {
                            memcpy(qar->quickjs_version, ver_str, ver_len);
                            qar->quickjs_version[ver_len] = '\0';
                        }
                    }
                }
            }
        }
    }
    
    return qar;
}

void qar_close(QarFile *qar)
{
    if (!qar)
        return;
    
    if (qar->file)
        fclose(qar->file);
    
    if (qar->entries) {
        int i;
        for (i = 0; i < qar->entry_count; i++) {
            free(qar->entries[i].path);
            free(qar->entries[i].bytecode_cache);
            free(qar->entries[i].source_cache);
        }
        free(qar->entries);
    }
    
    free(qar->manifest_json);
    free(qar->quickjs_version);
    free(qar);
}

int qar_get_entry_count(QarFile *qar)
{
    return qar ? qar->entry_count : 0;
}

static QarEntryInternal *get_entry_internal(QarFile *qar, int index)
{
    if (!qar || index < 0 || index >= qar->entry_count)
        return NULL;
    return &qar->entries[index];
}

const QarEntry *qar_get_entry(QarFile *qar, int index)
{
    return (const QarEntry *)get_entry_internal(qar, index);
}

const QarEntry *qar_find_entry(QarFile *qar, const char *path)
{
    if (!qar || !path)
        return NULL;
    
    int i;
    for (i = 0; i < qar->entry_count; i++) {
        if (strcmp(qar->entries[i].path, path) == 0)
            return (const QarEntry *)&qar->entries[i];
    }
    return NULL;
}

const char *qar_entry_get_path(const QarEntry *entry)
{
    const QarEntryInternal *e = (const QarEntryInternal *)entry;
    return e ? e->path : NULL;
}

int qar_entry_get_type(const QarEntry *entry)
{
    const QarEntryInternal *e = (const QarEntryInternal *)entry;
    return e ? (e->flags & 1) : 0;
}

int qar_entry_load_data(QarFile *qar, const QarEntry *entry)
{
    if (!qar || !entry || !qar->file)
        return -1;
    
    QarEntryInternal *e = (QarEntryInternal *)entry;
    
    // Verify entry belongs to this QAR (simple check)
    if (e < qar->entries || e >= qar->entries + qar->entry_count)
        return -1;
    
    // Load bytecode if not cached
    if (!e->bytecode_cache && e->bytecode_size > 0) {
        fprintf(stderr, "[QAR DEBUG] Loading bytecode for entry: %s, size: %llu, offset: %llu\n", 
                e->path, (unsigned long long)e->bytecode_size, (unsigned long long)e->bytecode_offset);
        
        fseek(qar->file, e->bytecode_offset, SEEK_SET);
        long pos = ftell(qar->file);
        if (pos != (long)e->bytecode_offset) {
            fprintf(stderr, "[QAR DEBUG] Failed to seek to bytecode offset: expected %llu, got %ld\n",
                    (unsigned long long)e->bytecode_offset, pos);
            return -1;
        }
        
        // Read compressed data
        uint8_t *compressed_data = malloc(e->bytecode_size);
        if (!compressed_data) {
            fprintf(stderr, "[QAR DEBUG] Failed to allocate memory for compressed bytecode\n");
            return -1;
        }
        
        size_t read_bytes = fread(compressed_data, 1, e->bytecode_size, qar->file);
        if (read_bytes != e->bytecode_size) {
            fprintf(stderr, "[QAR DEBUG] Failed to read bytecode: expected %llu bytes, got %zu bytes\n",
                    (unsigned long long)e->bytecode_size, read_bytes);
            free(compressed_data);
            return -1;
        }
        
        // Decompress if needed
        if (e->flags & 2) {
            // Compressed - decompress
            mz_ulong dest_len = (mz_ulong)e->bytecode_orig_size;
            e->bytecode_cache = malloc(dest_len);
            if (!e->bytecode_cache) {
                free(compressed_data);
                return -1;
            }
            
            int ret = mz_uncompress(e->bytecode_cache, &dest_len, compressed_data, (mz_ulong)e->bytecode_size);
            free(compressed_data);
            if (ret != MZ_OK) {
                fprintf(stderr, "[QAR DEBUG] Failed to decompress bytecode: %d\n", ret);
                free(e->bytecode_cache);
                e->bytecode_cache = NULL;
                return -1;
            }
        } else {
            // Not compressed - use directly
            e->bytecode_cache = compressed_data;
        }
        
        fprintf(stderr, "[QAR DEBUG] Successfully loaded bytecode: %zu bytes, first 4 bytes: %02x %02x %02x %02x\n",
                e->bytecode_orig_size, 
                e->bytecode_cache[0], e->bytecode_cache[1], 
                e->bytecode_cache[2], e->bytecode_cache[3]);
    } else if (e->bytecode_size == 0) {
        fprintf(stderr, "[QAR DEBUG] Entry %s has zero bytecode size\n", e->path);
    }
    
    // Load source if not cached
    if (!e->source_cache && e->source_size > 0) {
        // Source comes right after bytecode
        fseek(qar->file, e->bytecode_offset + e->bytecode_size, SEEK_SET);
        
        // Read compressed data
        uint8_t *compressed_data = malloc(e->source_size);
        if (!compressed_data)
            return -1;
        
        if (fread(compressed_data, 1, e->source_size, qar->file) != e->source_size) {
            free(compressed_data);
            return -1;
        }
        
        // Decompress if needed
        if (e->flags & 2) {
            // Compressed - decompress
            mz_ulong dest_len = (mz_ulong)e->source_orig_size;
            e->source_cache = malloc(dest_len);
            if (!e->source_cache) {
                free(compressed_data);
                return -1;
            }
            
            int ret = mz_uncompress(e->source_cache, &dest_len, compressed_data, (mz_ulong)e->source_size);
            free(compressed_data);
            if (ret != MZ_OK) {
                fprintf(stderr, "[QAR DEBUG] Failed to decompress source: %d\n", ret);
                free(e->source_cache);
                e->source_cache = NULL;
                return -1;
            }
        } else {
            // Not compressed - use directly
            e->source_cache = compressed_data;
        }
    }
    
    return 0;
}

const uint8_t *qar_entry_get_bytecode(const QarEntry *entry, size_t *len)
{
    const QarEntryInternal *e = (const QarEntryInternal *)entry;
    if (!e) {
        fprintf(stderr, "[QAR DEBUG] qar_entry_get_bytecode: entry is NULL\n");
        if (len) *len = 0;
        return NULL;
    }
    
    // Return NULL if bytecode not loaded or size is 0
    if (!e->bytecode_cache || e->bytecode_orig_size == 0) {
        fprintf(stderr, "[QAR DEBUG] qar_entry_get_bytecode: entry %s - bytecode_cache=%p, bytecode_orig_size=%llu\n",
                e->path, e->bytecode_cache, (unsigned long long)e->bytecode_orig_size);
        if (len) *len = 0;
        return NULL;
    }
    
    fprintf(stderr, "[QAR DEBUG] qar_entry_get_bytecode: entry %s - returning bytecode, size=%llu\n",
            e->path, (unsigned long long)e->bytecode_orig_size);
    if (len) *len = e->bytecode_orig_size;
    return e->bytecode_cache;
}

const uint8_t *qar_entry_get_source(const QarEntry *entry, size_t *len)
{
    const QarEntryInternal *e = (const QarEntryInternal *)entry;
    if (!e) {
        if (len) *len = 0;
        return NULL;
    }
    
    if (len) *len = e->source_orig_size;
    return e->source_cache;
}

const char *qar_get_manifest(QarFile *qar, size_t *len)
{
    if (!qar)
        return NULL;
    if (len)
        *len = qar->manifest_size;
    return qar->manifest_json;
}

const char *qar_get_quickjs_version(QarFile *qar)
{
    return qar ? qar->quickjs_version : NULL;
}

