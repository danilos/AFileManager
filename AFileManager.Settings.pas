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

unit AFileManager.Settings;

{ 0.10.6: AFileManager's user configuration behind the AROSA Configuration
  Service (0.10 Service Architecture sec. 8.11).

  AFileManager keeps its INI-style user profile ([Section] Key=Value) as
  the offline copy, but the authority is now the Configuration Service:
    * logical keys  arosa.application.afilemanager/<Section>/<Key>;
    * the "default" workspace maps to the USER layer, any other workspace
      to the WORKSPACE layer of that workspace (a workspace inherits the
      user's settings and overrides them);
    * on load, the resolved values (system, application defaults, user,
      workspace, session) are applied over the descriptor and profile file;
    * the first time the layer is empty, the existing profile file is
      imported, so nobody loses settings when the service appears;
    * on save, the profile file is written as before and the same keys go
      to the service ([Shortcuts] is replaced whole).
  The process security context (managed or compatibility launch) is the
  caller; without one, or with the service down, AFileManager works from
  the files alone, exactly as before. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils,
  Arosa.UI.WindowDescriptors;

const
  AFM_CONFIGURATION_NAMESPACE = 'arosa.application.afilemanager';

{ applies the Configuration Service's view to ADescriptor (importing the
  profile text first when the layer holds nothing yet).  AReport is for the
  diagnostics log: counts only, never values. }
function AfmApplyServiceConfiguration(ADescriptor: TArosaWindowDescriptor;
  const AWorkspaceId, AProfileText: string; out AReport: string): Boolean;
{ stores the profile text in the service }
function AfmStoreServiceConfiguration(const AWorkspaceId, AProfileText: string;
  out AReport: string): Boolean;

implementation

uses
  Arosa.Security.Types,
  Arosa.Services.Session.Client,
  Arosa.Services.Configuration.Client;

const
  WHOLE_SECTIONS: array[0..0] of string = ('Shortcuts');

function Available(out AContext: TArosaAccessContext; out AReport: string): Boolean;
begin
  AContext := EmptyAccessContext;
  Result := False;
  AReport := '';
  if not ArosaProcessSecurityContext(AContext) then
  begin
    AReport := 'no security context';
    Exit;
  end;
  if not ArosaConfigurationServiceRunning then
  begin
    AReport := 'configuration service not running';
    FillChar(AContext, SizeOf(AContext), 0);
    Exit;
  end;
  Result := True;
end;

function AfmApplyServiceConfiguration(ADescriptor: TArosaWindowDescriptor;
  const AWorkspaceId, AProfileText: string; out AReport: string): Boolean;
var
  Ctx: TArosaAccessContext;
  Overlay: string;
begin
  Result := False;
  AReport := '';
  if (ADescriptor = nil) or not Available(Ctx, AReport) then Exit;
  try
    Result := ArosaConfigurationLoadProfile(Ctx, AFM_CONFIGURATION_NAMESPACE, AWorkspaceId,
      AProfileText, WHOLE_SECTIONS, Overlay, AReport);
    if Result then ADescriptor.ApplyOverlay(Overlay, 'configuration-service');
  finally
    FillChar(Ctx, SizeOf(Ctx), 0);
  end;
end;

function AfmStoreServiceConfiguration(const AWorkspaceId, AProfileText: string;
  out AReport: string): Boolean;
var Ctx: TArosaAccessContext;
begin
  Result := False;
  if not Available(Ctx, AReport) then Exit;
  try
    Result := ArosaConfigurationStoreProfile(Ctx, AFM_CONFIGURATION_NAMESPACE, AWorkspaceId,
      AProfileText, WHOLE_SECTIONS, AReport);
  finally
    FillChar(Ctx, SizeOf(Ctx), 0);
  end;
end;

end.
