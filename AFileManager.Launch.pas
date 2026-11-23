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

unit AFileManager.Launch;

{ 0.8.27.10: how an AFileManager launch decides whether it becomes the
  running instance.  Kept out of the program file so that
  tests/LaunchDecisionDriver can exercise it against a simulated owner. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils,
  Arosa.Platform.Aros.Process,
  Arosa.Platform.Aros.MonotonicClock,
  Arosa.Platform.Aros.ApplicationEndpoint;

const
  AFM_APPLICATION_ID = 'arosa.application.afilemanager';
  { 0.8.27.10: diagnostics identity of a launch that does not become the
    running instance.  Its records go to the running instance's log as a
    child component; it never sends that log a new session.start, so the
    running instance's log is not restarted (the "-02" files that mixed two
    processes in 0.8.27.8). }
  AFM_LAUNCHER_ID = 'arosa.application.afilemanager.launcher';
  { An owner that is starting or exiting must report a new stage within
    this time; a running owner must show a heartbeat within the second
    limit; nobody waits longer than the third. }
  AFM_OWNER_PROGRESS_MS = 15000;
  AFM_OWNER_HEARTBEAT_MS = 3000;
  AFM_CLAIM_LIMIT_MS = 60000;
  { 0.8.29.1: an owner task that has not been on the Exec task lists for
    this long, without any progress, is gone; its endpoint is retired and
    the launch claims a new one.  Generous on purpose: on an SMP kernel a
    task running on another CPU is not on those lists either, and a
    starting AFileManager can spend seconds in one stage. }
  AFM_OWNER_GONE_MS = 10000;

type
  TAFMLaunchDecision = (afldRun, afldHandedOff, afldRefused);

function AFileManagerClaimInstance(out AReport, AMessage: string;
  out AWaitedMs: QWord): TAFMLaunchDecision;

{ 0.8.29.1: the launch decision told to the user.  On an interactive CLI it
  is a line in that window; otherwise (RUN >NIL:, Workbench, a script with
  redirected output) an Intuition requester, so a launch never ends
  unexplained. }
procedure AFileManagerTellUser(const AText: string);

{ The same decision for any application id, with the time limits given.
  AFileManagerClaimInstance uses the AFM_* limits above. }
function ArosaClaimApplicationInstance(const AApplicationId, ADisplayName: string;
  AProgressMs, AHeartbeatMs, ALimitMs: QWord;
  out AReport, AMessage: string; out AWaitedMs: QWord): TAFMLaunchDecision;

implementation

{$IFDEF AROS}
uses
  Exec, AmigaDOS, Intuition;
{$ENDIF}

procedure AFileManagerTellUser(const AText: string);
{$IFDEF AROS}
var
  OutHandle: BPTR;
  ES: TEasyStruct;
  Body, Title, Gadget: AnsiString;
{$ENDIF}
begin
  if Trim(AText)='' then Exit;
  {$IFDEF AROS}
  OutHandle:=DOSOutput;
  if (OutHandle<>BPTR(0)) and (IsInteractive(OutHandle)<>0) then
  begin
    ArosaConsoleLine(AText);
    Exit;
  end;
  { the text is a printf format: no conversions in it }
  Body:=StringReplace(AText,'%','%%',[rfReplaceAll]);
  Title:='AFileManager';
  Gadget:='OK';
  FillChar(ES,SizeOf(ES),0);
  ES.es_StructSize:=SizeOf(TEasyStruct);
  ES.es_Flags:=0;
  ES.es_Title:=PChar(Title);
  ES.es_TextFormat:=PChar(Body);
  ES.es_GadgetFormat:=PChar(Gadget);
  try
    EasyRequestArgs(nil,@ES,nil,nil);
  except
    { nothing else can be done }
  end;
  {$ELSE}
  ArosaConsoleLine(AText);
  {$ENDIF}
end;

