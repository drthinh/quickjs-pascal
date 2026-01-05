/*
 * Test program for QAR loading functionality
 */

#include <stdio.h>
#include <stdlib.h>
#include "quickjs.h"
#include "quickjs-libc.h"

int main(int argc, char **argv)
{
    JSRuntime *rt;
    JSContext *ctx;
    JSValue result;
    int ret = 0;
    
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <qar_file> [module_name]\n", argv[0]);
        return 1;
    }
    
    rt = JS_NewRuntime();
    ctx = JS_NewContext(rt);
    
    js_std_init_handlers(rt);
    js_std_add_helpers(ctx, argc, argv);
    JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);
    
    // Register QAR file
    if (js_register_qar_file(ctx, argv[1], NULL) < 0) {
        fprintf(stderr, "Failed to register QAR file: %s\n", argv[1]);
        ret = 1;
        goto cleanup;
    }
    
    // Load module
    const char *module_name = (argc > 2) ? argv[2] : "test_qar";
    JSValue module_promise = JS_LoadModule(ctx, module_name, module_name);
    
    if (JS_IsException(module_promise)) {
        fprintf(stderr, "Failed to load module: %s\n", module_name);
        js_std_dump_error(ctx);
        ret = 1;
        goto cleanup;
    }
    
    // Await the promise to get the module
    JSValue module = js_std_await(ctx, module_promise);
    JS_FreeValue(ctx, module_promise);
    
    if (JS_IsException(module)) {
        fprintf(stderr, "Failed to await module: %s\n", module_name);
        js_std_dump_error(ctx);
        ret = 1;
        goto cleanup;
    }
    
    // Resolve module dependencies
    if (JS_ResolveModule(ctx, module) < 0) {
        fprintf(stderr, "Failed to resolve module dependencies\n");
        js_std_dump_error(ctx);
        ret = 1;
        JS_FreeValue(ctx, module);
        goto cleanup;
    }
    
    // Evaluate module
    result = JS_EvalFunction(ctx, module);
    JS_FreeValue(ctx, module);
    if (JS_IsException(result)) {
        fprintf(stderr, "Exception during module evaluation\n");
        js_std_dump_error(ctx);
        ret = 1;
    } else {
        JS_FreeValue(ctx, result);
    }
    
cleanup:
    js_unregister_all_qar_files(rt);
    js_std_free_handlers(rt);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    
    return ret;
}

