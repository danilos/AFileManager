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


unit AFileManager.Context;

{ Shared AFileManager state exposed to AROSA window capabilities. }

{$MODE OBJFPC}{$H+}

interface

uses Classes, SysUtils, Arosa.ObjectModel, Arosa.UI.WindowCapabilities;

type
  TAFileManagerContext = class(TArosaObject,
    IArosaNavigationProvider, IArosaPreviewProvider,
    IArosaCommandEnvironmentProvider, IArosaOperationTargetProvider)
  private
    FActiveLocation: string;
    FSecondaryLocation: string;
    FFocusedResource: string;
    FSelection: TStringList;
    FOnNavigate: TNotifyEvent;
    FOnRefresh: TNotifyEvent;
  protected
    procedure DoDispose; override;
  public
    constructor Create;
    function ActiveLocation: string;
    function SecondaryLocation: string;
    procedure NavigateActive(const ALocation: string);
    procedure Refresh;
    function PreviewResource: string;
    function WorkingDirectory: string;
    function SelectionVariable: string;
    function ActiveTarget: string;
    function SecondaryTarget: string;
    procedure SetLocations(const AActive, ASecondary: string);
    procedure SetFocusedResource(const AResource: string);
    procedure SetSelection(ASelection: TStrings);
    property OnNavigate: TNotifyEvent read FOnNavigate write FOnNavigate;
    property OnRefresh: TNotifyEvent read FOnRefresh write FOnRefresh;
  end;

implementation

constructor TAFileManagerContext.Create;
begin
  inherited Create;
  FSelection := TStringList.Create;
end;

procedure TAFileManagerContext.DoDispose;
begin
  FreeAndNil(FSelection);
  inherited DoDispose;
end;

function TAFileManagerContext.ActiveLocation: string; begin Result:=FActiveLocation; end;
function TAFileManagerContext.SecondaryLocation: string; begin Result:=FSecondaryLocation; end;
procedure TAFileManagerContext.NavigateActive(const ALocation: string);
begin FActiveLocation:=ALocation; if Assigned(FOnNavigate) then FOnNavigate(Self); end;
procedure TAFileManagerContext.Refresh;
begin if Assigned(FOnRefresh) then FOnRefresh(Self); end;
function TAFileManagerContext.PreviewResource: string; begin Result:=FFocusedResource; end;
function TAFileManagerContext.WorkingDirectory: string; begin Result:=FActiveLocation; end;
function TAFileManagerContext.SelectionVariable: string; begin Result:=FSelection.CommaText; end;
function TAFileManagerContext.ActiveTarget: string; begin Result:=FActiveLocation; end;
function TAFileManagerContext.SecondaryTarget: string; begin Result:=FSecondaryLocation; end;
procedure TAFileManagerContext.SetLocations(const AActive, ASecondary: string);
begin FActiveLocation:=AActive; FSecondaryLocation:=ASecondary; end;
procedure TAFileManagerContext.SetFocusedResource(const AResource: string);
begin FFocusedResource:=AResource; end;
procedure TAFileManagerContext.SetSelection(ASelection: TStrings);
begin if ASelection=nil then FSelection.Clear else FSelection.Assign(ASelection); end;

end.
