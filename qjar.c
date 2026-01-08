/*
 * QuickJS Archive (QAR) Packager
 * 
 * Creates QAR files containing compiled bytecode, source code, and manifest
 * Similar to Java JAR format
 *
 * Copyright (c) 2024
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <inttypes.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <io.h>
#define stat _stat
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#else
#include <unistd.h>
#include <dirent.h>
#include <sys/types.h>
#endif

#include "cutils.h"
#include "quickjs-libc.h"
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
#define QAR_VERSION 1

typedef struct {
    char *path;      // Path in archive (e.g., "lib/utils.js")
    char *filepath;  // Real file path
    uint8_t *bytecode;
    size_t bytecode_len;
    uint8_t *source;
    size_t source_len;
    int is_module;   // 1 if ES module, 0 if script
    int is_asset;    // 1 if non-JS asset
    uint8_t *bytecode_compressed;  // Compressed bytecode
    size_t bytecode_compressed_len;
    uint8_t *source_compressed;     // Compressed source (or asset payload)
    size_t source_compressed_len;
    int is_compressed;  // 1 if compressed, 0 if not
} QarEntry;

typedef struct {
    QarEntry *entries;
    int count;
    int size;
} QarEntryList;

static void qar_entry_list_init(QarEntryList *list)
{
    list->entries = NULL;
    list->count = 0;
    list->size = 0;
}

static void qar_entry_list_add(QarEntryList *list, const char *path, 
                                const char *filepath, uint8_t *bytecode, 
                                size_t bytecode_len, uint8_t *source, 
                                size_t source_len, int is_module, int is_asset)
{
    if (list->count == list->size) {
        int newsize = list->size + (list->size >> 1) + 4;
        QarEntry *e = realloc(list->entries, sizeof(QarEntry) * newsize);
        if (!e) {
            fprintf(stderr, "Memory allocation error\n");
            exit(1);
        }
        list->entries = e;
        list->size = newsize;
    }
    
    QarEntry *entry = &list->entries[list->count++];
    entry->path = strdup(path);
    entry->filepath = strdup(filepath);
    entry->bytecode = bytecode;
    entry->bytecode_len = bytecode_len;
    entry->source = source;
    entry->source_len = source_len;
    entry->is_module = is_module;
    entry->is_asset = is_asset;
    entry->bytecode_compressed = NULL;
    entry->bytecode_compressed_len = 0;
    entry->source_compressed = NULL;
    entry->source_compressed_len = 0;
    entry->is_compressed = 0;
}

static void qar_entry_list_free(QarEntryList *list)
{
    int i;
    for (i = 0; i < list->count; i++) {
        QarEntry *e = &list->entries[i];
        free(e->path);
        free(e->filepath);
        free(e->bytecode);
        free(e->source);
        free(e->bytecode_compressed);
        free(e->source_compressed);
    }
    free(list->entries);
    list->entries = NULL;
    list->count = 0;
    list->size = 0;
}

static int is_js_file(const char *filename)
{
    return js__has_suffix(filename, ".js") || js__has_suffix(filename, ".mjs");
}

static int is_asset_file(const char *filename)
{
    /* Allow common asset extensions; can be extended later */
    return js__has_suffix(filename, ".json") ||
           js__has_suffix(filename, ".png")  ||
           js__has_suffix(filename, ".jpg")  ||
           js__has_suffix(filename, ".jpeg") ||
           js__has_suffix(filename, ".gif")  ||
           js__has_suffix(filename, ".mp3")  ||
           js__has_suffix(filename, ".ogg")  ||
           js__has_suffix(filename, ".wav")  ||
           js__has_suffix(filename, ".mp4")  ||
           js__has_suffix(filename, ".webp") ||
           js__has_suffix(filename, ".svg");
}

static void normalize_path(char *path)
{
    char *p = path;
    while (*p) {
        if (*p == '\\') *p = '/';
        p++;
    }
}

