unit http_async_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, SyncObjs,
  quickjs_types, quickjs_core,
  Windows,
  qjs_log;

procedure RegisterHttpAsyncHelpers(ctx: PJSContext);

implementation

type
  HINTERNET = Pointer;
  INTERNET_PORT = Word;

  PURL_COMPONENTS = ^URL_COMPONENTS;
  URL_COMPONENTS = record
    dwStructSize: DWORD;
    lpszScheme: PWideChar;
    dwSchemeLength: DWORD;
    nScheme: DWORD;
    lpszHostName: PWideChar;
    dwHostNameLength: DWORD;
    nPort: INTERNET_PORT;
    lpszUserName: PWideChar;
    dwUserNameLength: DWORD;
    lpszPassword: PWideChar;
    dwPasswordLength: DWORD;
    lpszUrlPath: PWideChar;
    dwUrlPathLength: DWORD;
    lpszExtraInfo: PWideChar;
    dwExtraInfoLength: DWORD;
  end;

const
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_NO_REFERER: PWideChar = nil;
  WINHTTP_DEFAULT_ACCEPT_TYPES: Pointer = nil;
  WINHTTP_NO_PROXY_NAME: PWideChar = nil;
  WINHTTP_NO_PROXY_BYPASS: PWideChar = nil;
  WINHTTP_NO_ADDITIONAL_HEADERS: PWideChar = nil;
  WINHTTP_NO_REQUEST_DATA: Pointer = nil;

  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_RAW_HEADERS_CRLF = 22;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;

  WINHTTP_OPTION_CONNECT_TIMEOUT = 3;
  WINHTTP_OPTION_SEND_TIMEOUT = 5;
  WINHTTP_OPTION_RECEIVE_TIMEOUT = 6;
  WINHTTP_OPTION_REDIRECT_POLICY = 88;
  WINHTTP_OPTION_REDIRECT_POLICY_NEVER = 0;
  WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS = 1;

