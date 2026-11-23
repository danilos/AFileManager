// Copyright (c) 2026 DaniloS
// MPL-2.0
unit AFileManager.TransferWorker;

{ The detached transfer worker: AFileManager started with
      --transfer-worker <job file>

  It is a separate AmigaDOS process with its own FPC runtime, so it may
  block in LIST / STAT / AGet / APut for as long as the network needs
  without freezing the AFileManager window.  It never opens a window and
  never asks a question: everything it needs to know is in the job file,
  everything it has to say goes into the result file
  (AFileManager.TransferProtocol describes both).

  0.8.6.1: the worker now PLANS before it runs.  The earlier worker skipped
  every destination that already existed and reported the skip as a
  failure, so a paste onto existing files looked like "copy does not work"
  and no Replace/Skip question was ever shown.  The worker now reports the
  conflicts (with size and date of both sides) and stops; AFileManager asks
  the user and starts the run phase with the answers. }

{$MODE OBJFPC}{$H+}

interface

uses
  Arosa.Services.System, Arosa.Services.Shell, Arosa.Services.Locations;

type
  { Registers the location providers the worker may be asked to use.
    The default registers ATransfer.  Conformance programs replace it to
    run the whole worker against a provider that needs no network. }
  TAFMTransferProviderSetup = procedure(ALocations: TArosaLocationService;
    AShell: TArosaShellService; APaths: TArosaPathService);

var
  AFMTransferProviderSetup: TAFMTransferProviderSetup = nil;

procedure RunAFileManagerTransferWorker(const AJobPath: string);

implementation

uses
  Classes, SysUtils,
  Arosa.ObjectModel,
  Arosa.Platform.Api, Arosa.Platform.Registry,
  {$IFDEF AROS}Arosa.Platform.Aros.Application,{$ELSE}Arosa.Platform.Null.Application,{$ENDIF}
  Arosa.Services.Diagnostics,
  Arosa.Services.Content, Arosa.Services.ResourceAccess,
  Arosa.Services.LocationResourceAccess, Arosa.Services.ResourceOperations,
  Arosa.Services.DataTransfer,
  AFileManager.TransferProtocol;

const
  ProgressIntervalMs = 300;