static void add_file_to_list(QarEntryList *list, const char *base_dir, 
                              const char *filepath)
{
    struct stat st;
    if (stat(filepath, &st) != 0) {
        fprintf(stderr, "Cannot stat file: %s\n", filepath);
        return;
    }
    
    if (S_ISDIR(st.st_mode)) {
        // Recursively add directory contents
#ifdef _WIN32
        char pattern[1024];
        WIN32_FIND_DATA findData;
        HANDLE hFind;
        
        snprintf(pattern, sizeof(pattern), "%s\\*", filepath);
        hFind = FindFirstFile(pattern, &findData);
        if (hFind != INVALID_HANDLE_VALUE) {
            do {
                if (strcmp(findData.cFileName, ".") == 0 || 
                    strcmp(findData.cFileName, "..") == 0)
                    continue;
                    
                char fullpath[1024];
                snprintf(fullpath, sizeof(fullpath), "%s\\%s", filepath, findData.cFileName);
                
                if (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                    add_file_to_list(list, base_dir, fullpath);
                } else if (is_js_file(findData.cFileName) || is_asset_file(findData.cFileName)) {
                    add_file_to_list(list, base_dir, fullpath);
                }
            } while (FindNextFile(hFind, &findData));
            FindClose(hFind);
        }
#else
        DIR *dir = opendir(filepath);
        if (dir) {
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL) {
                if (strcmp(entry->d_name, ".") == 0 || 
                    strcmp(entry->d_name, "..") == 0)
                    continue;
                    
                char fullpath[1024];
                snprintf(fullpath, sizeof(fullpath), "%s/%s", filepath, entry->d_name);
                
                struct stat entry_st;
                if (stat(fullpath, &entry_st) == 0) {
                    if (S_ISDIR(entry_st.st_mode)) {
                        add_file_to_list(list, base_dir, fullpath);
                    } else if (is_js_file(entry->d_name) || is_asset_file(entry->d_name)) {
                        add_file_to_list(list, base_dir, fullpath);
                    }
                }
            }
            closedir(dir);
        }
#endif
    } else if (is_js_file(filepath) || is_asset_file(filepath)) {
        // Add single file - will be compiled later
        char rel_path[1024];
        size_t base_len = strlen(base_dir);
        if (strncmp(filepath, base_dir, base_len) == 0) {
            const char *rel = filepath + base_len;
            if (*rel == '/' || *rel == '\\') rel++;
            js__pstrcpy(rel_path, sizeof(rel_path), rel);
        } else {
            const char *basename = strrchr(filepath, '/');
            if (!basename) basename = strrchr(filepath, '\\');
            if (basename) basename++;
            else basename = filepath;
            js__pstrcpy(rel_path, sizeof(rel_path), basename);
        }
        normalize_path(rel_path);
        
        int is_js = is_js_file(filepath);
        qar_entry_list_add(list, rel_path, filepath, NULL, 0, NULL, 0, is_js, !is_js);
    }
}

static JSModuleDef *qjar_module_loader(JSContext *ctx,
                                       const char *module_name, void *opaque)
{
    // Dummy loader for compilation
    JSModuleDef *m = JS_NewCModule(ctx, module_name, NULL);
    return m;
}

