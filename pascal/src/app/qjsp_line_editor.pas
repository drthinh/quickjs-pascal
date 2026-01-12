unit qjsp_line_editor;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

procedure RunUnicodeLineEditor(const FilePath: string);

implementation

uses
  Classes, console_utf8;

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
      Result.Add(UTF8ToString(line));
      line := '';
    end
    else
      line := line + tmp[i];
  end;
  if line <> '' then
    Result.Add(UTF8ToString(line))
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
    s := UTF8Encode(lines[i]);
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
  dirty: boolean;
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
begin
  p := ExpandFileName(FilePath);
  lines := nil;
  dirty := False;
  insertAt := 0;
  replaceMode := False;
  replaceIdx := -1;

  try
    existed := FileExists(p);
    try
      text := ReadUtf8FileText(p);
      lines := SplitLinesUtf8(text);
    except
      lines := TStringList.Create;
      lines.Add('');
    end;

    insertAt := lines.Count;
    WriteLn('-- edit ', p, ' --');
    WriteLn('Commands: :w (write), :q (quit), :wq (write+quit), :p [N [M]] (print; full or range), :l N (show line), :d N (delete line), :i N (insert before line), :a N (append after line), :r N [text] (replace line), :s N FROM TO (replace substring)');
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
          lines[replaceIdx] := input;
          dirty := True;
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
          dirty := False;
          WriteLn('(written)');
          Continue;
        end;

        if verb = 'wq' then
        begin
          WriteUtf8FileText(p, BuildTextFromLines(lines));
          dirty := False;
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
          if TryStrToInt(arg, n) then
          begin
            idx := n - 1;
            if (idx >= 0) and (idx < lines.Count) then
            begin
              lines.Delete(idx);
              if lines.Count = 0 then
                lines.Add('');
              if insertAt > lines.Count then
                insertAt := lines.Count;
              dirty := True;
              Continue;
            end;
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
          if TryStrToInt(arg, n) then
          begin
            idx := n - 1;
            if (idx >= -1) and (idx < lines.Count) then
            begin
              insertAt := idx + 1;
              Continue;
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
            if Pos(' ', arg) > 0 then
            begin
              if TryStrToInt(Copy(arg, 1, Pos(' ', arg) - 1), n) then
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

          if (Pos(' ', arg) > 0) then
          begin
            lines[idx] := Trim(Copy(arg, Pos(' ', arg) + 1, Length(arg)));
            dirty := True;
            insertAt := idx + 1;
            Continue;
          end;

          replaceMode := True;
          replaceIdx := idx;
          WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
          WriteLn('Replace line ', idx + 1, ':');
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
          lines[idx] := StringReplace(lines[idx], a1, a2, []);
          dirty := True;
          WriteLn(Format('%6d  %s', [idx + 1, lines[idx]]));
          Continue;
        end;

        WriteLn('Error: unknown command');
        Continue;
      end;

      lines.Insert(insertAt, input);
      Inc(insertAt);
      dirty := True;
    end;
  finally
    if lines <> nil then
      lines.Free;
  end;
end;

end.
