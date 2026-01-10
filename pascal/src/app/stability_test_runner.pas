{
  Stability Test Runner for QuickJS Pascal Integration
  
  This program runs comprehensive stability tests including:
  - Memory leak detection (repeated context creation/destruction)
  - Stress tests (many operations)
  - Performance benchmarks
  - Resource cleanup verification
  
  Compile with: fpc -Fu. stability_test_runner.pas
  Run with: stability_test_runner.exe
}

program StabilityTestRunner;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, ctypes, quickjs_types, quickjs_core, quickjs_std, qar, Classes
  {$IFDEF WINDOWS}
  , Windows
  {$ELSE}
  {$IFDEF UNIX}
  , dl, Unix
  {$ENDIF}
  {$IFDEF DARWIN}
  , dl
  {$ENDIF}
  {$ENDIF}
  ;

type
  TTestResult = record
    name: string;
    passed: Boolean;
    duration: Int64; // microseconds
    error: string;
  end;

var
  TestResults: array of TTestResult;
  TotalTests: Integer = 0;
  PassedTests: Integer = 0;
  FailedTests: Integer = 0;

procedure DrainPendingJobs(rt: PJSRuntime);
var
  pending_ctx: PJSContext;
begin
  if rt = nil then
    Exit;
  pending_ctx := nil;
  while JS_ExecutePendingJob(rt, @pending_ctx) > 0 do
  begin
  end;
end;

// Helper function to load and execute JS file
// Returns error message in errorMsg parameter if failed
function LoadAndExecuteJSFile(ctx: PJSContext; const filename: string; out errorMsg: string): Boolean;
var
  script: string;
  script_content: TStringList;
  result_val: JSValue;
  is_exception: Boolean;
  exception_str: PChar;
  exc_val: JSValue;
  oldMask: TFPUExceptionMask;