static int compile_and_add_entry(JSContext *ctx, QarEntry *entry)
{
    uint8_t *buf;
    size_t buf_len;
    JSValue obj;
    int eval_flags;
    int is_module;
    
    if (entry->is_asset) {
        /* Asset: store raw bytes as "source", no bytecode */
        buf = js_load_file(ctx, &buf_len, entry->filepath);
        if (!buf) {
            fprintf(stderr, "Could not load asset file: %s\n", entry->filepath);
            return -1;
        }
        entry->source = malloc(buf_len);
        if (!entry->source) {
            js_free(ctx, buf);
            return -1;
        }
        memcpy(entry->source, buf, buf_len);
        entry->source_len = buf_len;
        entry->bytecode = NULL;
        entry->bytecode_len = 0;
        entry->is_module = 0;
        js_free(ctx, buf);
        return 0;
    }

    /* JavaScript entry */
    buf = js_load_file(ctx, &buf_len, entry->filepath);
    if (!buf) {
        fprintf(stderr, "Could not load file: %s\n", entry->filepath);
        return -1;
    }
    
    // Save source code
    entry->source = malloc(buf_len);
    if (!entry->source) {
        js_free(ctx, buf);
        return -1;
    }
    memcpy(entry->source, buf, buf_len);
    entry->source_len = buf_len;
    
    // Detect module type
    is_module = (js__has_suffix(entry->filepath, ".mjs") ||
                 JS_DetectModule((const char *)buf, buf_len));
    entry->is_module = is_module;
    
    // Compile to bytecode
    eval_flags = JS_EVAL_FLAG_COMPILE_ONLY;
    if (is_module)
        eval_flags |= JS_EVAL_TYPE_MODULE;
    else
        eval_flags |= JS_EVAL_TYPE_GLOBAL;
    
    obj = JS_Eval(ctx, (const char *)buf, buf_len, entry->filepath, eval_flags);
    js_free(ctx, buf);
    
    if (JS_IsException(obj)) {
        fprintf(stderr, "Compilation error in %s:\n", entry->filepath);
        js_std_dump_error(ctx);
        return -1;
    }
    
    // Write bytecode
    int flags = JS_WRITE_OBJ_BYTECODE | JS_WRITE_OBJ_REFERENCE;
    entry->bytecode = JS_WriteObject(ctx, &entry->bytecode_len, obj, flags);
    JS_FreeValue(ctx, obj);
    
    if (!entry->bytecode) {
        fprintf(stderr, "Failed to write bytecode for %s\n", entry->filepath);
        return -1;
    }
    
    return 0;
}

static void write_string(FILE *f, const char *str)
{
    uint32_t len = strlen(str);
    fwrite(&len, 4, 1, f);
    fwrite(str, 1, len, f);
}

/* Compress data using miniz */
static int compress_data(const uint8_t *src, size_t src_len, 
                         uint8_t **dst, size_t *dst_len)
{
    mz_ulong dest_len = mz_compressBound((mz_ulong)src_len);
    uint8_t *compressed = malloc(dest_len);
    if (!compressed)
        return -1;
    
    int ret = mz_compress2(compressed, &dest_len, src, (mz_ulong)src_len, MZ_DEFAULT_LEVEL);
    if (ret != MZ_OK) {
        free(compressed);
        return -1;
    }
    
    *dst = compressed;
    *dst_len = (size_t)dest_len;
    return 0;
}

/* Compress entry data - always compress to prevent code modification/corruption/injection */
static void compress_entry(QarEntry *entry)
{
    // Always compress to prevent code modification, corruption, or bytecode injection
    uint8_t *bytecode_compressed = NULL;
    size_t bytecode_compressed_len = 0;
    uint8_t *source_compressed = NULL;
    size_t source_compressed_len = 0;
    
    // Compress bytecode - always compress
    if (entry->bytecode_len > 0) {
        if (compress_data(entry->bytecode, entry->bytecode_len, 
                         &bytecode_compressed, &bytecode_compressed_len) == 0) {
            // Always use compressed version to prevent tampering
            entry->bytecode_compressed = bytecode_compressed;
            entry->bytecode_compressed_len = bytecode_compressed_len;
        }
    }
    
    // Compress source - always compress
    if (entry->source_len > 0) {
        if (compress_data(entry->source, entry->source_len, 
                         &source_compressed, &source_compressed_len) == 0) {
            // Always use compressed version to prevent tampering
            entry->source_compressed = source_compressed;
            entry->source_compressed_len = source_compressed_len;
        }
    }
    
    // Mark as compressed if either is compressed (should always be true now)
    if (entry->bytecode_compressed || entry->source_compressed) {
        entry->is_compressed = 1;
    }
}