{ 0.8.27.10: single-instance decision through the AROSA application
  endpoint (Arosa.Platform.Aros.ApplicationEndpoint).  It replaces the
  0.8.27.9 Exec task-name rule, under which two simultaneous launches could
  both continue, a process stuck in startup silently rejected every later
  launch, and the transfer worker counted as an instance.

    no owner                -> this process becomes the instance
    owner running           -> ask it to come to the front; it must show a
                               heartbeat, then this launch ends (handed off)
    owner starting/exiting  -> wait while it reports progress: a starting
                               owner is handed off once it runs, an exiting
                               owner is replaced once it is gone
    no progress / heartbeat -> refuse, and say why (log + launching CLI)
    owner task gone         -> 0.8.29.1: the endpoint of a process that
                               died without withdrawing it (crash
                               requester, killed task) is retired after
                               AFM_OWNER_GONE_MS and this launch runs.
                               Before, such a leftover refused every later
                               launch until a reboot - silently under
                               RUN >NIL:. }
function ArosaClaimApplicationInstance(const AApplicationId, ADisplayName: string;
  AProgressMs, AHeartbeatMs, ALimitMs: QWord;
  out AReport, AMessage: string; out AWaitedMs: QWord): TAFMLaunchDecision;
var
  Info: TArosaAppEndpointInfo;
  Started, ProgressAt, BeatAt: QWord;
  LastSerial, LastBeat: LongWord;
  LastPhase: TArosaAppEndpointPhase;
  Activated: Boolean;
  Claim: TArosaAppEndpointClaim;
  GoneSince: QWord;
  GoneOwner: PtrUInt;
  GoneSerial, GoneBeat: LongWord;
  Retired: string;

  function OwnerText: string;
  begin
    Result:='owner='+IntToHex(Info.OwnerTask,8)+
      ' owner-phase='+ArosaAppEndpointPhaseName(Info.Phase)+
      ' owner-stage='+Info.Stage;
  end;

  function OwnerSentence: string;
  begin
    Result:='task '+IntToHex(Info.OwnerTask,8)+', '+
      ArosaAppEndpointPhaseName(Info.Phase)+', stage "'+Info.Stage+'"';
  end;

