// // Copyright (c) 2026 DaniloS
// //
// // This file is part of the AFileManager project.
// //
// // Original author: Danilo S.
// //
// // This Source Code Form is subject to the terms of the
// // Mozilla Public License, v. 2.0.
// // If a copy of the MPL was not distributed with this
// // file, You can obtain one at https://mozilla.org/MPL/2.0/.


unit AFileManager.CommandHistory;

{$MODE OBJFPC}{$H+}

interface

uses Classes, SysUtils, Arosa.ObjectModel;

type
  TAFileManagerCommandHistory = class(TArosaObject)
  private
    FItems: TStringList;
    FPath: string;
    FMaxEntries: Integer;
    procedure TrimToLimit;
  protected
    procedure DoDispose; override;
  public
    constructor CreateHistory(const APath: string; AMaxEntries: Integer);
    procedure Load;
    procedure Save;
    procedure Remember(const ACommand: string);
    procedure Remove(const ACommand: string);
    procedure Clear;
    function Count: Integer;
    function Item(AIndex: Integer): string;
  end;

implementation

constructor TAFileManagerCommandHistory.CreateHistory(const APath: string;
  AMaxEntries: Integer);
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.CaseSensitive := False;
  FPath := APath;
  FMaxEntries := AMaxEntries;
end;

procedure TAFileManagerCommandHistory.DoDispose;
begin
  Save;
  FreeAndNil(FItems);
  inherited DoDispose;
end;

procedure TAFileManagerCommandHistory.TrimToLimit;
begin
  if FMaxEntries <= 0 then Exit;
  while FItems.Count > FMaxEntries do FItems.Delete(FItems.Count-1);
end;

procedure TAFileManagerCommandHistory.Load;
begin
  FItems.Clear;
  if FileExists(FPath) then
    try FItems.LoadFromFile(FPath); except FItems.Clear; end;
  TrimToLimit;
end;

procedure TAFileManagerCommandHistory.Save;
begin
  if (FItems=nil) or (FPath='') then Exit;
  try FItems.SaveToFile(FPath); except end;
end;

procedure TAFileManagerCommandHistory.Remember(const ACommand: string);
var C: string; I: Integer;
begin
  C := Trim(ACommand);
  if C='' then Exit;
  I := FItems.IndexOf(C);
  if I>=0 then FItems.Delete(I);
  FItems.Insert(0,C);
  TrimToLimit;
  Save;
end;

procedure TAFileManagerCommandHistory.Remove(const ACommand: string);
var I: Integer;
begin
  I := FItems.IndexOf(Trim(ACommand));
  if I>=0 then begin FItems.Delete(I); Save; end;
end;

procedure TAFileManagerCommandHistory.Clear;
begin FItems.Clear; Save; end;
function TAFileManagerCommandHistory.Count: Integer;
begin Result:=FItems.Count; end;
function TAFileManagerCommandHistory.Item(AIndex: Integer): string;
begin if (AIndex>=0) and (AIndex<FItems.Count) then Result:=FItems[AIndex] else Result:=''; end;

end.