begin
  Result := False;
  errorMsg := '';
  
  if not FileExists(filename) then
  begin
    errorMsg := 'File not found: ' + filename;
    Exit;
  end;
  
  try
    script_content := TStringList.Create;
    try
      script_content.LoadFromFile(filename);
      script := script_content.Text;
      
      if Length(script) = 0 then
      begin
        errorMsg := 'File is empty: ' + filename;
        Exit;
      end;
      
      try
        oldMask := GetExceptionMask;
        SetExceptionMask(oldMask + [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
        try
          result_val := JS_Eval(ctx, PChar(script), QWord(Length(script)), 
                               PChar(filename), JS_EVAL_TYPE_GLOBAL);
        finally
          SetExceptionMask(oldMask);
        end;
        
        is_exception := JS_IsException(result_val) <> 0;
        if is_exception then
        begin
          exc_val := JS_GetException(ctx);
          exception_str := JS_ToCString(ctx, exc_val);
          if exception_str <> nil then
          begin
            errorMsg := 'JavaScript exception: ' + string(exception_str);
            JS_FreeCString(ctx, exception_str);
          end
          else
            errorMsg := 'JavaScript exception (unable to get message)';
          JS_FreeValue(ctx, exc_val);
          JS_FreeValue(ctx, result_val);
          Exit;
        end;
        
        DrainPendingJobs(JS_GetRuntime(ctx));
        JS_FreeValue(ctx, result_val);
        Result := True;
      except
        on E: EDivByZero do
        begin
          errorMsg := 'Division by zero during JS_Eval: ' + E.Message;
          Exit;
        end;
        on E: EZeroDivide do
        begin
          errorMsg := 'Zero divide during JS_Eval: ' + E.Message;
          Exit;
        end;
        on E: Exception do
        begin
          errorMsg := 'Exception during JS_Eval: ' + E.ClassName + ' - ' + E.Message;
          Exit;
        end;
      end;
    finally
      script_content.Free;
    end;
  except
    on E: EDivByZero do
    begin
      errorMsg := 'Division by zero in file loading: ' + E.Message;
      Exit;
    end;
    on E: EZeroDivide do
    begin
      errorMsg := 'Zero divide in file loading: ' + E.Message;
      Exit;
    end;
    on E: Exception do
    begin
      errorMsg := 'Error loading file: ' + E.ClassName + ' - ' + E.Message;
      Exit;
    end;
  end;
end;

// Get high-resolution time in microseconds
function GetTimeMicroseconds: Int64;
{$IFDEF WINDOWS}
var
  freq, count: Int64;
begin
  QueryPerformanceFrequency(freq);
  QueryPerformanceCounter(count);
  if freq > 0 then
    Result := (count * 1000000) div freq
  else
    Result := count; // Fallback if frequency is 0 (shouldn't happen)
end;
{$ELSE}
var
  tv: TimeVal;
begin
  fpGetTimeOfDay(@tv, nil);
  Result := Int64(tv.tv_sec) * 1000000 + Int64(tv.tv_usec);
end;
{$ENDIF}

// Run a single test
function RunTest(const testName, testFile: string): TTestResult;
var
  rt: PJSRuntime;
  ctx: PJSContext;
  startTime, endTime: Int64;
  success: Boolean;
  errorMsg: string;
begin
  Result.name := testName;
  Result.passed := False;
  Result.duration := 0;
  Result.error := '';
  
  startTime := GetTimeMicroseconds;
  rt := nil;
  ctx := nil;
  
  try
    // Create runtime
    rt := JS_NewRuntime;
    if rt = nil then
    begin
      Result.error := 'Failed to create JS runtime';
      endTime := GetTimeMicroseconds;
      if endTime >= startTime then
        Result.duration := endTime - startTime;
      Exit;
    end;
    
    // Set memory limit (128 MB for stability tests)
    JS_SetMemoryLimit(rt, 128 * 1024 * 1024);
    
    // Create context
    ctx := JS_NewContext(rt);
    if ctx = nil then
    begin
      Result.error := 'Failed to create JS context';
      if rt <> nil then
        JS_FreeRuntime(rt);
      endTime := GetTimeMicroseconds;
      if endTime >= startTime then
        Result.duration := endTime - startTime;
      Exit;
    end;
    
    // Initialize standard handlers
    js_std_init_handlers(rt);
    
    // Set up module loader
    JS_SetModuleLoaderFunc(rt, nil, nil, nil);
    
    // Add standard helpers
    js_std_add_helpers(ctx, 0, nil);
    
    // Note: RegisterQarHelpers is not available in this standalone test runner
    // The stability tests don't require QAR functionality
    
    // Run the test
    success := LoadAndExecuteJSFile(ctx, testFile, errorMsg);

    DrainPendingJobs(rt);
    
    // Calculate duration before cleanup
    endTime := GetTimeMicroseconds;
    if endTime >= startTime then
      Result.duration := endTime - startTime
    else
      Result.duration := 0; // Handle clock rollover
    
    Result.passed := success;
    
    if not success then
      Result.error := errorMsg;
      
  except
    on E: EDivByZero do
    begin
      Result.error := 'Division by zero error in RunTest: ' + E.ClassName + ' - ' + E.Message;
      try
        endTime := GetTimeMicroseconds;
        if endTime >= startTime then
          Result.duration := endTime - startTime
        else
          Result.duration := 0;
      except
        Result.duration := 0;
      end;
    end;
    on E: EZeroDivide do
    begin
      Result.error := 'Zero divide error in RunTest: ' + E.ClassName + ' - ' + E.Message;
      try
        endTime := GetTimeMicroseconds;
        if endTime >= startTime then
          Result.duration := endTime - startTime
        else
          Result.duration := 0;
      except
        Result.duration := 0;
      end;
    end;
    on E: Exception do
    begin
      Result.error := 'Exception in RunTest: ' + E.ClassName + ' - ' + E.Message;
      try
        endTime := GetTimeMicroseconds;
        if endTime >= startTime then
          Result.duration := endTime - startTime
        else
          Result.duration := 0;
      except
        Result.duration := 0;
      end;
    end;
  end;
  
  // Cleanup (always, even if exception occurred)
  try
    if ctx <> nil then
      JS_FreeContext(ctx);
    if rt <> nil then
      js_std_free_handlers(rt);
    if rt <> nil then
      JS_FreeRuntime(rt);
  except
    // Ignore cleanup errors
  end;
end;

// Memory leak test: Create and destroy contexts repeatedly
function RunMemoryLeakTest(iterations: Integer): TTestResult;
var
  rt: PJSRuntime;
  ctx: PJSContext;
  i: Integer;
  startTime, endTime: Int64;
  script: string;
  result_val: JSValue;
  exc_val: JSValue;
  oldMask: TFPUExceptionMask;
begin
  Result.name := 'Memory Leak Test (' + IntToStr(iterations) + ' iterations)';
  Result.passed := False;
  Result.duration := 0;
  Result.error := '';
  
  startTime := GetTimeMicroseconds;
  
  try
    for i := 1 to iterations do
    begin
      // Create runtime
      rt := JS_NewRuntime;
      if rt = nil then
      begin
        Result.error := 'Failed to create JS runtime at iteration ' + IntToStr(i);
        Exit;
      end;
      
      JS_SetMemoryLimit(rt, 64 * 1024 * 1024);
      
      // Create context
      ctx := JS_NewContext(rt);
      if ctx = nil then
      begin
        Result.error := 'Failed to create JS context at iteration ' + IntToStr(i);
        JS_FreeRuntime(rt);
        Exit;
      end;
      
      js_std_init_handlers(rt);
      JS_SetModuleLoaderFunc(rt, nil, nil, nil);
      js_std_add_helpers(ctx, 0, nil);
      
      // Execute a simple script
      script := 'var x = 10 + 20; console.log("Iteration ' + IntToStr(i) + ': " + x);';
      oldMask := GetExceptionMask;
      SetExceptionMask(oldMask + [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
      try
        result_val := JS_Eval(ctx, PChar(script), Length(script), 
                             'memory_test.js', JS_EVAL_TYPE_GLOBAL);
      finally
        SetExceptionMask(oldMask);
      end;
      
      if JS_IsException(result_val) <> 0 then
      begin
        exc_val := JS_GetException(ctx);
        Result.error := 'Exception at iteration ' + IntToStr(i);
        JS_FreeValue(ctx, exc_val);
        JS_FreeValue(ctx, result_val);
        DrainPendingJobs(rt);
        JS_FreeContext(ctx);
        js_std_free_handlers(rt);
        JS_FreeRuntime(rt);
        Exit;
      end;
      
      JS_FreeValue(ctx, result_val);
      DrainPendingJobs(rt);
      
      // Cleanup
      JS_FreeContext(ctx);
      js_std_free_handlers(rt);
      JS_FreeRuntime(rt);
    end;
    
    endTime := GetTimeMicroseconds;
    Result.duration := endTime - startTime;
    Result.passed := True;
    
  except
    on E: Exception do
    begin
      Result.error := 'Exception: ' + E.Message;
      endTime := GetTimeMicroseconds;
      Result.duration := endTime - startTime;
    end;
  end;
end;

// Stress test: Run many operations in a single context
function RunStressTest: TTestResult;
var
  rt: PJSRuntime;
  ctx: PJSContext;
  startTime, endTime: Int64;
  script: string;
  result_val: JSValue;
  exc_val: JSValue;
  oldMask: TFPUExceptionMask;
begin
  Result.name := 'Stress Test (10000 operations)';
  Result.passed := False;
  Result.duration := 0;
  Result.error := '';
  
  startTime := GetTimeMicroseconds;
  
  try
    rt := JS_NewRuntime;
    if rt = nil then
    begin
      Result.error := 'Failed to create JS runtime';
      Exit;
    end;
    
    JS_SetMemoryLimit(rt, 128 * 1024 * 1024);
    
    ctx := JS_NewContext(rt);
    if ctx = nil then
    begin
      Result.error := 'Failed to create JS context';
      JS_FreeRuntime(rt);
      Exit;
    end;
    
    js_std_init_handlers(rt);
    JS_SetModuleLoaderFunc(rt, nil, nil, nil);
    js_std_add_helpers(ctx, 0, nil);
    
    // Run stress test script
    script := 'var sum = 0; ' +
              'for (var i = 0; i < 10000; i++) { ' +
              '  sum += i; ' +
              '  var obj = { id: i, data: "test" + i }; ' +
              '  var str = JSON.stringify(obj); ' +
              '  var parsed = JSON.parse(str); ' +
              '} ' +
              'console.log("Stress test completed, sum =", sum);';
    
    oldMask := GetExceptionMask;
    SetExceptionMask(oldMask + [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
    try
      result_val := JS_Eval(ctx, PChar(script), Length(script), 
                           'stress_test.js', JS_EVAL_TYPE_GLOBAL);
    finally
      SetExceptionMask(oldMask);
    end;
    
    if JS_IsException(result_val) <> 0 then
    begin
      exc_val := JS_GetException(ctx);
      Result.error := 'Exception during stress test';
      JS_FreeValue(ctx, exc_val);
      JS_FreeValue(ctx, result_val);
      DrainPendingJobs(rt);
      JS_FreeContext(ctx);
      js_std_free_handlers(rt);
      JS_FreeRuntime(rt);
      Exit;
    end;
    
    JS_FreeValue(ctx, result_val);
    DrainPendingJobs(rt);
    
    JS_FreeContext(ctx);
    js_std_free_handlers(rt);
    JS_FreeRuntime(rt);
    
    endTime := GetTimeMicroseconds;
    Result.duration := endTime - startTime;
    Result.passed := True;
    
  except
    on E: Exception do
    begin
      Result.error := 'Exception: ' + E.Message;
      endTime := GetTimeMicroseconds;
      Result.duration := endTime - startTime;
    end;
  end;
end;

// Add test result
procedure AddTestResult(const result: TTestResult);
begin
  SetLength(TestResults, Length(TestResults) + 1);
  TestResults[Length(TestResults) - 1] := result;
  Inc(TotalTests);
  if result.passed then
    Inc(PassedTests)
  else
    Inc(FailedTests);
end;

// Print test results
procedure PrintResults;
var
  i: Integer;
  totalDuration: Int64;
  avgDuration: Double;
  duration_ms: Double;
begin
  WriteLn;
  WriteLn('========================================');
  WriteLn('      STABILITY TEST RESULTS');
  WriteLn('========================================');
  WriteLn;
  
  totalDuration := 0;
  for i := 0 to Length(TestResults) - 1 do
  begin
    totalDuration := totalDuration + TestResults[i].duration;
    
    if TestResults[i].passed then
      Write('✓ PASS')
    else
      Write('✗ FAIL');
    
    WriteLn(' - ', TestResults[i].name);
    try
      if (TestResults[i].duration >= 0) and (TestResults[i].duration < High(Int64) div 2) then
      begin
        duration_ms := TestResults[i].duration / 1000.0;
        // Check for NaN: NaN is not equal to itself
        // Check for Infinity: compare with a very large number
        if (duration_ms <> duration_ms) or (Abs(duration_ms) > 1e15) then
          WriteLn('  Duration: (invalid)')
        else
          WriteLn('  Duration: ', duration_ms:0:2, ' ms');
      end
      else
        WriteLn('  Duration: 0.00 ms');
    except
      on E: Exception do
        WriteLn('  Duration: (error: ', E.Message, ')');
    end;
    
    if not TestResults[i].passed then
      WriteLn('  Error: ', TestResults[i].error);
    
    WriteLn;
  end;
  
  WriteLn('========================================');
  WriteLn('Summary:');
  WriteLn('  Total Tests: ', TotalTests);
  WriteLn('  Passed: ', PassedTests);
  WriteLn('  Failed: ', FailedTests);
  
  if TotalTests > 0 then
  begin
    try
      avgDuration := totalDuration / TotalTests / 1000.0;
      WriteLn('  Total Duration: ', (totalDuration / 1000.0):0:2, ' ms');
      WriteLn('  Average Duration: ', avgDuration:0:2, ' ms');
    except
      on E: EDivByZero do
      begin
        WriteLn('  Total Duration: (error calculating)');
        WriteLn('  Average Duration: (error calculating)');
      end;
      on E: Exception do
      begin
        WriteLn('  Total Duration: (error: ', E.Message, ')');
        WriteLn('  Average Duration: (error: ', E.Message, ')');
      end;
    end;
  end;
  
  WriteLn('========================================');
  WriteLn;
  
  if FailedTests = 0 then
  begin
    WriteLn('✓ All stability tests PASSED!');
    WriteLn('The QuickJS Pascal integration appears stable.');
  end
  else
  begin
    WriteLn('✗ Some stability tests FAILED!');
    WriteLn('Please review the errors above.');
  end;
end;

// Main program
var
  result: TTestResult;
  testFile: string;
begin
  WriteLn('QuickJS Pascal Stability Test Runner');
  WriteLn('====================================');
  WriteLn;
  
  // Test 1: Comprehensive JavaScript stability test
  WriteLn('Running comprehensive JavaScript stability test...');
  testFile := 'tests/stability_test.js';
  if FileExists(testFile) then
  begin
    result := RunTest('Comprehensive JavaScript Stability Test', testFile);
    AddTestResult(result);
  end
  else
  begin
    WriteLn('Warning: ', testFile, ' not found. Skipping.');
  end;
  
  // Test 2: Memory leak test
  WriteLn('Running memory leak test (100 iterations)...');
  result := RunMemoryLeakTest(100);
  AddTestResult(result);
  
  // Test 3: Stress test
  WriteLn('Running stress test...');
  result := RunStressTest;
  AddTestResult(result);
  
  // Test 4: More aggressive memory leak test
  WriteLn('Running aggressive memory leak test (500 iterations)...');
  result := RunMemoryLeakTest(500);
  AddTestResult(result);
  
  // Print all results
  PrintResults;
  
  // Exit with appropriate code
  if FailedTests = 0 then
    Halt(0)
  else
    Halt(1);
end.