begin
  AReport:='';
  AMessage:='';
  AWaitedMs:=0;
  Started:=ArosaMonotonicMilliseconds;
  ProgressAt:=Started;
  BeatAt:=Started;
  LastSerial:=0;
  LastBeat:=0;
  LastPhase:=aapeAbsent;
  Activated:=False;
  GoneSince:=0;
  GoneOwner:=0;
  GoneSerial:=0;
  GoneBeat:=0;
  Retired:='';
  Info:=Default(TArosaAppEndpointInfo);
  repeat
    AWaitedMs:=ArosaMonotonicElapsed(Started);
    Claim:=ArosaAppEndpointClaim(AApplicationId);
    if Claim=aaecClaimed then
    begin
      if Retired<>'' then
        AReport:=Retired
      else if LastPhase<>aapeAbsent then
        AReport:='instance-claimed-after-previous-owner '+OwnerText;
      Exit(afldRun);
    end;
    if Claim=aaecUnavailable then
    begin
      AReport:='application-endpoint-unavailable single-instance=not-enforced';
      Exit(afldRun);
    end;

    if not ArosaAppEndpointInspect(AApplicationId,Info) then
    begin
      if Info.Foreign then
      begin
        AReport:='application-endpoint-name-used-by-foreign-port name='+
          ArosaAppEndpointName(AApplicationId)+
          ' single-instance=not-enforced';
        Exit(afldRun);
      end;
      { the owner withdrew between the two calls: claim again }
      Sleep(20);
      Continue;
    end;

    if (Info.StageSerial<>LastSerial) or (Info.Phase<>LastPhase) then
    begin
      LastSerial:=Info.StageSerial;
      LastPhase:=Info.Phase;
      ProgressAt:=ArosaMonotonicMilliseconds;
    end;

    { 0.8.29.1: an owner that is no longer an Exec task and shows no
      progress is gone.  Being listed, a new owner, a new stage or a new
      heartbeat restarts the count. }
    if Info.OwnerListed or (Info.OwnerTask<>GoneOwner) or
       (Info.StageSerial<>GoneSerial) or (Info.Heartbeat<>GoneBeat) then
    begin
      GoneSince:=0;
      GoneOwner:=Info.OwnerTask;
      GoneSerial:=Info.StageSerial;
      GoneBeat:=Info.Heartbeat;
    end;
    if not Info.OwnerListed then
    begin
      if GoneSince=0 then
        GoneSince:=ArosaMonotonicMilliseconds
      else if ArosaMonotonicElapsed(GoneSince)>=AFM_OWNER_GONE_MS then
      begin
        if ArosaAppEndpointRetireStale(AApplicationId,Info.OwnerTask) then
          Retired:='stale-endpoint-retired owner-gone-ms='+
            IntToStr(ArosaMonotonicElapsed(GoneSince))+' '+OwnerText;
        GoneSince:=0;
        { claim again; if the owner reappeared, the next pass sees it }
        Continue;
      end;
      { while the owner is unlisted its silence is not yet a refusal }
      if ArosaMonotonicElapsed(Started)<ALimitMs then
      begin
        Sleep(100);
        Continue;
      end;
    end;

    if Info.Phase=aapeRunning then
    begin
      if not Activated then
      begin
        ArosaAppEndpointRequest(AApplicationId,aaerActivate);
        Activated:=True;
        LastBeat:=Info.Heartbeat;
        BeatAt:=ArosaMonotonicMilliseconds;
      end
      else if Info.Heartbeat<>LastBeat then
      begin
        AReport:='handed-off '+OwnerText;
        AMessage:=ADisplayName+' is already running ('+OwnerSentence+
          '); its window was brought to the front.';
        Exit(afldHandedOff);
      end
      else if ArosaMonotonicElapsed(BeatAt)>=AHeartbeatMs then
      begin
        AReport:='owner-unresponsive no-heartbeat-ms='+
          IntToStr(ArosaMonotonicElapsed(BeatAt))+' '+OwnerText;
        AMessage:=ADisplayName+' is already running ('+OwnerSentence+
          ') but has not answered for '+
          IntToStr(ArosaMonotonicElapsed(BeatAt) div 1000)+
          ' s. It will come to the front when it responds.';
        Exit(afldRefused);
      end;
    end
    else if ArosaMonotonicElapsed(ProgressAt)>=AProgressMs then
    begin
      AReport:='owner-stalled no-progress-ms='+
        IntToStr(ArosaMonotonicElapsed(ProgressAt))+' '+OwnerText;
      AMessage:='Another '+ADisplayName+' process ('+OwnerSentence+
        ') has made no progress for '+
        IntToStr(ArosaMonotonicElapsed(ProgressAt) div 1000)+
        ' s. This launch was not started.';
      Exit(afldRefused);
    end;

    if ArosaMonotonicElapsed(Started)>=ALimitMs then
    begin
      AReport:='owner-wait-limit waited-ms='+
        IntToStr(ArosaMonotonicElapsed(Started))+' '+OwnerText;
      AMessage:='Another '+ADisplayName+' process ('+OwnerSentence+
        ') is still busy after '+IntToStr(ALimitMs div 1000)+
        ' s. This launch was not started.';
      Exit(afldRefused);
    end;
    Sleep(100);
  until False;
end;

function AFileManagerClaimInstance(out AReport, AMessage: string;
  out AWaitedMs: QWord): TAFMLaunchDecision;
begin
  Result:=ArosaClaimApplicationInstance(AFM_APPLICATION_ID,'AFileManager',
    AFM_OWNER_PROGRESS_MS,AFM_OWNER_HEARTBEAT_MS,AFM_CLAIM_LIMIT_MS,
    AReport,AMessage,AWaitedMs);
end;

end.
