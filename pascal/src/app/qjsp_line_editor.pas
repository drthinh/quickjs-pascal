unit qjsp_line_editor;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

procedure RunUnicodeLineEditor(const FilePath: string);

implementation

uses
  Classes, console_utf8;

type
  TLineEditorState = class
  public
    Lines: TStringList;
    InsertAt: integer;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TLineEditorState.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
  InsertAt := 0;
end;

destructor TLineEditorState.Destroy;
begin
  if Lines <> nil then
    Lines.Free;
  inherited Destroy;
end;

function CloneLines(const src: TStringList): TStringList;
var
  i: integer;
begin
  Result := TStringList.Create;
  for i := 0 to src.Count - 1 do
    Result.Add(src[i]);
end;

function CaptureState(const srcLines: TStringList; const srcInsertAt: integer): TLineEditorState;
begin
  Result := TLineEditorState.Create;
  Result.Lines.Free;
  Result.Lines := CloneLines(srcLines);
  Result.InsertAt := srcInsertAt;
end;

procedure RestoreState(dstLines: TStringList; var dstInsertAt: integer; const st: TLineEditorState);
begin
  dstLines.Assign(st.Lines);
  dstInsertAt := st.InsertAt;
end;

procedure ClearStateStack(const stack: TList);
var
  i: integer;
begin
  for i := 0 to stack.Count - 1 do
    TObject(stack[i]).Free;
  stack.Clear;
end;

function CountOccurrences(const haystack, needle: string): integer;
var
  p: SizeInt;
  startAt: SizeInt;
begin
  Result := 0;
  if needle = '' then
    Exit;
  startAt := 1;
  while True do
  begin
    p := Pos(needle, Copy(haystack, startAt, Length(haystack)));
    if p <= 0 then
      Break;
    Inc(Result);
    startAt := startAt + p + Length(needle) - 1;
    if startAt > Length(haystack) then
      Break;
  end;
end;

function ReadUtf8FileText(const FileName: string): UTF8String;
var
  fs: TFileStream;
  buf: TBytes;
begin
  Result := '';
  if (FileName = '') or (not FileExists(FileName)) then
    Exit;
  fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if fs.Size <= 0 then
      Exit;
    SetLength(buf, fs.Size);
    fs.ReadBuffer(buf[0], Length(buf));
    SetString(Result, PAnsiChar(@buf[0]), Length(buf));
  finally
    fs.Free;
  end;
end;

procedure WriteUtf8FileText(const FileName: string; const Text: UTF8String);
var
  fs: TFileStream;
begin
  if FileName = '' then
    Exit;
  fs := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Text) > 0 then
      fs.WriteBuffer(Text[1], Length(Text));
  finally
    fs.Free;
  end;
end;

function SplitLinesUtf8(const s: UTF8String): TStringList;
var
  tmp: UTF8String;
  i: SizeInt;
  line: UTF8String;
