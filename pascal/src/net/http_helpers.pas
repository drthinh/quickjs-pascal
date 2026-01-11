unit http_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes,
  quickjs_types, quickjs_core,
  Windows,
  qjs_log;

function js_http_request(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
procedure RegisterHttpHelpers(ctx: PJSContext);

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

function WideToUtf8Raw(const ws: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(ws);
end;

function WinHttpLastErrorMessage: string;
begin
  Result := 'WinHTTP error ' + IntToStr(GetLastError);
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

type
  THttpHeaders = array of record
    Name: string;
    Value: string;
  end;

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

function js_http_request(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  method: string;
  url: string;
  headers: THttpHeaders;
  obj: JSValue;
  timeoutMs: Integer;
  maxBytes: Integer;
  allowRedirects: Boolean;
  optObj: JSValue;
  optVal: JSValue;
  i: Integer;
  bodyVal: JSValueConst;
  bodyStr: string;
  abSize: csize_t;
  abPtr: Pcuint8;
  bodyBytes: JSValue;
  bodyText: JSValue;
  status: Integer;
  s: RawByteString;
  responseType: string;
  asText: Boolean;
  okHeaders: Boolean;
  headerListVal: JSValueConst;
  followVal: JSValue;
  respTypeVal: JSValue;
  optFromArg3: Boolean;
  arg3Obj: JSValue;
  hdrValTmp: JSValue;
  bodyValTmp: JSValue;
  bodyNeedsFree: Boolean;
  maxVal: JSValue;
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
  chunkSize: DWORD;
  totalRead: Int64;
begin
  try
    Result := JS_EXCEPTION;

    if argc < 2 then
    begin
      JS_ThrowTypeError(ctx, PChar('HttpRequest(method, url, headers?, body?, options?)'));
      Exit;
    end;

  method := JsValueToString(ctx, argv[0]);
  url := JsValueToString(ctx, argv[1]);

  optFromArg3 := False;
  bodyNeedsFree := False;
  arg3Obj := JS_UNDEFINED;
  hdrValTmp := JS_UNDEFINED;
  bodyValTmp := JS_UNDEFINED;

  headerListVal := JS_UNDEFINED;
  if argc >= 3 then
  begin
    // Support wrapper style: HttpRequest(method, url, { headers, body, ...options })
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
        bodyNeedsFree := True;
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
      if bodyNeedsFree then
        JS_FreeValue(ctx, bodyValTmp);
      JS_FreeValue(ctx, arg3Obj);
    end;
    JS_ThrowTypeError(ctx, PChar('headers must be an array of [name, value] pairs'));
    Exit;
  end;

  if not optFromArg3 then
  begin
    bodyVal := JS_UNDEFINED;
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

  qjs_log.DebugMsg(0, 'HttpRequest: argc=' + IntToStr(argc) + ' optFromArg3=' + BoolToStr(optFromArg3, True) +
    ' optIsObject=' + BoolToStr(JS_IsObject(optObj) <> 0, True) +
    ' optIsArray=' + BoolToStr(JS_IsArray(ctx, optObj) <> 0, True));

  if (JS_IsObject(optObj) <> 0) then
  begin
    optVal := JS_GetPropertyStr(ctx, optObj, PChar('timeoutMs'));
    qjs_log.DebugMsg(0, 'HttpRequest: opt.has(timeoutMs)=' + BoolToStr(JS_IsUndefined(optVal) = 0, True));
    JS_FreeValue(ctx, optVal);

    optVal := JS_GetPropertyStr(ctx, optObj, PChar('maxBytes'));
    qjs_log.DebugMsg(0, 'HttpRequest: opt.has(maxBytes)=' + BoolToStr(JS_IsUndefined(optVal) = 0, True));
    JS_FreeValue(ctx, optVal);

    optVal := JS_GetPropertyStr(ctx, optObj, PChar('responseType'));
    qjs_log.DebugMsg(0, 'HttpRequest: opt.has(responseType)=' + BoolToStr(JS_IsUndefined(optVal) = 0, True));
    JS_FreeValue(ctx, optVal);

    optVal := JS_GetPropertyStr(ctx, optObj, PChar('followRedirects'));
    qjs_log.DebugMsg(0, 'HttpRequest: opt.has(followRedirects)=' + BoolToStr(JS_IsUndefined(optVal) = 0, True));
    JS_FreeValue(ctx, optVal);
  end;

  if (JS_IsUndefined(optObj) = 0) and (JS_IsNull(optObj) = 0) then
  begin
    optVal := JS_GetPropertyStr(ctx, optObj, PChar('timeoutMs'));
    if JS_IsUndefined(optVal) <> 0 then
      qjs_log.DebugMsg(0, 'HttpRequest: options.timeoutMs is undefined');
    timeoutMs := JsValueToInt(ctx, optVal, 0);
    JS_FreeValue(ctx, optVal);

    followVal := JS_GetPropertyStr(ctx, optObj, PChar('followRedirects'));
    if JS_IsUndefined(followVal) = 0 then
      allowRedirects := (JS_ToBool(ctx, followVal) <> 0);
    JS_FreeValue(ctx, followVal);

    respTypeVal := JS_GetPropertyStr(ctx, optObj, PChar('responseType'));
    if JS_IsUndefined(respTypeVal) <> 0 then
      qjs_log.DebugMsg(0, 'HttpRequest: options.responseType is undefined');
    if JS_IsUndefined(respTypeVal) = 0 then
      responseType := LowerCase(JsValueToString(ctx, respTypeVal));
    JS_FreeValue(ctx, respTypeVal);

    maxVal := JS_GetPropertyStr(ctx, optObj, PChar('maxBytes'));
    if JS_IsUndefined(maxVal) <> 0 then
      qjs_log.DebugMsg(0, 'HttpRequest: options.maxBytes is undefined');
    maxBytes := JsValueToInt(ctx, maxVal, 0);
    JS_FreeValue(ctx, maxVal);
  end;
  if (optFromArg3 = False) and (argc >= 5) then
    JS_FreeValue(ctx, optObj);

  asText := responseType = 'text';

  qjs_log.DebugMsg(0, 'HttpRequest: ' + UpperCase(method) + ' ' + url +
    ' timeoutMs=' + IntToStr(timeoutMs) +
    ' maxBytes=' + IntToStr(maxBytes) +
    ' followRedirects=' + BoolToStr(allowRedirects, True) +
    ' responseType=' + responseType);

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
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpCrackUrl failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar('Invalid URL: ' + url));
      Exit;
    end;

    SetString(hostName, uc.lpszHostName, uc.dwHostNameLength);
    SetString(urlPath, uc.lpszUrlPath, uc.dwUrlPathLength);
    SetString(scheme, uc.lpszScheme, uc.dwSchemeLength);
    port := uc.nPort;

    qjs_log.DebugMsg(1, 'HttpRequest: scheme=' + string(scheme) + ' host=' + string(hostName) +
      ' port=' + IntToStr(port) + ' path=' + string(urlPath));

    flags := 0;
    if (LowerCase(string(scheme)) = 'https') then
      flags := flags or WINHTTP_FLAG_SECURE;

    session := WinHttpOpen(PWideChar(UnicodeString('qjsp/1.0')),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if session = nil then
    begin
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpOpen failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
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
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpConnect failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
      Exit;
    end;

    verbW := UTF8Decode(UpperCase(method));
    request := WinHttpOpenRequest(connect, PWideChar(verbW), PWideChar(urlPath), nil, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if request = nil then
    begin
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpOpenRequest failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
      Exit;
    end;

    if timeoutMs > 0 then
    begin
      WinHttpSetOption(request, WINHTTP_OPTION_CONNECT_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(request, WINHTTP_OPTION_SEND_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
      WinHttpSetOption(request, WINHTTP_OPTION_RECEIVE_TIMEOUT, @timeoutMs, SizeOf(timeoutMs));
    end;

    // Add custom headers
    for i := 0 to High(headers) do
    begin
      if headers[i].Name <> '' then
      begin
        hdrLineW := UTF8Decode(headers[i].Name + ': ' + headers[i].Value + #13#10);
        WinHttpAddRequestHeaders(request, PWideChar(hdrLineW), DWORD(-1), 0);
      end;
    end;

    // Determine request body
    s := '';
    if (JS_IsUndefined(bodyVal) = 0) and (JS_IsNull(bodyVal) = 0) then
    begin
      if JS_IsString(bodyVal) <> 0 then
      begin
        bodyStr := JsValueToString(ctx, bodyVal);
        if bodyStr <> '' then
          s := RawByteString(bodyStr);
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
        begin
          JS_ThrowTypeError(ctx, PChar('body must be string, ArrayBuffer, or Uint8Array'));
          Exit;
        end;

        if abSize > 0 then
        begin
          SetLength(s, abSize);
          Move(abPtr^, Pointer(s)^, abSize);
        end;
      end;
    end;

    if not WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
      WINHTTP_NO_REQUEST_DATA, 0, DWORD(Length(s)), 0) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpSendRequest failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
      Exit;
    end;

    if Length(s) > 0 then
    begin
      bytesWritten := 0;
      if not WinHttpWriteData(request, Pointer(s), DWORD(Length(s)), bytesWritten) then
      begin
        qjs_log.DebugMsg(0, 'HttpRequest: WinHttpWriteData failed: ' + WinHttpLastErrorMessage);
        JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
        Exit;
      end;
    end;

    if not WinHttpReceiveResponse(request, nil) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpReceiveResponse failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
      Exit;
    end;

    // Status code
    statusCode := 0;
    bufLen := SizeOf(statusCode);
    idx := 0;
    if not WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER, nil,
      @statusCode, bufLen, idx) then
    begin
      qjs_log.DebugMsg(0, 'HttpRequest: WinHttpQueryHeaders(status) failed: ' + WinHttpLastErrorMessage);
      JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
      Exit;
    end;
    status := Integer(statusCode);

    qjs_log.DebugMsg(1, 'HttpRequest: status=' + IntToStr(status));

    // Raw headers
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

    // Read response body
    totalRead := 0;
    while True do
    begin
      avail := 0;
      if not WinHttpQueryDataAvailable(request, avail) then
      begin
        qjs_log.DebugMsg(0, 'HttpRequest: WinHttpQueryDataAvailable failed: ' + WinHttpLastErrorMessage);
        JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
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
          qjs_log.DebugMsg(0, 'HttpRequest: WinHttpReadData failed: ' + WinHttpLastErrorMessage);
          JS_ThrowTypeError(ctx, PChar(WinHttpLastErrorMessage));
          Exit;
        end;
        if bytesRead = 0 then
          Break;
        ms.WriteBuffer(tmpBuf, bytesRead);
        totalRead := totalRead + bytesRead;
        Dec(avail, bytesRead);
      end;

      if (maxBytes > 0) and (ms.Size >= maxBytes) then
        Break;
    end;

    if maxBytes > 0 then
      qjs_log.DebugMsg(1, 'HttpRequest: bodyBytes=' + IntToStr(ms.Size) + ' (stopped at maxBytes)')
    else
      qjs_log.DebugMsg(1, 'HttpRequest: bodyBytes=' + IntToStr(ms.Size));

    // Build JS response
    obj := JS_NewObject(ctx);
    JS_DefinePropertyValueStr(ctx, obj, PChar('status'), JS_NewInt32(ctx, status), JS_PROP_C_W_E);
    AddResponseHeadersToObject(ctx, obj, hdrList);

    if ms.Size > 0 then
    begin
      SetLength(s, ms.Size);
      ms.Position := 0;
      ms.ReadBuffer(Pointer(s)^, ms.Size);

      bodyBytes := JS_NewArrayBufferCopy(ctx, Pcuint8(Pointer(s)), csize_t(Length(s)));
      JS_DefinePropertyValueStr(ctx, obj, PChar('body'), bodyBytes, JS_PROP_C_W_E);

      if asText then
      begin
        bodyText := JS_NewStringLen(ctx, PChar(AnsiString(s)), csize_t(Length(s)));
        JS_DefinePropertyValueStr(ctx, obj, PChar('bodyText'), bodyText, JS_PROP_C_W_E);
      end;
    end
    else
    begin
      JS_DefinePropertyValueStr(ctx, obj, PChar('body'), JS_NewArrayBufferCopy(ctx, nil, 0), JS_PROP_C_W_E);
      if asText then
        JS_DefinePropertyValueStr(ctx, obj, PChar('bodyText'), JS_NewString(ctx, PChar('')), JS_PROP_C_W_E);
    end;

    Result := obj;
  finally
    ms.Free;

    if request <> nil then
      WinHttpCloseHandle(request);
    if connect <> nil then
      WinHttpCloseHandle(connect);
    if session <> nil then
      WinHttpCloseHandle(session);

    if hdrList <> nil then
      hdrList.Free;

    if optFromArg3 then
    begin
      if bodyNeedsFree then
        JS_FreeValue(ctx, bodyValTmp);
      JS_FreeValue(ctx, arg3Obj);
    end;
  end;
  except
    on E: Exception do
    begin
      Result := JS_ThrowPlainError(ctx, PChar('net:http_helpers:HttpRequest: ' + E.Message));
    end;
  end;
end;

procedure RegisterHttpHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('HttpRequest'),
    JS_NewCFunction(ctx, @js_http_request, PChar('HttpRequest'), 5), JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);
end;

end.
