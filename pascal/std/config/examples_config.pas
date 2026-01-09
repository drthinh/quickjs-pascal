unit examples_config;

{$mode objfpc}{$H+}

interface

type
  // Example test configuration type
  TExampleConfig = record
    enabled: boolean;
    name: string;
  end;

  TExampleConfigs = array of TExampleConfig;

function DefaultExamplesConfigFile: string;
procedure LoadExamplesConfigFromFile(var Configs: TExampleConfigs; const FileName: string; DebugLevel: integer);
procedure SaveExamplesConfigToFile(const FileName: string; const Configs: TExampleConfigs);
function FindExampleConfig(const Configs: TExampleConfigs; const name: string): integer;

implementation

uses
  SysUtils, Classes, fpjson, jsonparser;

function DefaultExamplesConfigFile: string;
var
  exe_dir: string;
  pascal_root: string;
begin
  exe_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  pascal_root := ExpandFileName(IncludeTrailingPathDelimiter(exe_dir) + '..');
  Result := IncludeTrailingPathDelimiter(pascal_root) + 'config' + PathDelim + 'qjs_examples.json';
end;

// Helper function to load examples config from JSON file
procedure LoadExamplesConfigFromFile(var Configs: TExampleConfigs; const FileName: string; DebugLevel: integer);
var
  json_content, line: string;
  f: TextFile;
  jsonData, examplesData: TJSONData;
  rootObj, examplesObj: TJSONObject;
  i, count: integer;
  key: string;
  item: TJSONData;
  enabled: boolean;
begin
  // Start with empty configuration
  SetLength(Configs, 0);

  // If config file does not exist, leave the list empty
  if not FileExists(FileName) then
    Exit;

  // Read JSON file into a single string
  json_content := '';
  AssignFile(f, FileName);
  Reset(f);
  try
    while not EOF(f) do
    begin
      ReadLn(f, line);
      if json_content <> '' then
        json_content := json_content + LineEnding;
      json_content := json_content + line;
    end;
  finally
    CloseFile(f);
  end;

  if json_content = '' then
    Exit;

  // Parse JSON using FreePascal's fpjson
  try
    jsonData := GetJSON(json_content);
  except
    on E: Exception do
    begin
      if DebugLevel > 0 then
        WriteLn('[DEBUG] Failed to parse examples config JSON (fpjson): ', E.Message);
      Exit;
    end;
  end;

  try
    if not (jsonData is TJSONObject) then
      Exit;

    rootObj := TJSONObject(jsonData);
    examplesData := rootObj.Find('examples');
    if (examplesData = nil) or not (examplesData is TJSONObject) then
      Exit;

    examplesObj := TJSONObject(examplesData);
    count := examplesObj.Count;
    SetLength(Configs, count);

    for i := 0 to count - 1 do
    begin
      key := examplesObj.Names[i];
      item := examplesObj.Items[i];

      if (item <> nil) and (item.JSONType = jtBoolean) then
        enabled := item.AsBoolean
      else
        enabled := False;

      Configs[i].name := key;
      Configs[i].enabled := enabled;
    end;
  finally
    jsonData.Free;
  end;
end;

// Helper function to save examples config to JSON file
procedure SaveExamplesConfigToFile(const FileName: string; const Configs: TExampleConfigs);
var
  rootObj, examplesObj: TJSONObject;
  f: TextFile;
  i: integer;
  jsonStr: string;
  out_dir: string;
begin
  // Build JSON structure: { "examples": { "name": boolean, ... } }
  rootObj := TJSONObject.Create;
  try
    examplesObj := TJSONObject.Create;
    rootObj.Add('examples', examplesObj);

    // Add each example to examples object
    for i := 0 to Length(Configs) - 1 do
      examplesObj.Add(Configs[i].name, Configs[i].enabled);

    // Serialize to string
    jsonStr := rootObj.FormatJSON([]);

    out_dir := ExtractFileDir(FileName);
    if (out_dir <> '') and (not DirectoryExists(out_dir)) then
      ForceDirectories(out_dir);

    // Write to file
    AssignFile(f, FileName);
    Rewrite(f);
    try
      Write(f, jsonStr);
    finally
      CloseFile(f);
    end;
  finally
    rootObj.Free;
  end;
end;

// Helper function to find example config index by name
function FindExampleConfig(const Configs: TExampleConfigs; const name: string): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to Length(Configs) - 1 do
  begin
    if Configs[i].name = name then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

end.