static void write_manifest(FILE *f, QarEntryList *list, const char *qjs_version)
{
    // Write manifest as JSON
    fprintf(f, "{\n");
    fprintf(f, "  \"format\": \"qar\",\n");
    fprintf(f, "  \"version\": %d,\n", QAR_VERSION);
    fprintf(f, "  \"quickjs_version\": \"%s\",\n", qjs_version);
    fprintf(f, "  \"entries\": [\n");
    
    int i;
    for (i = 0; i < list->count; i++) {
        QarEntry *e = &list->entries[i];
        fprintf(f, "    {\n");
        fprintf(f, "      \"path\": \"%s\",\n", e->path);
        const char *kind = e->is_asset ? "asset" : (e->is_module ? "module" : "script");
        fprintf(f, "      \"type\": \"%s\",\n", kind);
        fprintf(f, "      \"bytecode_size\": %zu,\n", e->bytecode_len);
        fprintf(f, "      \"source_size\": %zu\n", e->source_len);
        fprintf(f, "    }%s\n", i < list->count - 1 ? "," : "");
    }
    
    fprintf(f, "  ]\n");
    fprintf(f, "}\n");
}

static int create_qar(const char *output_file, QarEntryList *list, 
                      const char *qjs_version)
{
    FILE *f = fopen(output_file, "wb");
    if (!f) {
        fprintf(stderr, "Cannot create output file: %s\n", output_file);
        return -1;
    }
    
    // Write magic and version
    fwrite(QAR_MAGIC, 1, QAR_MAGIC_SIZE, f);
    uint32_t version = QAR_VERSION;
    fwrite(&version, 4, 1, f);
    
    // Write manifest offset placeholder (will update later)
    uint64_t manifest_offset = 0;
    uint64_t manifest_size = 0;
    uint64_t manifest_offset_pos = ftell(f);
    fwrite(&manifest_offset, 8, 1, f);
    fwrite(&manifest_size, 8, 1, f);
    
    // Write entries
    fwrite(&list->count, 4, 1, f);
    
    int i;
    for (i = 0; i < list->count; i++) {
        QarEntry *e = &list->entries[i];
        
        // Compress entry data
        compress_entry(e);
        
        // Write entry header
        write_string(f, e->path);
        uint32_t flags = e->is_module ? 1 : 0;
        if (e->is_compressed)
            flags |= 2;  // Bit 1 = compressed
        if (e->is_asset)
            flags |= 4;  // Bit 2 = asset
        fwrite(&flags, 4, 1, f);
        
        // Write sizes - use compressed sizes if available, otherwise original
        uint64_t bytecode_size = e->bytecode_compressed ? e->bytecode_compressed_len : e->bytecode_len;
        uint64_t source_size = e->source_compressed ? e->source_compressed_len : e->source_len;
        fwrite(&bytecode_size, 8, 1, f);
        fwrite(&source_size, 8, 1, f);
        
        // Write original sizes if compressed
        if (e->is_compressed) {
            fwrite(&e->bytecode_len, 8, 1, f);  // Original bytecode size
            fwrite(&e->source_len, 8, 1, f);   // Original source size
        }
        
        // Write data - use compressed if available
        if (e->bytecode_compressed) {
            fwrite(e->bytecode_compressed, 1, e->bytecode_compressed_len, f);
        } else {
            fwrite(e->bytecode, 1, e->bytecode_len, f);
        }
        if (e->source_compressed) {
            fwrite(e->source_compressed, 1, e->source_compressed_len, f);
        } else {
            fwrite(e->source, 1, e->source_len, f);
        }
    }
    
    // Write manifest
    manifest_offset = ftell(f);
    write_manifest(f, list, qjs_version);
    manifest_size = ftell(f) - manifest_offset;
    
    // Update manifest offset and size
    fseek(f, manifest_offset_pos, SEEK_SET);
    fwrite(&manifest_offset, 8, 1, f);
    fwrite(&manifest_size, 8, 1, f);
    
    fclose(f);
    return 0;
}