type
  TTransferRun = class
  private
    FRequest: TAFMTransferRequest;
    FReport: TAFMTransferReport;
    FContent: TArosaContentService;
    FUnits: Integer;
    FCompletedTopLevel: Integer;
    FSerial: Int64;
    FLastProgressTick: QWord;
    FCancelSeen: Boolean;
    FPauseSeen: Boolean;
    FUnplannedConflicts: Integer;
    procedure Progress(const AState, ACurrent: string; AForce: Boolean);
  public
    constructor Create(ARequest: TAFMTransferRequest; AReport: TAFMTransferReport);
    function ErrorDecision(const AOperation, ASource, ADestination,
      AMessage: string): TArosaOperationErrorDecision;
    function ConflictDecision(const ASource, ADestination: string;
      ASourceIsDirectory, ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
    function ContinueTransfer: Boolean;
    procedure TransferProgress(const ASource, ADestination: string);
    property Content: TArosaContentService read FContent write FContent;
    property CancelSeen: Boolean read FCancelSeen;
    property UnplannedConflicts: Integer read FUnplannedConflicts;
    property Units: Integer read FUnits;
  end;

function IsProviderLocation(const ALocation: string): Boolean;
begin
  Result:=Pos('://',Trim(ALocation))>0;
end;

function LeafOf(const ALocation: string): string;
var I: Integer; S: string;
begin
  S:=ALocation;
  while (Length(S)>0) and (S[Length(S)]='/') do Delete(S,Length(S),1);
  I:=Length(S);
  while (I>0) and not (S[I] in ['/',':']) do Dec(I);
  Result:=Copy(S,I+1,MaxInt);
end;

constructor TTransferRun.Create(ARequest: TAFMTransferRequest;
  AReport: TAFMTransferReport);
begin
  inherited Create;
  FRequest:=ARequest;
  FReport:=AReport;
  FContent:=nil;
  FUnits:=0;
  FCompletedTopLevel:=0;
  FSerial:=0;
  FLastProgressTick:=0;
  FCancelSeen:=False;
  FPauseSeen:=False;
  FUnplannedConflicts:=0;
end;

procedure TTransferRun.Progress(const AState, ACurrent: string; AForce: Boolean);
var T: QWord;
begin
  T:=GetTickCount64;
  if (not AForce) and (FLastProgressTick<>0) and
     (T-FLastProgressTick<ProgressIntervalMs) then Exit;
  FLastProgressTick:=T;
  Inc(FSerial);
  AFMWriteProgress(FRequest.ProgressPath,AState,FUnits,FCompletedTopLevel,
    FRequest.Items.Count,ACurrent,FSerial);
  Arosa.Services.Diagnostics.DiagnosticPump;
end;

function TTransferRun.ErrorDecision(const AOperation, ASource, ADestination,
  AMessage: string): TArosaOperationErrorDecision;
begin
  Result:=aoedSkip;
  { A copy interrupted by Cancel is not a failure of that item. }
  if FCancelSeen then Exit;
  FReport.Errors.Add(LeafOf(ASource)+': '+AMessage);
  Diagnostic('TRANSFER-WORKER error operation='+AOperation+' source='+ASource+
    ' destination='+ADestination+' message='+AMessage);
end;

function TTransferRun.ConflictDecision(const ASource, ADestination: string;
  ASourceIsDirectory, ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
begin
  { Reached only for a destination that was NOT there when the plan was
    made (something created it meanwhile).  Nobody can be asked from here,
    so it is left alone and reported - never replaced silently. }
  Inc(FUnplannedConflicts);
  FReport.Errors.Add(LeafOf(ADestination)+
    ': appeared in the destination after the check and was left untouched');
  Diagnostic('TRANSFER-WORKER unplanned conflict source='+ASource+
    ' destination='+ADestination+' decision=skip');
  Result:=arcdSkip;
  if ASourceIsDirectory and ADestinationIsDirectory then ;
end;

function TTransferRun.ContinueTransfer: Boolean;
begin
  if (not FCancelSeen) and (FRequest.CancelPath<>'') and
     SysUtils.FileExists(FRequest.CancelPath) then
  begin
    FCancelSeen:=True;
    Diagnostic('TRANSFER-WORKER cancel requested');
  end;

  { Pause is cooperative, exactly like cancel: it is observed at resource
    boundaries.  While paused this worker sleeps; the Intuition/UI process
    remains completely independent. }
  while (not FCancelSeen) and (FRequest.PausePath<>'') and
        SysUtils.FileExists(FRequest.PausePath) do
  begin
    if not FPauseSeen then
    begin
      FPauseSeen:=True;
      Diagnostic('TRANSFER-WORKER pause requested');
      Progress(AFM_PROGRESS_PAUSED,'',True);
    end;
    SysUtils.Sleep(100);
    Arosa.Services.Diagnostics.DiagnosticPump;
    if (FRequest.CancelPath<>'') and SysUtils.FileExists(FRequest.CancelPath) then
    begin
      FCancelSeen:=True;
      Diagnostic('TRANSFER-WORKER cancel requested while paused');
    end;
  end;

  if FPauseSeen and not FCancelSeen then
  begin
    FPauseSeen:=False;
    Diagnostic('TRANSFER-WORKER resumed');
    Progress(AFM_PROGRESS_RUNNING,'',True);
  end;

  Result:=not FCancelSeen;
end;

procedure TTransferRun.TransferProgress(const ASource, ADestination: string);
begin
  Inc(FUnits);
  { ResourceOperations reports a directory only after its whole recursive tree
    has completed.  Therefore a callback whose source is one of the original
    request items is an exact top-level completion, for files and folders. }
  if FRequest.Items.IndexOf(ASource)>=0 then Inc(FCompletedTopLevel);
  { A fetched original is only needed until it has been copied.  Dropping
    it now keeps T: (usually RAM) from holding a whole remote folder. }
  if (FContent<>nil) and IsProviderLocation(ASource) then
    FContent.Invalidate(ASource);
  Progress(AFM_PROGRESS_RUNNING,LeafOf(ADestination),False);
end;

function SameResource(const A, B: string): Boolean;
begin
  Result:=SameText(ExcludeTrailingPathDelimiter(Trim(A)),
    ExcludeTrailingPathDelimiter(Trim(B)));
end;

procedure DescribeSide(AAccess: TArosaResourceAccess; const ALocation: string;
  out ASide: TAFMConflictSide);
var Info: TArosaFileInfo;
begin
  ASide.Known:=False;
  ASide.IsDirectory:=False;
  ASide.Size:=0;
  ASide.Modified:='';
  if not AAccess.GetInfo(ALocation,Info) then Exit;
  ASide.Known:=True;
  ASide.IsDirectory:=Info.Kind=afekDirectory;
  ASide.Size:=Info.Size;
  if Info.ModifiedUtc>0 then
    ASide.Modified:=FormatDateTime('yyyy-mm-dd hh:nn:ss',Info.ModifiedUtc);
end;

{ APlatform is created here but destroyed by the CALLER, after this
  procedure has returned.  Assigning an interface function result inside a
  try block makes the compiler keep a hidden second reference that it
  releases when this procedure exits; AROSA platform objects are freed
  explicitly, so releasing that reference after the object is gone calls
  through freed memory.  (The 0.8.5.2.0.1 worker destroyed the platform in
  here and so ended every transfer with exactly that call.) }
procedure ExecuteTransfer(var APlatform: IArosaPlatform; const AJobPath: string);
var
  Request: TAFMTransferRequest;
  Report: TAFMTransferReport;
  Run: TTransferRun;
  Paths: TArosaPathService;
  Files: TArosaFileService;
  Locations: TArosaLocationService;
  ATransferProvider: TArosaATransferLocationProvider;
  Shell: TArosaShellService;
  Content: TArosaContentService;
  Access: TArosaLocationResourceAccess;
  Ops: TArosaResourceOperationService;
  ConflictSources, ConflictDestinations: TStringList;
  I, N, Completed, SkipDecisions, SamePlace: Integer;
  CacheDirectory, Planned: string;
  Operation: TArosaTransferOperation;
  Conflict: TAFMConflict;
  Wrote: Boolean;
begin
  Request:=TAFMTransferRequest.Create;
  Report:=TAFMTransferReport.Create;
  ConflictSources:=TStringList.Create;
  ConflictDestinations:=TStringList.Create;
  Run:=nil; Paths:=nil; Files:=nil; Locations:=nil; ATransferProvider:=nil; Shell:=nil; Content:=nil;
  Access:=nil; CacheDirectory:=''; Wrote:=False;
  try
    try
      Request.LoadFromFile(AJobPath);
      { The request is in memory now.  Removing the hand-off file here means
        an exiting AFileManager is never tied to this process by an open
        or leftover file. }
      SysUtils.DeleteFile(AJobPath);

      Run:=TTransferRun.Create(Request,Report);
      { First sign of life.  AFileManager treats a missing progress file as
        "the worker never started" and says so instead of waiting. }
      Run.Progress(AFM_PROGRESS_STARTED,'',True);
      Diagnostic('TRANSFER-WORKER start phase='+Request.Phase+
        ' items='+IntToStr(Request.Items.Count)+' destination='+Request.Destination);

      {$IFDEF AROS}
      APlatform:=ArosaCreatePlatform('AROS');
      {$ELSE}
      APlatform:=ArosaCreatePlatform('Null');
      {$ENDIF}
      Paths:=TArosaPathService.CreateForPlatform(APlatform);
      Files:=TArosaFileService.CreateForPlatform(APlatform,Paths);
      Locations:=TArosaLocationService.Create;
      Locations.RegisterProvider(TArosaLocalLocationProvider.CreateProvider(Paths));
      Shell:=TArosaShellService.CreateForApplication(
        'arosa.application.afilemanager.transfer-worker',
        IntToHex(PtrUInt(Request),SizeOf(Pointer)*2),APlatform,Paths,Files);
      if Assigned(AFMTransferProviderSetup) then
        AFMTransferProviderSetup(Locations,Shell,Paths)
      else
      begin
        ATransferProvider:=TArosaATransferLocationProvider.CreateProvider(Shell,Paths);
        ATransferProvider.TraceComponentId:=AFM_ATRANSFER_TRACE_COMPONENT;
        if Request.ProgressPath<>'' then
          ATransferProvider.ProgressPath:=Request.ProgressPath+'.bytes';
        Locations.RegisterProvider(ATransferProvider);
      end;
      Content:=TArosaContentService.CreateForLocations(Locations,Paths,Files);
      { A cache of its own.  The default cache names are derived from the
        location, so this process and the AFileManager window (which may be
        previewing the very same remote file) would otherwise delete and
        rewrite each other's cached copy. }
      if Request.ResultPath<>'' then
      begin
        CacheDirectory:=ChangeFileExt(Request.ResultPath,'.cache');
        Content.CacheDirectory:=CacheDirectory;
      end;
      Run.Content:=Content;
      Access:=TArosaLocationResourceAccess.CreateForLocations(
        Locations,Content,Paths,Files);
      Ops:=Shell.Operations;
      Ops.ResourceAccess:=Access;
      Ops.OnError:=@Run.ErrorDecision;
      Ops.OnConflict:=@Run.ConflictDecision;
      Ops.OnTransferContinue:=@Run.ContinueTransfer;
      Ops.OnTransferProgress:=@Run.TransferProgress;

      if Request.Move then Operation:=atoMove else Operation:=atoCopy;
      { A provider cannot remove its own resources yet, so a move out of one
        could only ever end as "copied, then failed to delete".  Do what can
        be done - copy - and say so, instead of reporting a failure for a
        file that arrived intact. }
      if Operation=atoMove then
        for I:=0 to Request.Items.Count-1 do
          if IsProviderLocation(Request.Items[I]) then
          begin
            Operation:=atoCopy;
            Report.MovedAsCopy:=True;
            Break;
          end;

      if Request.Phase=AFM_PHASE_PLAN then
      begin
        Run.Progress(AFM_PROGRESS_PLANNING,'',True);
        N:=Ops.PlanTransferConflicts(Request.Items,Request.Destination,Operation,
          ConflictSources,ConflictDestinations);
        Diagnostic('TRANSFER-WORKER plan conflicts='+IntToStr(N));
        if N>0 then
        begin
          for I:=0 to ConflictDestinations.Count-1 do
          begin
            Conflict.Source:=ConflictSources[I];
            Conflict.Destination:=ConflictDestinations[I];
            DescribeSide(Access,Conflict.Source,Conflict.Incoming);
            DescribeSide(Access,Conflict.Destination,Conflict.Existing);
            Report.AddConflict(Conflict);
            if not Run.ContinueTransfer then Break;
          end;
          if Run.CancelSeen then
          begin
            Report.State:=AFM_STATE_CANCELLED;
            Report.Message:='cancelled before anything was changed';
          end
          else
            Report.State:=AFM_STATE_PLAN;
          Report.SaveToFile(Request.ResultPath);
          Wrote:=True;
        end;
        { No conflict: nothing to ask, so do the work now rather than pay
          for a second process start. }
      end;

      if not Wrote then
      begin
        SkipDecisions:=0;
        for I:=0 to Request.DecisionCount-1 do
          if Request.DecisionChoice(I)=afccReplace then
            Ops.PresetConflictDecision(Request.DecisionDestination(I),arcdReplace)
          else
          begin
            Ops.PresetConflictDecision(Request.DecisionDestination(I),arcdSkip);
            Inc(SkipDecisions);
          end;

        { A move onto its own folder is nothing to do; the service leaves
          such items alone.  Count them so they are not reported as failed. }
        SamePlace:=0;
        if Operation=atoMove then
          for I:=0 to Request.Items.Count-1 do
          begin
            Planned:=Access.Join(Request.Destination,Access.LeafName(Request.Items[I]));
            if SameResource(Planned,Request.Items[I]) then Inc(SamePlace);
          end;

        Run.Progress(AFM_PROGRESS_RUNNING,'',True);
        Completed:=0;
        Ops.Transfer(Request.Items,Request.Destination,Operation,Completed);
        Ops.ClearConflictDecisions;

        Report.Completed:=Completed;
        Report.Units:=Run.Units;
        Report.Skipped:=SkipDecisions+Run.UnplannedConflicts+SamePlace;
        if Report.Skipped>Request.Items.Count-Completed then
          Report.Skipped:=Request.Items.Count-Completed;
        Report.Failed:=Request.Items.Count-Completed-Report.Skipped;
        if Report.Failed<0 then Report.Failed:=0;

        if Run.CancelSeen then
        begin
          Report.State:=AFM_STATE_CANCELLED;
          { whatever was not reached is neither skipped nor failed }
          Report.Failed:=0;
          Report.Message:='cancelled';
        end
        else if (Report.Failed=0) and (Report.Errors.Count=0) then
        begin
          Report.State:=AFM_STATE_OK;
          Report.Message:='completed';
        end
        else
        begin
          Report.State:=AFM_STATE_PARTIAL;
          if Report.Errors.Count>0 then Report.Message:=Report.Errors[0]
          else Report.Message:='not every requested item was transferred';
        end;
        Diagnostic('TRANSFER-WORKER done state='+Report.State+
          ' completed='+IntToStr(Report.Completed)+
          ' skipped='+IntToStr(Report.Skipped)+
          ' failed='+IntToStr(Report.Failed)+
          ' units='+IntToStr(Report.Units));
        Report.SaveToFile(Request.ResultPath);
        Wrote:=True;
      end;
    except
      on E: Exception do
      begin
        Diagnostic('TRANSFER-WORKER exception '+E.ClassName+': '+E.Message);
        if not Wrote then
        begin
          Report.State:=AFM_STATE_ERROR;
          Report.Message:=E.Message;
          try
            Report.SaveToFile(Request.ResultPath);
          except
            { nowhere left to report to }
          end;
        end;
      end;
    end;
  finally
    { Destroy in dependency order.  The platform outlives all of it. }
    if Shell<>nil then
    begin
      Shell.Operations.OnError:=nil;
      Shell.Operations.OnConflict:=nil;
      Shell.Operations.OnTransferContinue:=nil;
      Shell.Operations.OnTransferProgress:=nil;
      Shell.Operations.ResourceAccess:=nil;
    end;
    Access.Free;
    Content.Free;
    if CacheDirectory<>'' then SysUtils.RemoveDir(CacheDirectory);
    Shell.Free;
    Locations.Free;
    Files.Free;
    Paths.Free;
    Run.Free;
    ConflictSources.Free;
    ConflictDestinations.Free;
    if Request.ProgressPath<>'' then
    begin
      SysUtils.DeleteFile(Request.ProgressPath);
      SysUtils.DeleteFile(Request.ProgressPath+'.tmp');
      SysUtils.DeleteFile(Request.ProgressPath+'.bytes');
      SysUtils.DeleteFile(Request.ProgressPath+'.bytes.tmp');
    end;
    Report.Free;
    Request.Free;
  end;
end;

procedure RunAFileManagerTransferWorker(const AJobPath: string);
var Platform: IArosaPlatform;
begin
  if Trim(AJobPath)='' then Exit;
  Platform:=nil;
  { The worker's own diagnostics go to the message service like everybody
    else's, under their own source name.  Without a broker they stay in a
    bounded memory queue and are dropped at exit; nothing waits for them. }
  DiagnosticStart('arosa.application.afilemanager.transfer-worker');
  try
    ExecuteTransfer(Platform,AJobPath);
  finally
    ArosaDestroyPlatform(Platform);
    DiagnosticStop;
  end;
end;

end.
