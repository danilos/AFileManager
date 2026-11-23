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

unit AFileManager.DropRules;

{ 0.10.6.2: what a drag and drop of files does - the rules, without the UI,
  so tests/DropRulesDriver checks them.

    * The target is always a folder (the controller resolves a file row or
      empty space to the folder the pane shows, a volume at its root).
    * Dropping items into the folder they are already in does nothing - a
      drag is never a "duplicate here".  Copies in the same folder come only
      from Copy + Paste (keyboard or context menu).
    * A folder never goes into itself or a folder below it.
    * The operation: Ctrl = copy, Shift = move; a remote location on either
      side = copy (a move would need the provider to delete); otherwise the
      [FileOperations] rule - DragSameVolume (default Move) within one
      volume, DragOtherVolume (default Copy) across volumes; a rule may be
      Ask, which opens a Move / Copy / Cancel menu at the drop. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils,
  Arosa.Services.DataTransfer;

{ normalizes a rule text to Move, Copy or Ask (ADefault otherwise) }
function AfmDragRule(const AValue, ADefault: string): string;

{ the operation of a drop; AAsk = the rule says Ask (the result is then the
  menu's default, Move) }
function AfmDropOperation(ACopyKey, AMoveKey, ARemote, ACrossesVolume: Boolean;
  const ASameVolumeRule, AOtherVolumeRule: string; out AAsk: Boolean): TArosaTransferOperation;

{ True when APath is AFolder or lies below it (case-insensitive; '/' and ':'
  separate, as in AmigaDOS paths and provider URIs) }
function AfmPathInside(const AFolder, APath: string): Boolean;

{ True when dropping an item whose folder is AItemParent into ADestination
  would leave it where it is }
function AfmDropIsSamePlace(const AItemPath, AItemParent, ADestination: string): Boolean;

implementation

function AfmDragRule(const AValue, ADefault: string): string;
begin
  if SameText(Trim(AValue), 'Move') then Result := 'Move'
  else if SameText(Trim(AValue), 'Copy') then Result := 'Copy'
  else if SameText(Trim(AValue), 'Ask') then Result := 'Ask'
  else Result := ADefault;
end;

function AfmDropOperation(ACopyKey, AMoveKey, ARemote, ACrossesVolume: Boolean;
  const ASameVolumeRule, AOtherVolumeRule: string; out AAsk: Boolean): TArosaTransferOperation;
var Rule: string;
begin
  AAsk := False;
  if ARemote then Exit(atoCopy);
  if ACopyKey then Exit(atoCopy);
  if AMoveKey then Exit(atoMove);
  if ACrossesVolume then Rule := AfmDragRule(AOtherVolumeRule, 'Copy')
  else Rule := AfmDragRule(ASameVolumeRule, 'Move');
  if Rule = 'Copy' then Result := atoCopy
  else
  begin
    Result := atoMove;
    AAsk := Rule = 'Ask';
  end;
end;

function Strip(const APath: string): string;
begin
  Result := LowerCase(Trim(APath));
  { a trailing '/' is not part of the name; a trailing ':' is (a volume) }
  while (Length(Result) > 1) and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function AfmPathInside(const AFolder, APath: string): Boolean;
var F, P: string;
begin
  F := Strip(AFolder);
  P := Strip(APath);
  Result := False;
  if (F = '') or (P = '') then Exit;
  if P = F then Exit(True);
  if (Length(P) > Length(F)) and (Copy(P, 1, Length(F)) = F) then
    Result := (F[Length(F)] in ['/', ':']) or (P[Length(F) + 1] = '/');
end;

function AfmDropIsSamePlace(const AItemPath, AItemParent, ADestination: string): Boolean;
begin
  Result := SameText(Strip(AItemParent), Strip(ADestination)) or
    SameText(Strip(AItemPath), Strip(ADestination));
end;

end.