void help(void)
{
    printf("QuickJS Archive (QAR) Packager\n"
           "usage: qjar [options] <files/directories...>\n"
           "\n"
           "options:\n"
           "-o output    set the output QAR filename (default: out.qar)\n"
           "-h, --help  show this help\n"
           "\n"
           "Creates a QAR file containing compiled bytecode, source code,\n"
           "and manifest information for JavaScript files.\n");
    exit(1);
}

int main(int argc, char **argv)
{
    const char *out_filename = "out.qar";
    QarEntryList entry_list;
    JSRuntime *rt;
    JSContext *ctx;
    int i;
    
    qar_entry_list_init(&entry_list);
    
    // Parse arguments - handle options anywhere in command line
    for (i = 1; i < argc; i++) {
        if (*argv[i] == '-') {
            char *arg = argv[i] + 1;
            
            if (*arg == 'h' || !strcmp(arg, "-help")) {
                help();
            } else if (*arg == 'o') {
                i++;
                if (i >= argc) {
                    fprintf(stderr, "Missing filename for -o\n");
                    exit(1);
                }
                out_filename = argv[i];
            } else {
                help();
            }
        }
    }
    
    // Initialize QuickJS
    rt = JS_NewRuntime();
    ctx = JS_NewContext(rt);
    JS_SetModuleLoaderFunc(rt, NULL, qjar_module_loader, NULL);
    
    // Collect files (skip options)
    int has_input = 0;
    for (i = 1; i < argc; i++) {
        if (*argv[i] == '-') {
            char *arg = argv[i] + 1;
            if (*arg == 'o') {
                i++;  // Skip -o filename
                continue;
            } else if (*arg == 'h' || !strcmp(arg, "-help")) {
                continue;  // Already handled
            }
        }
        // This is an input file
        has_input = 1;
        char base_dir[1024];
        const char *input = argv[i];
        
        // Determine base directory
        struct stat st;
        if (stat(input, &st) == 0 && S_ISDIR(st.st_mode)) {
            js__pstrcpy(base_dir, sizeof(base_dir), input);
        } else {
            const char *slash = strrchr(input, '/');
            if (!slash) slash = strrchr(input, '\\');
            if (slash) {
                size_t len = slash - input;
                memcpy(base_dir, input, len);
                base_dir[len] = '\0';
            } else {
                base_dir[0] = '.';
                base_dir[1] = '\0';
            }
        }
        
        add_file_to_list(&entry_list, base_dir, input);
    }
    
    if (!has_input) {
        fprintf(stderr, "No input files specified\n");
        help();
    }
    
    if (entry_list.count == 0) {
        fprintf(stderr, "No JavaScript files found\n");
        exit(1);
    }
    
    // Compile all files
    printf("Compiling %d files...\n", entry_list.count);
    for (i = 0; i < entry_list.count; i++) {
        printf("  %s\n", entry_list.entries[i].path);
        if (compile_and_add_entry(ctx, &entry_list.entries[i]) < 0) {
            fprintf(stderr, "Failed to compile %s\n", entry_list.entries[i].filepath);
            exit(1);
        }
    }
    
    // Create QAR file
    printf("Creating QAR file: %s\n", out_filename);
    const char *qjs_version = JS_GetVersion();
    if (create_qar(out_filename, &entry_list, qjs_version) < 0) {
        fprintf(stderr, "Failed to create QAR file\n");
        exit(1);
    }
    
    printf("Done! Created %s with %d entries\n", out_filename, entry_list.count);
    
    // Cleanup
    qar_entry_list_free(&entry_list);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    
    return 0;
}