function WinHttpOpen(pwszUserAgent: PWideChar; dwAccessType: DWORD; pwszProxyName: PWideChar;
  pwszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET; stdcall; external 'winhttp.dll';
function WinHttpCloseHandle(hInternet: HINTERNET): BOOL; stdcall; external 'winhttp.dll';
function WinHttpCrackUrl(pwszUrl: PWideChar; dwUrlLength: DWORD; dwFlags: DWORD; var lpUrlComponents: URL_COMPONENTS): BOOL; stdcall; external 'winhttp.dll';
function WinHttpConnect(hSession: HINTERNET; pswzServerName: PWideChar; nServerPort: INTERNET_PORT; dwReserved: DWORD): HINTERNET; stdcall; external 'winhttp.dll';
function WinHttpOpenRequest(hConnect: HINTERNET; pwszVerb: PWideChar; pwszObjectName: PWideChar;
  pwszVersion: PWideChar; pwszReferrer: PWideChar; ppwszAcceptTypes: Pointer; dwFlags: DWORD): HINTERNET; stdcall; external 'winhttp.dll';
function WinHttpAddRequestHeaders(hRequest: HINTERNET; pwszHeaders: PWideChar; dwHeadersLength: DWORD; dwModifiers: DWORD): BOOL; stdcall; external 'winhttp.dll';
function WinHttpSendRequest(hRequest: HINTERNET; pwszHeaders: PWideChar; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength: DWORD; dwTotalLength: DWORD; dwContext: DWORD_PTR): BOOL; stdcall; external 'winhttp.dll';
function WinHttpWriteData(hRequest: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToWrite: DWORD; var lpdwNumberOfBytesWritten: DWORD): BOOL; stdcall; external 'winhttp.dll';
function WinHttpReceiveResponse(hRequest: HINTERNET; lpReserved: Pointer): BOOL; stdcall; external 'winhttp.dll';
function WinHttpQueryHeaders(hRequest: HINTERNET; dwInfoLevel: DWORD; pwszName: PWideChar; lpBuffer: Pointer; var lpdwBufferLength: DWORD; var lpdwIndex: DWORD): BOOL; stdcall; external 'winhttp.dll';
function WinHttpReadData(hRequest: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD; var lpdwNumberOfBytesRead: DWORD): BOOL; stdcall; external 'winhttp.dll';
function WinHttpQueryDataAvailable(hRequest: HINTERNET; var lpdwNumberOfBytesAvailable: DWORD): BOOL; stdcall; external 'winhttp.dll';
function WinHttpSetOption(hInternet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer; dwBufferLength: DWORD): BOOL; stdcall; external 'winhttp.dll';

function WinHttpLastErrorMessage: string;
begin
  Result := 'WinHTTP error ' + IntToStr(GetLastError);
end;

type
  THttpHeaderPair = record
    Name: string;
    Value: string;
  end;

  THttpHeaders = array of THttpHeaderPair;

function JsValueToString(ctx: PJSContext; v: JSValueConst): string;
var
  p: PChar;
begin
  p := JS_ToCString(ctx, v);
  if p = nil then
    Exit('');
  try
    Result := string(p);
  finally
    JS_FreeCString(ctx, p);
  end;
end;

function JsValueToInt(ctx: PJSContext; v: JSValueConst; defaultValue: Integer): Integer;
var
  tmp: cint32;
begin
  tmp := 0;
  if JS_IsUndefined(v) <> 0 then
    Exit(defaultValue);
  if JS_ToInt32(ctx, @tmp, v) <> 0 then
    Exit(defaultValue);
  Result := tmp;
end;

function GetHeadersFromJs(ctx: PJSContext; v: JSValueConst; out headers: THttpHeaders): Boolean;
var
  len: cint;
  len64: cint64;
  i: cint;
  pair: JSValue;
  keyVal: JSValue;
  valVal: JSValue;
  keyStr: string;
  valStr: string;
begin
  Result := False;
  SetLength(headers, 0);

  if (JS_IsUndefined(v) <> 0) or (JS_IsNull(v) <> 0) then
  begin
    Result := True;
    Exit;
  end;

  len64 := 0;
  if JS_GetLength(ctx, v, @len64) <> 0 then
    Exit;
  if (len64 < 0) or (len64 > High(cint)) then
    Exit;
  len := cint(len64);

  SetLength(headers, len);
  for i := 0 to len - 1 do
  begin
    pair := JS_GetPropertyUint32(ctx, v, cuint32(i));
    if JS_IsException(pair) <> 0 then
      Exit;

    keyVal := JS_GetPropertyUint32(ctx, pair, 0);
    valVal := JS_GetPropertyUint32(ctx, pair, 1);

    keyStr := JsValueToString(ctx, keyVal);
    valStr := JsValueToString(ctx, valVal);

    JS_FreeValue(ctx, keyVal);
    JS_FreeValue(ctx, valVal);
    JS_FreeValue(ctx, pair);

    headers[i].Name := keyStr;
    headers[i].Value := valStr;
  end;

  Result := True;
end;

function SplitRawHeadersToStrings(const raw: UnicodeString; out list: TStringList): Boolean;
var
  startIdx: Integer;
  p: Integer;
  line: UnicodeString;
begin
  list := TStringList.Create;
  list.Clear;

  startIdx := 1;
  while startIdx <= Length(raw) do
  begin
    p := Pos(#13#10, raw, startIdx);
    if p = 0 then
      p := Length(raw) + 1;

    line := Copy(raw, startIdx, p - startIdx);
    if line <> '' then
      list.Add(string(line));

    startIdx := p + 2;
  end;

  Result := True;
end;

procedure AddResponseHeadersToObject(ctx: PJSContext; targetObj: JSValue; headers: TStrings);
var
  i: Integer;
  line: string;
  p: Integer;
  k, v: string;
  hdrObj: JSValue;
  keyAtom: PChar;
begin
  hdrObj := JS_NewObject(ctx);

  for i := 0 to headers.Count - 1 do
  begin
    line := headers[i];
    p := Pos(':', line);
    if p <= 0 then
      Continue;

    k := Trim(Copy(line, 1, p - 1));
    v := Trim(Copy(line, p + 1, Length(line)));

    keyAtom := PChar(k);
    JS_DefinePropertyValueStr(ctx, hdrObj, keyAtom, JS_NewString(ctx, PChar(v)), JS_PROP_C_W_E);
  end;

  JS_DefinePropertyValueStr(ctx, targetObj, PChar('headers'), hdrObj, JS_PROP_C_W_E);
end;

type
  THttpResult = record
    Ok: Boolean;
    ErrorMsg: string;
    Status: Integer;
    Headers: TStringList;
    Body: RawByteString;
    BodyText: string;
  end;

function DoHttpRequest(const method, url: string; const headers: THttpHeaders; const body: RawByteString;
  timeoutMs: Integer; allowRedirects: Boolean; responseType: string; maxBytes: Integer): THttpResult;
var
  session: HINTERNET;
  connect: HINTERNET;
  request: HINTERNET;
  uc: URL_COMPONENTS;
  hostName: UnicodeString;
  urlPath: UnicodeString;
  scheme: UnicodeString;
  fullUrlW: UnicodeString;
  verbW: UnicodeString;
  hdrLineW: UnicodeString;
  port: INTERNET_PORT;
  flags: DWORD;
  bufLen: DWORD;
  idx: DWORD;
  statusCode: DWORD;
  rawHeadersW: UnicodeString;
  rawHeadersBuf: PWideChar;
  avail: DWORD;
  bytesRead: DWORD;
  bytesWritten: DWORD;
  ms: TMemoryStream;
  tmpBuf: array[0..8191] of Byte;
  hdrList: TStringList;
  i: Integer;
  s: RawByteString;
  asText: Boolean;
  chunkSize: DWORD;
begin
  qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): ' + UpperCase(method) + ' ' + url +
    ' timeoutMs=' + IntToStr(timeoutMs) +
    ' maxBytes=' + IntToStr(maxBytes) +
    ' followRedirects=' + BoolToStr(allowRedirects, True) +
    ' responseType=' + LowerCase(responseType));

  Result.Ok := False;
  Result.ErrorMsg := '';
  Result.Status := 0;
  Result.Headers := nil;
  Result.Body := '';
  Result.BodyText := '';

  session := nil;
  connect := nil;
  request := nil;
  rawHeadersBuf := nil;
  hdrList := nil;
  ms := TMemoryStream.Create;
  try
    fullUrlW := UTF8Decode(url);
    FillChar(uc, SizeOf(uc), 0);
    uc.dwStructSize := SizeOf(uc);
    uc.lpszHostName := nil;
    uc.dwHostNameLength := DWORD(-1);
    uc.lpszUrlPath := nil;
    uc.dwUrlPathLength := DWORD(-1);
    uc.lpszScheme := nil;
    uc.dwSchemeLength := DWORD(-1);

    if not WinHttpCrackUrl(PWideChar(fullUrlW), Length(fullUrlW), 0, uc) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpCrackUrl failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := 'Invalid URL: ' + url;
      Exit;
    end;

    SetString(hostName, uc.lpszHostName, uc.dwHostNameLength);
    SetString(urlPath, uc.lpszUrlPath, uc.dwUrlPathLength);
    SetString(scheme, uc.lpszScheme, uc.dwSchemeLength);
    port := uc.nPort;

    qjs_log.DebugMsg(1, 'HttpRequestAsync(worker): scheme=' + string(scheme) + ' host=' + string(hostName) +
      ' port=' + IntToStr(port) + ' path=' + string(urlPath));

    flags := 0;
    if (LowerCase(string(scheme)) = 'https') then
      flags := flags or WINHTTP_FLAG_SECURE;

    session := WinHttpOpen(PWideChar(UnicodeString('qjsp/1.0')),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if session = nil then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpOpen failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;

    if timeoutMs > 0 then
    begin
      WinHttpSetOption(session, WINHTTP_OPTION_CONNECT_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(session, WINHTTP_OPTION_SEND_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(session, WINHTTP_OPTION_RECEIVE_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
    end;

    if allowRedirects then
      i := WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS
    else
      i := WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    WinHttpSetOption(session, WINHTTP_OPTION_REDIRECT_POLICY, @i, SizeOf(i));

    connect := WinHttpConnect(session, PWideChar(hostName), port, 0);
    if connect = nil then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpConnect failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;

    verbW := UTF8Decode(UpperCase(method));
    request := WinHttpOpenRequest(connect, PWideChar(verbW), PWideChar(urlPath), nil, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if request = nil then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpOpenRequest failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;

    if timeoutMs > 0 then
    begin
      WinHttpSetOption(request, WINHTTP_OPTION_CONNECT_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(request, WINHTTP_OPTION_SEND_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
    end;

    for i := 0 to High(headers) do
    begin
      if headers[i].Name <> '' then
      begin
        hdrLineW := UTF8Decode(headers[i].Name + ': ' + headers[i].Value + #13#10);
        WinHttpAddRequestHeaders(request, PWideChar(hdrLineW), DWORD(-1), 0);
      end;
    end;

    s := body;

    if not WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
      WINHTTP_NO_REQUEST_DATA, 0, DWORD(Length(s)), 0) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpSendRequest failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;

    if Length(s) > 0 then
    begin
      bytesWritten := 0;
      if not WinHttpWriteData(request, Pointer(s), DWORD(Length(s)), bytesWritten) then
      begin
        qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpWriteData failed: ' + WinHttpLastErrorMessage);
        Result.ErrorMsg := WinHttpLastErrorMessage;
        Exit;
      end;
    end;

    if not WinHttpReceiveResponse(request, nil) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpReceiveResponse failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;

    statusCode := 0;
    bufLen := SizeOf(statusCode);
    idx := 0;
    if not WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER, nil,
      @statusCode, bufLen, idx) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpQueryHeaders(status) failed: ' + WinHttpLastErrorMessage);
      Result.ErrorMsg := WinHttpLastErrorMessage;
      Exit;
    end;
    Result.Status := Integer(statusCode);

    qjs_log.DebugMsg(1, 'HttpRequestAsync(worker): status=' + IntToStr(Result.Status));

    bufLen := 0;
    idx := 0;
    WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, nil, nil, bufLen, idx);
    if bufLen > 0 then
    begin
      GetMem(rawHeadersBuf, bufLen);
      try
        idx := 0;
        if WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, nil, rawHeadersBuf, bufLen, idx) then
        begin
          rawHeadersW := UnicodeString(rawHeadersBuf);
          SplitRawHeadersToStrings(rawHeadersW, hdrList);
        end;
      finally
        FreeMem(rawHeadersBuf);
        rawHeadersBuf := nil;
      end;
    end;
    if hdrList = nil then
      hdrList := TStringList.Create;

    while True do
    begin
      avail := 0;
      if not WinHttpQueryDataAvailable(request, avail) then
      begin
        qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpQueryDataAvailable failed: ' + WinHttpLastErrorMessage);
        Result.ErrorMsg := WinHttpLastErrorMessage;
        Exit;
      end;
      if avail = 0 then
        Break;

      while avail > 0 do
      begin
        if avail > DWORD(Length(tmpBuf)) then
          chunkSize := DWORD(Length(tmpBuf))
        else
          chunkSize := avail;

        if (maxBytes > 0) and (ms.Size >= maxBytes) then
        begin
          avail := 0;
          Break;
        end;

        if (maxBytes > 0) and ((maxBytes - ms.Size) < chunkSize) then
          chunkSize := DWORD(maxBytes - ms.Size);

        bytesRead := chunkSize;

        if not WinHttpReadData(request, @tmpBuf[0], bytesRead, bytesRead) then
        begin
          qjs_log.DebugMsg(0, 'HttpRequestAsync(worker): WinHttpReadData failed: ' + WinHttpLastErrorMessage);
          Result.ErrorMsg := WinHttpLastErrorMessage;
          Exit;
        end;
        if bytesRead = 0 then
          Break;
        ms.WriteBuffer(tmpBuf[0], bytesRead);
        Dec(avail, bytesRead);
      end;

      if (maxBytes > 0) and (ms.Size >= maxBytes) then
        Break;
    end;

    if maxBytes > 0 then
      qjs_log.DebugMsg(1, 'HttpRequestAsync(worker): bodyBytes=' + IntToStr(ms.Size) + ' (stopped at maxBytes)')
    else
      qjs_log.DebugMsg(1, 'HttpRequestAsync(worker): bodyBytes=' + IntToStr(ms.Size));

    if ms.Size > 0 then
    begin
      SetLength(Result.Body, ms.Size);
      ms.Position := 0;
      ms.ReadBuffer(Pointer(Result.Body)^, ms.Size);
    end
    else
    begin
      Result.Body := '';
    end;

    Result.Headers := hdrList;
    hdrList := nil;

    asText := LowerCase(responseType) = 'text';
    if asText then
    begin
      Result.BodyText := string(AnsiString(Result.Body));
    end;

    Result.Ok := True;
  finally
    if hdrList <> nil then
      hdrList.Free;
    ms.Free;
    if request <> nil then
      WinHttpCloseHandle(request);
    if connect <> nil then
      WinHttpCloseHandle(connect);
    if session <> nil then
      WinHttpCloseHandle(session);
  end;
end;

type
  PAsyncTask = ^TAsyncTask;
  TAsyncTask = record
    Id: cint;
    Ctx: PJSContext;
    ResolveFunc: JSValue;
    RejectFunc: JSValue;
    Method: string;
    Url: string;
    Headers: THttpHeaders;
    Body: RawByteString;
    TimeoutMs: Integer;
    MaxBytes: Integer;
    FollowRedirects: Boolean;
    ResponseType: string;
  end;

  PAsyncResult = ^TAsyncResult;
  TAsyncResult = record
    TaskId: cint;
    Ctx: PJSContext;
    ResolveFunc: JSValue;
    RejectFunc: JSValue;
    Ok: Boolean;
    ErrorMsg: string;
    Status: Integer;
    Headers: TStringList;
    Body: RawByteString;
    BodyText: string;
  end;

var
  NextTaskId: cint = 1;
  TaskQueue: array of PAsyncTask;
  ResultQueue: array of PAsyncResult;
  QueueCS: TRTLCriticalSection;
  HasWorkEvent: TEvent;
  QueueInit: Boolean = False;
  PoolStarted: Boolean = False;
  PoolSize: Integer = 4;
  PoolThreads: array of TThread;

procedure TaskQueuePush(t: PAsyncTask);
begin
  EnterCriticalSection(QueueCS);
  try
    SetLength(TaskQueue, Length(TaskQueue) + 1);
    TaskQueue[High(TaskQueue)] := t;
  finally
    LeaveCriticalSection(QueueCS);
  end;
  if HasWorkEvent <> nil then
    HasWorkEvent.SetEvent;
end;

function TaskQueuePop: PAsyncTask;
var
  i: Integer;
  t: PAsyncTask;
  outArr: array of PAsyncTask;
begin
  Result := nil;
  EnterCriticalSection(QueueCS);
  try
    if Length(TaskQueue) = 0 then
      Exit;
    t := TaskQueue[0];
    if Length(TaskQueue) = 1 then
    begin
      SetLength(TaskQueue, 0);
    end
    else
    begin
      SetLength(outArr, Length(TaskQueue) - 1);
      for i := 1 to High(TaskQueue) do
        outArr[i - 1] := TaskQueue[i];
      TaskQueue := outArr;
    end;
    Result := t;
  finally
    LeaveCriticalSection(QueueCS);
  end;
end;

procedure ResultQueuePush(r: PAsyncResult);
begin
  EnterCriticalSection(QueueCS);
  try
    SetLength(ResultQueue, Length(ResultQueue) + 1);
    ResultQueue[High(ResultQueue)] := r;
  finally
    LeaveCriticalSection(QueueCS);
  end;
end;

function ResultQueueDrain: TList;
var
  i: Integer;
  lst: TList;
begin
  lst := TList.Create;
  EnterCriticalSection(QueueCS);
  try
    for i := 0 to High(ResultQueue) do
      lst.Add(ResultQueue[i]);
    SetLength(ResultQueue, 0);
  finally
    LeaveCriticalSection(QueueCS);
  end;
  Result := lst;
end;

type
  THttpWorkerThread = class(TThread)
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

constructor THttpWorkerThread.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;
end;

procedure THttpWorkerThread.Execute;
var
  t: PAsyncTask;
  res: THttpResult;
  r: PAsyncResult;
  i: Integer;
  errMsg: string;
begin
  while not Terminated do
  begin
    t := TaskQueuePop;
    if t = nil then
    begin
      if HasWorkEvent <> nil then
        HasWorkEvent.WaitFor(100)
      else
        Sleep(100);
      Continue;
    end;

    errMsg := '';
    qjs_log.DebugMsg(1, 'HttpRequestAsync(worker): start taskId=' + IntToStr(t^.Id));
    try
      res := DoHttpRequest(t^.Method, t^.Url, t^.Headers, t^.Body, t^.TimeoutMs, t^.FollowRedirects, t^.ResponseType, t^.MaxBytes);
    except
      on E: Exception do
      begin
        res.Ok := False;
        res.ErrorMsg := 'net:http_async_helpers:Worker: ' + E.Message;
        res.Status := 0;
        res.Headers := nil;
        res.Body := '';
        res.BodyText := '';
      end;
    end;

    New(r);
    FillChar(r^, SizeOf(TAsyncResult), 0);
    r^.TaskId := t^.Id;
    r^.Ctx := t^.Ctx;
    r^.ResolveFunc := t^.ResolveFunc;
    r^.RejectFunc := t^.RejectFunc;
    r^.Ok := res.Ok;
    r^.ErrorMsg := res.ErrorMsg;
    r^.Status := res.Status;
    r^.Headers := res.Headers;
    r^.Body := res.Body;
    r^.BodyText := res.BodyText;

    for i := 0 to High(t^.Headers) do
    begin
    end;

    Finalize(t^);
    Dispose(t);

    ResultQueuePush(r);
  end;
end;

procedure EnsurePoolStarted;
var
  i: Integer;
begin
  if not QueueInit then
  begin
    InitCriticalSection(QueueCS);
    HasWorkEvent := TEvent.Create(nil, False, False, '');
    QueueInit := True;
  end;

  if PoolStarted then
    Exit;
  PoolStarted := True;
  if PoolSize < 1 then
    PoolSize := 1;
  SetLength(PoolThreads, PoolSize);
  for i := 0 to PoolSize - 1 do
    PoolThreads[i] := THttpWorkerThread.Create;
end;

function js_http_request_async(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  method: string;
  url: string;
  headers: THttpHeaders;
  bodyVal: JSValueConst;
  abSize: csize_t;
  abPtr: Pcuint8;
  bodyStr: string;
  bodyRaw: RawByteString;
  okHeaders: Boolean;
  timeoutMs: Integer;
  allowRedirects: Boolean;
  responseType: string;
  optObj: JSValue;
  optVal: JSValue;
  followVal: JSValue;
  respTypeVal: JSValue;
  maxBytes: Integer;
  maxVal: JSValue;
  resolving_funcs: array[0..1] of JSValue;
  promise: JSValue;
  headerListVal: JSValueConst;
  t: PAsyncTask;
  optFromArg3: Boolean;
  arg3Obj: JSValue;
  hdrValTmp: JSValue;
  bodyValTmp: JSValue;
begin
  try
    if argc < 2 then
      Exit(JS_ThrowTypeError(ctx, PChar('HttpRequestAsync(method, url, headers?, body?, options?)')));

    EnsurePoolStarted;

  method := JsValueToString(ctx, argv[0]);
  url := JsValueToString(ctx, argv[1]);

  optFromArg3 := False;
  arg3Obj := JS_UNDEFINED;
  hdrValTmp := JS_UNDEFINED;
  bodyValTmp := JS_UNDEFINED;

  headerListVal := JS_UNDEFINED;
  bodyVal := JS_UNDEFINED;
  if argc >= 3 then
  begin
    // Support wrapper style: HttpRequestAsync(method, url, { headers, body, ...options })
    if (JS_IsObject(argv[2]) <> 0) then
    begin
      hdrValTmp := JS_GetPropertyStr(ctx, argv[2], PChar('headers'));
      if JS_IsUndefined(hdrValTmp) = 0 then
      begin
        arg3Obj := JS_DupValue(ctx, argv[2]);
        optFromArg3 := True;

        headerListVal := hdrValTmp;

        bodyValTmp := JS_GetPropertyStr(ctx, arg3Obj, PChar('body'));
        bodyVal := bodyValTmp;
      end
      else
      begin
        JS_FreeValue(ctx, hdrValTmp);
        headerListVal := argv[2];
      end;
    end
    else
      headerListVal := argv[2];
  end;

  okHeaders := GetHeadersFromJs(ctx, headerListVal, headers);
  if optFromArg3 then
    JS_FreeValue(ctx, hdrValTmp);
  if not okHeaders then
  begin
    if optFromArg3 then
    begin
      JS_FreeValue(ctx, bodyValTmp);
      JS_FreeValue(ctx, arg3Obj);
    end;
    Exit(JS_ThrowTypeError(ctx, PChar('headers must be an array of [name, value] pairs')));
  end;

  if not optFromArg3 then
  begin
    if argc >= 4 then
      bodyVal := argv[3];
  end;

  timeoutMs := 0;
  maxBytes := 0;
  allowRedirects := True;
  responseType := 'arraybuffer';

  if optFromArg3 then
    optObj := arg3Obj
  else if argc >= 5 then
    optObj := JS_DupValue(ctx, argv[4])
  else
    optObj := JS_UNDEFINED;

  if (JS_IsUndefined(optObj) = 0) and (JS_IsNull(optObj) = 0) then
  begin
    optVal := JS_GetPropertyStr(ctx, optObj, PChar('timeoutMs'));
    timeoutMs := JsValueToInt(ctx, optVal, 0);
    JS_FreeValue(ctx, optVal);

    followVal := JS_GetPropertyStr(ctx, optObj, PChar('followRedirects'));
    if JS_IsUndefined(followVal) = 0 then
      allowRedirects := (JS_ToBool(ctx, followVal) <> 0);
    JS_FreeValue(ctx, followVal);

    respTypeVal := JS_GetPropertyStr(ctx, optObj, PChar('responseType'));
    if JS_IsUndefined(respTypeVal) = 0 then
      responseType := LowerCase(JsValueToString(ctx, respTypeVal));
    JS_FreeValue(ctx, respTypeVal);

    maxVal := JS_GetPropertyStr(ctx, optObj, PChar('maxBytes'));
    maxBytes := JsValueToInt(ctx, maxVal, 0);
    JS_FreeValue(ctx, maxVal);
  end;
  if (optFromArg3 = False) and (argc >= 5) then
    JS_FreeValue(ctx, optObj);

  bodyRaw := '';
  if (JS_IsUndefined(bodyVal) = 0) and (JS_IsNull(bodyVal) = 0) then
  begin
    if JS_IsString(bodyVal) <> 0 then
    begin
      bodyStr := JsValueToString(ctx, bodyVal);
      if bodyStr <> '' then
        bodyRaw := RawByteString(bodyStr);
    end
    else
    begin
      abSize := 0;
      abPtr := nil;
      if JS_IsArrayBuffer(bodyVal) <> 0 then
        abPtr := JS_GetArrayBuffer(ctx, @abSize, bodyVal)
      else
        abPtr := JS_GetUint8Array(ctx, @abSize, bodyVal);

      if abPtr = nil then
        Exit(JS_ThrowTypeError(ctx, PChar('body must be string, ArrayBuffer, or Uint8Array')));

      if abSize > 0 then
      begin
        SetLength(bodyRaw, abSize);
        Move(abPtr^, Pointer(bodyRaw)^, abSize);
      end;
    end;
  end;

  promise := JS_NewPromiseCapability(ctx, @resolving_funcs[0]);
  if JS_IsException(promise) <> 0 then
    Exit(JS_EXCEPTION);

  New(t);
  FillChar(t^, SizeOf(TAsyncTask), 0);
  t^.Id := NextTaskId;
  Inc(NextTaskId);
  t^.Ctx := ctx;
  t^.ResolveFunc := JS_DupValue(ctx, resolving_funcs[0]);
  t^.RejectFunc := JS_DupValue(ctx, resolving_funcs[1]);
  t^.Method := method;
  t^.Url := url;
  t^.Headers := headers;
  t^.Body := bodyRaw;
  t^.TimeoutMs := timeoutMs;
  t^.MaxBytes := maxBytes;
  t^.FollowRedirects := allowRedirects;
  t^.ResponseType := responseType;

  if optFromArg3 then
  begin
    JS_FreeValue(ctx, bodyValTmp);
    JS_FreeValue(ctx, arg3Obj);
  end;

  TaskQueuePush(t);

  JS_FreeValue(ctx, resolving_funcs[0]);
  JS_FreeValue(ctx, resolving_funcs[1]);

    Result := promise;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('net:http_async_helpers:HttpRequestAsync: ' + E.Message));
  end;
end;

function js_pump_http_requests(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lst: TList;
  i: Integer;
  r: PAsyncResult;
  obj: JSValue;
  bodyBytes: JSValue;
  bodyText: JSValue;
  args: array[0..0] of JSValue;
  errVal: JSValue;
  globalObj: JSValue;
  errCtor: JSValue;
  errArgs: array[0..0] of JSValue;
begin
  try
    lst := ResultQueueDrain;
    try
      for i := 0 to lst.Count - 1 do
      begin
        r := PAsyncResult(lst[i]);
        if r = nil then
          Continue;

      if r^.Ok then
      begin
        obj := JS_NewObject(ctx);
        JS_DefinePropertyValueStr(ctx, obj, PChar('status'), JS_NewInt32(ctx, r^.Status), JS_PROP_C_W_E);
        if r^.Headers <> nil then
          AddResponseHeadersToObject(ctx, obj, r^.Headers)
        else
          JS_DefinePropertyValueStr(ctx, obj, PChar('headers'), JS_NewObject(ctx), JS_PROP_C_W_E);

        if Length(r^.Body) > 0 then
          bodyBytes := JS_NewArrayBufferCopy(ctx, Pcuint8(Pointer(r^.Body)), csize_t(Length(r^.Body)))
        else
          bodyBytes := JS_NewArrayBufferCopy(ctx, nil, 0);
        JS_DefinePropertyValueStr(ctx, obj, PChar('body'), bodyBytes, JS_PROP_C_W_E);

        if r^.BodyText <> '' then
        begin
          bodyText := JS_NewStringLen(ctx, PChar(AnsiString(r^.Body)), csize_t(Length(r^.Body)));
          JS_DefinePropertyValueStr(ctx, obj, PChar('bodyText'), bodyText, JS_PROP_C_W_E);
        end;

        args[0] := obj;
        JS_Call(ctx, r^.ResolveFunc, JS_UNDEFINED, 1, @args[0]);
        JS_FreeValue(ctx, obj);
      end
      else
      begin
        // Construct Error(message) without relying on JS_NewError (not always exposed in bindings)
        globalObj := JS_GetGlobalObject(ctx);
        errCtor := JS_GetPropertyStr(ctx, globalObj, PChar('Error'));
        JS_FreeValue(ctx, globalObj);

        errArgs[0] := JS_NewString(ctx, PChar(r^.ErrorMsg));
        errVal := JS_CallConstructor(ctx, errCtor, 1, @errArgs[0]);
        JS_FreeValue(ctx, errArgs[0]);
        JS_FreeValue(ctx, errCtor);

        if JS_IsException(errVal) <> 0 then
        begin
          // Fallback: reject with string
          errVal := JS_NewString(ctx, PChar(r^.ErrorMsg));
        end;

        args[0] := errVal;
        JS_Call(ctx, r^.RejectFunc, JS_UNDEFINED, 1, @args[0]);
        JS_FreeValue(ctx, errVal);
      end;

      JS_FreeValue(ctx, r^.ResolveFunc);
      JS_FreeValue(ctx, r^.RejectFunc);
      if r^.Headers <> nil then
        r^.Headers.Free;

      r^.Headers := nil;
      Finalize(r^);
      Dispose(r);
    end;
  finally
      lst.Free;
    end;

    Result := JS_UNDEFINED;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('net:http_async_helpers:PumpHttpRequests: ' + E.Message));
  end;
end;

procedure RegisterHttpAsyncHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  if not QueueInit then
  begin
    InitCriticalSection(QueueCS);
    HasWorkEvent := TEvent.Create(nil, False, False, '');
    QueueInit := True;
  end;

  global_obj := JS_GetGlobalObject(ctx);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('HttpRequestAsync'),
    JS_NewCFunction(ctx, @js_http_request_async, PChar('HttpRequestAsync'), 5), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('PumpHttpRequests'),
    JS_NewCFunction(ctx, @js_pump_http_requests, PChar('PumpHttpRequests'), 0), JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);
end;

end.