begin
  Result := TStringList.Create;
  Result.LineBreak := LineEnding;
  tmp := s;
  tmp := StringReplace(tmp, #13#10, #10, [rfReplaceAll]);
  tmp := StringReplace(tmp, #13, #10, [rfReplaceAll]);
  line := '';
  for i := 1 to Length(tmp) do
  begin
    if tmp[i] = #10 then
    begin
      Result.Add(string(line));
      line := '';
    end
    else
      line := line + tmp[i];
  end;
  if line <> '' then
    Result.Add(string(line))
  else if (Length(tmp) > 0) and (tmp[Length(tmp)] = #10) then
    Result.Add('');
  if Result.Count = 0 then
    Result.Add('');
end;

function BuildTextFromLines(const lines: TStringList): UTF8String;
var
  i: integer;
  s: UTF8String;
begin
  Result := '';
  for i := 0 to lines.Count - 1 do
  begin
    s := UTF8String(lines[i]);
    Result := Result + s;
    if i < lines.Count - 1 then
      Result := Result + #10;
  end;
  Result := Result + #10;
end;

procedure PrintBuffer(const lines: TStringList);
var
  i: integer;
begin
  for i := 0 to lines.Count - 1 do
    WriteLn(Format('%6d  %s', [i + 1, lines[i]]));
end;

procedure RunUnicodeLineEditor(const FilePath: string);
var
  p: string;
  lines: TStringList;
  insertAt: integer;
  replaceMode: boolean;
  replaceIdx: integer;
  input: string;
  cmd: string;
  verb: string;
  argsLine: string;
  arg: string;
  n: integer;
  idx: integer;
  text: UTF8String;
  existed: boolean;
  p1: SizeInt;
  a1: string;
  a2: string;
  cmdArgs: TStringList;
  undoStack: TList;
  redoStack: TList;
  i: integer;
  startLine: integer;
  replCount: integer;

  procedure PushUndoSnapshot;
  begin
    undoStack.Add(CaptureState(lines, insertAt));
    ClearStateStack(redoStack);
  end;

  procedure DoUndo;
  var
    st: TLineEditorState;
  begin
    if undoStack.Count <= 0 then
    begin
      WriteLn('Error: nothing to undo');
      Exit;
    end;
    redoStack.Add(CaptureState(lines, insertAt));
    st := TLineEditorState(undoStack[undoStack.Count - 1]);
    undoStack.Delete(undoStack.Count - 1);
    RestoreState(lines, insertAt, st);
    st.Free;
    replaceMode := False;
    replaceIdx := -1;
  end;

  procedure DoRedo;
  var
    st: TLineEditorState;
  begin
    if redoStack.Count <= 0 then
    begin
      WriteLn('Error: nothing to redo');
      Exit;
    end;
    undoStack.Add(CaptureState(lines, insertAt));
    st := TLineEditorState(redoStack[redoStack.Count - 1]);
    redoStack.Delete(redoStack.Count - 1);
    RestoreState(lines, insertAt, st);
    st.Free;
    replaceMode := False;
    replaceIdx := -1;
  end;
begin
  p := ExpandFileName(FilePath);
  lines := nil;
  insertAt := 0;
  replaceMode := False;
  replaceIdx := -1;
  undoStack := nil;
  redoStack := nil;

  try
    existed := FileExists(p);
    try
      text := ReadUtf8FileText(p);
      lines := SplitLinesUtf8(text);
    except
      lines := TStringList.Create;
      lines.Add('');
    end;

    undoStack := TList.Create;
    redoStack := TList.Create;

    insertAt := lines.Count;
    WriteLn('-- edit ', p, ' --');
    WriteLn('Commands: :w (write), :q (quit), :wq (write+quit), :u (undo), :redo (redo), :p [N [M]] (print; full or range), :l N (show line), :f [N] TEXT (find substring), :d N [M] (delete line/range), :i N (insert before line), :a N [text] (append after line / append to end-of-line), :r N [text] (replace line), :s N FROM TO (replace substring), :sa FROM TO (replace all)');
    WriteLn('Enter text lines. Empty line is allowed.');
    WriteLn;

    if existed then
    begin
      PrintBuffer(lines);
      WriteLn;
    end;

    while True do
    begin
      input := ReadLnUtf8;
      cmd := Trim(input);

      if replaceMode and (cmd <> '') and (cmd[1] = ':') then
      begin
        // User typed a command while we were waiting for replacement text.
        // Cancel replaceMode so it won't unexpectedly apply later.
        replaceMode := False;
        replaceIdx := -1;
        // fall through to command processing
      end
      else if replaceMode and ((cmd = '') or (cmd[1] <> ':')) then
      begin
        if (replaceIdx >= 0) and (replaceIdx < lines.Count) then
        begin
          PushUndoSnapshot;
          lines[replaceIdx] := input;
          insertAt := replaceIdx + 1;
        end;
        replaceMode := False;
        replaceIdx := -1;
        Continue;
      end;

      if (cmd <> '') and (cmd[1] = ':') then
      begin
        cmd := Trim(Copy(cmd, 2, Length(cmd)));
        p1 := Pos(' ', cmd);
        if p1 > 0 then
        begin
          verb := LowerCase(Copy(cmd, 1, p1 - 1));
          argsLine := Trim(Copy(cmd, p1 + 1, Length(cmd)));
        end
        else
        begin
          verb := LowerCase(cmd);
          argsLine := '';
        end;

        if verb = 'q' then
          Exit;

        if verb = 'u' then
        begin
          DoUndo;
          Continue;
        end;

        if verb = 'f' then
        begin
          arg := argsLine;
          if arg = '' then
          begin
            WriteLn('Error: usage :f [N] TEXT');
            Continue;
          end;

          startLine := 1;
          p1 := Pos(' ', arg);
          if (p1 > 0) and TryStrToInt(Copy(arg, 1, p1 - 1), n) then
          begin
            startLine := n;
            a1 := Trim(Copy(arg, p1 + 1, Length(arg)));
          end
          else
          begin
            a1 := arg;
          end;

          if a1 = '' then
          begin
            WriteLn('Error: usage :f [N] TEXT');
            Continue;
          end;

          if startLine < 1 then
            startLine := 1;
          if startLine > lines.Count then
          begin
            WriteLn('Error: invalid line number');
            Continue;
          end;

          i := startLine - 1;
          while i < lines.Count do
          begin
            if Pos(a1, lines[i]) > 0 then
              WriteLn(Format('%6d  %s', [i + 1, lines[i]]));
            Inc(i);
          end;
          Continue;
        end;

        if verb = 'redo' then
        begin
          DoRedo;
          Continue;
        end;

        if verb = 'p' then
        begin
          if argsLine = '' then
          begin
            PrintBuffer(lines);
            Continue;
          end;

          cmdArgs := TStringList.Create;
          try
            cmdArgs.Delimiter := ' ';
            cmdArgs.StrictDelimiter := True;
            cmdArgs.DelimitedText := argsLine;
            if (cmdArgs.Count >= 1) and TryStrToInt(cmdArgs[0], n) then
            begin
              idx := n - 1;
              if (idx < 0) or (idx >= lines.Count) then
              begin
                WriteLn('Error: invalid line number');
                Continue;
              end;

              if (cmdArgs.Count >= 2) and TryStrToInt(cmdArgs[1], n) then
              begin
                n := n - 1;
                if n < idx then
                begin
                  WriteLn('Error: invalid range');
                  Continue;
                end;
                if n >= lines.Count then
                  n := lines.Count - 1;
                while idx <= n do
                begin
                  WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
                  Inc(idx);
                end;
              end
              else
              begin
                WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
              end;
              Continue;
            end;
            WriteLn('Error: invalid print args');
          finally
            cmdArgs.Free;
          end;
          Continue;
        end;

        if verb = 'w' then
        begin
          WriteUtf8FileText(p, BuildTextFromLines(lines));
          WriteLn('(written)');
          Continue;
        end;

        if verb = 'wq' then
        begin
          WriteUtf8FileText(p, BuildTextFromLines(lines));
          WriteLn('(written)');
          Exit;
        end;

        if verb = 'l' then
        begin
          arg := argsLine;
          if TryStrToInt(arg, n) then
          begin
            idx := n - 1;
            if (idx >= 0) and (idx < lines.Count) then
            begin
              WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
              Continue;
            end;
          end;
          WriteLn('Error: invalid line number');
          Continue;
        end;

        if verb = 'd' then
        begin
          arg := argsLine;
          cmdArgs := TStringList.Create;
          try
            cmdArgs.Delimiter := ' ';
            cmdArgs.StrictDelimiter := True;
            cmdArgs.DelimitedText := arg;

            if (cmdArgs.Count >= 1) and TryStrToInt(cmdArgs[0], n) then
            begin
              idx := n - 1;
              if (idx < 0) or (idx >= lines.Count) then
              begin
                WriteLn('Error: invalid line number');
                Continue;
              end;

              if (cmdArgs.Count >= 2) and TryStrToInt(cmdArgs[1], n) then
              begin
                n := n - 1;
                if n < idx then
                begin
                  WriteLn('Error: invalid range');
                  Continue;
                end;
                if n >= lines.Count then
                  n := lines.Count - 1;

                PushUndoSnapshot;
                while n >= idx do
                begin
                  lines.Delete(n);
                  Dec(n);
                end;
              end
              else
              begin
                PushUndoSnapshot;
                lines.Delete(idx);
              end;

              if lines.Count = 0 then
                lines.Add('');
              if insertAt > lines.Count then
                insertAt := lines.Count;
              Continue;
            end;
          finally
            cmdArgs.Free;
          end;
          WriteLn('Error: invalid line number');
          Continue;
        end;

        if verb = 'i' then
        begin
          arg := argsLine;
          if TryStrToInt(arg, n) then
          begin
            idx := n - 1;
            if (idx >= 0) and (idx <= lines.Count) then
            begin
              PushUndoSnapshot;
              insertAt := idx;
              Continue;
            end;
          end;
          WriteLn('Error: invalid line number');
          Continue;
        end;

        if verb = 'a' then
        begin
          arg := argsLine;
          if arg <> '' then
          begin
            p1 := Pos(' ', arg);
            if p1 > 0 then
            begin
              if TryStrToInt(Copy(arg, 1, p1 - 1), n) then
              begin
                idx := n - 1;
                if (idx >= 0) and (idx < lines.Count) then
                begin
                  PushUndoSnapshot;
                  lines[idx] := lines[idx] + Copy(arg, p1 + 1, Length(arg));
                  WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
                  insertAt := idx + 1;
                  Continue;
                end;
              end;
            end
            else
            begin
              if TryStrToInt(arg, n) then
              begin
                idx := n - 1;
                if (idx >= -1) and (idx < lines.Count) then
                begin
                  PushUndoSnapshot;
                  insertAt := idx + 1;
                  Continue;
                end;
              end;
            end;
          end;
          WriteLn('Error: invalid line number');
          Continue;
        end;

        if verb = 'r' then
        begin
          arg := argsLine;
          n := 0;
          idx := -1;
          if arg <> '' then
          begin
            p1 := Pos(' ', arg);
            if p1 > 0 then
            begin
              if TryStrToInt(Copy(arg, 1, p1 - 1), n) then
                idx := n - 1;
            end
            else
            begin
              if TryStrToInt(arg, n) then
                idx := n - 1;
            end;
          end;

          if (idx < 0) or (idx >= lines.Count) then
          begin
            WriteLn('Error: invalid line number');
            Continue;
          end;

          if (arg <> '') and (Pos(' ', arg) > 0) then
          begin
            p1 := Pos(' ', arg);
            PushUndoSnapshot;
            lines[idx] := Copy(arg, p1 + 1, Length(arg));
            WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
            insertAt := idx + 1;
            Continue;
          end;

          replaceMode := True;
          replaceIdx := idx;
          WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
          Continue;
        end;

        if verb = 's' then
        begin
          arg := argsLine;
          p1 := Pos(' ', arg);
          if p1 <= 0 then
          begin
            WriteLn('Error: usage :s N FROM TO');
            Continue;
          end;
          if not TryStrToInt(Copy(arg, 1, p1 - 1), n) then
          begin
            WriteLn('Error: invalid line number');
            Continue;
          end;
          idx := n - 1;
          if (idx < 0) or (idx >= lines.Count) then
          begin
            WriteLn('Error: invalid line number');
            Continue;
          end;
          arg := Trim(Copy(arg, p1 + 1, Length(arg)));
          p1 := Pos(' ', arg);
          if p1 <= 0 then
          begin
            WriteLn('Error: usage :s N FROM TO');
            Continue;
          end;
          a1 := Copy(arg, 1, p1 - 1);
          a2 := Trim(Copy(arg, p1 + 1, Length(arg)));
          if a1 = '' then
          begin
            WriteLn('Error: FROM must be non-empty');
            Continue;
          end;
          if Pos(a1, lines[idx]) <= 0 then
          begin
            WriteLn('Error: FROM not found');
            Continue;
          end;
          PushUndoSnapshot;
          lines[idx] := StringReplace(lines[idx], a1, a2, []);
          WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
          Continue;
        end;

        if verb = 'sa' then
        begin
          arg := argsLine;
          p1 := Pos(' ', arg);
          if p1 <= 0 then
          begin
            WriteLn('Error: usage :sa FROM TO');
            Continue;
          end;
          a1 := Copy(arg, 1, p1 - 1);
          a2 := Trim(Copy(arg, p1 + 1, Length(arg)));
          if a1 = '' then
          begin
            WriteLn('Error: FROM must be non-empty');
            Continue;
          end;

          replCount := 0;
          for i := 0 to lines.Count - 1 do
            Inc(replCount, CountOccurrences(lines[i], a1));
          if replCount <= 0 then
          begin
            WriteLn('Error: FROM not found');
            Continue;
          end;

          PushUndoSnapshot;
          for i := 0 to lines.Count - 1 do
            lines[i] := StringReplace(lines[i], a1, a2, [rfReplaceAll]);
          WriteLn(Format('(replaced %d)', [replCount]));
          Continue;
        end;

        WriteLn('Error: unknown command');
        Continue;
      end;

      PushUndoSnapshot;
      lines.Insert(insertAt, input);
      Inc(insertAt);
    end;
  finally
    if undoStack <> nil then
    begin
      ClearStateStack(undoStack);
      undoStack.Free;
    end;
    if redoStack <> nil then
    begin
      ClearStateStack(redoStack);
      redoStack.Free;
    end;
    if lines <> nil then
      lines.Free;
  end;
end;

end.
