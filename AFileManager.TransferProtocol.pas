// Copyright (c) 2026 DaniloS
// MPL-2.0
unit AFileManager.TransferProtocol;

{ The hand-off between AFileManager and its detached transfer worker.

  Both ends are the same executable (the worker is AFileManager started with
  --transfer-worker), but they are different processes and share nothing
  except small text files in T:.  This unit is the ONE description of those
  files, used by both ends, so the two can never disagree about a key name.

      <stamp>.job        written by the UI, read once by the worker
      <stamp>.progress   rewritten by the worker while it runs
      <stamp>.result     written once by the worker when it stops
      <stamp>.cancel     created by the UI to ask the worker to stop

  A transfer is two phases, because the worker may not show a window and the
  UI may not talk to a remote server:

      plan   the worker finds every destination that already exists and
             reports it, with size and date of both sides.  Nothing is
             changed.  When there is no conflict it carries straight on to
             "run" in the same process.
      run    the worker performs the transfer, applying the decisions the
             user made for the planned conflicts.

  Every file is written to a temporary name and renamed, so a reader sees
  either the previous complete file or the new complete file. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils;

const
  AFM_TRANSFER_VERSION = '4';

  { Application-owned diagnostics component for ATransfer activity.  Starting
    AFileManager with --trace=arosa.application.afilemanager.atransfer traces
    navigation plus detached transfer-worker ATransfer activity without
    enabling unrelated AFileManager trace traffic. }
  AFM_ATRANSFER_TRACE_COMPONENT = 'arosa.application.afilemanager.atransfer';

  AFM_PHASE_PLAN = 'plan';
  AFM_PHASE_RUN  = 'run';

  { result states }
  AFM_STATE_PLAN      = 'plan';       { conflicts found; nothing changed }
  AFM_STATE_OK        = 'ok';         { everything asked for was done }
  AFM_STATE_PARTIAL   = 'partial';    { finished, but some items failed }
  AFM_STATE_CANCELLED = 'cancelled';
  AFM_STATE_ERROR     = 'error';      { could not run at all }

  { progress states }
  AFM_PROGRESS_STARTED  = 'started';
  AFM_PROGRESS_PLANNING = 'planning';
  AFM_PROGRESS_RUNNING  = 'running';
  AFM_PROGRESS_PAUSED   = 'paused';

type
  TAFMConflictChoice = (afccSkip, afccReplace);

  { One side of a conflict as the worker saw it. }
  TAFMConflictSide = record
    Known: Boolean;        { False: the worker could not read its details }
    IsDirectory: Boolean;
    Size: Int64;
    Modified: string;      { "yyyy-mm-dd hh:nn:ss", '' when unknown }
  end;

  TAFMConflict = record
    Source: string;
    Destination: string;
    Incoming: TAFMConflictSide;
    Existing: TAFMConflictSide;
  end;

  { What the UI asks the worker to do. }
  TAFMTransferRequest = class
  private
    FItems: TStringList;
    FDecisionDestinations: TStringList;
    FDecisionChoices: array of TAFMConflictChoice;
  public
    Phase: string;
    Move: Boolean;
    Destination: string;
    ResultPath: string;
    ProgressPath: string;
    CancelPath: string;
    PausePath: string;
    constructor Create;
    destructor Destroy; override;
    procedure AddDecision(const ADestination: string; AChoice: TAFMConflictChoice);
    function DecisionCount: Integer;
    function DecisionDestination(AIndex: Integer): string;
    function DecisionChoice(AIndex: Integer): TAFMConflictChoice;
    procedure SaveToFile(const APath: string);
    { Raises an exception that says what is wrong with the file. }
    procedure LoadFromFile(const APath: string);
    property Items: TStringList read FItems;
  end;

  { What the worker answers. }
  TAFMTransferReport = class
  private
    FConflicts: array of TAFMConflict;
    FConflictCount: Integer;
    FErrors: TStringList;
    function GetConflict(AIndex: Integer): TAFMConflict;
  public
    State: string;
    Completed: Integer;    { top-level items transferred }
    Skipped: Integer;      { top-level items left alone by decision }
    Failed: Integer;       { top-level items that were asked for and not done }
    Units: Integer;        { files and folders processed, all levels }
    MovedAsCopy: Boolean;  { a move was done as a copy (source cannot delete) }
    Message: string;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddConflict(const AConflict: TAFMConflict);
    procedure SaveToFile(const APath: string);
    function LoadFromFile(const APath: string): Boolean;
    function Finished: Boolean;
    property ConflictCount: Integer read FConflictCount;
    property Conflicts[AIndex: Integer]: TAFMConflict read GetConflict;
    property Errors: TStringList read FErrors;
  end;

  TAFMTransferProgress = record
    Valid: Boolean;
    State: string;
    Units: Integer;
    Completed: Integer;    { top-level items completely transferred }
    Total: Integer;        { total top-level items requested; 0 if unknown }
    Current: string;       { leaf name of the item last finished }
    Serial: Int64;         { changes every time the worker writes }
  end;

  { AGet/APut byte telemetry.  This is separate from the worker's item-level
    progress because the helper process can update it while the worker is
    blocked waiting for that one command to finish. }
  TAFMTransferByteProgress = record
    Valid: Boolean;
    State: string;
    Direction: string;
    Bytes: Int64;
    Total: Int64;
    Source: string;
    Target: string;
    Serial: Int64;
  end;

{ Paths for one transfer, derived from one stamp so they cannot collide
  with another transfer or another AFileManager. }
function AFMTransferFile(const AStamp, AExtension: string): string;

procedure AFMWriteProgress(const APath, AState: string; AUnits, ACompleted,
  ATotal: Integer; const ACurrent: string; ASerial: Int64);
function AFMReadProgress(const APath: string): TAFMTransferProgress;
function AFMReadByteProgress(const APath: string): TAFMTransferByteProgress;

{ Write AText to APath so a reader never sees half a file. }
procedure AFMWriteAtomic(const APath: string; ALines: TStrings);

implementation

function OneLine(const S: string): string;
begin
  Result:=StringReplace(StringReplace(S,#13,' ',[rfReplaceAll]),#10,' ',[rfReplaceAll]);
end;

function AFMTransferFile(const AStamp, AExtension: string): string;
begin
  {$IFDEF AROS}
  Result:='T:afm-transfer-'+AStamp+'.'+AExtension;
  {$ELSE}
  Result:=IncludeTrailingPathDelimiter(GetTempDir)+'afm-transfer-'+AStamp+'.'+AExtension;
  {$ENDIF}
end;

procedure AFMWriteAtomic(const APath: string; ALines: TStrings);
var Tmp: string;
begin
  if Trim(APath)='' then Exit;
  Tmp:=APath+'.tmp';
  SysUtils.DeleteFile(Tmp);
  ALines.SaveToFile(Tmp);
  SysUtils.DeleteFile(APath);
  if not SysUtils.RenameFile(Tmp,APath) then
  begin
    { Last resort: the reader tolerates a file it cannot parse yet and
      simply reads again on its next poll. }
    ALines.SaveToFile(APath);
    SysUtils.DeleteFile(Tmp);
  end;
end;

procedure AFMWriteProgress(const APath, AState: string; AUnits, ACompleted,
  ATotal: Integer; const ACurrent: string; ASerial: Int64);
var L: TStringList;
begin
  if Trim(APath)='' then Exit;
  L:=TStringList.Create;
  try
    L.Values['state']:=AState;
    L.Values['units']:=IntToStr(AUnits);
    L.Values['completed']:=IntToStr(ACompleted);
    L.Values['total']:=IntToStr(ATotal);
    L.Values['current']:=OneLine(ACurrent);
    L.Values['serial']:=IntToStr(ASerial);
    try
      AFMWriteAtomic(APath,L);
    except
      { Progress is advisory.  A full T: must not stop a transfer. }
    end;
  finally
    L.Free;
  end;
end;

function AFMReadProgress(const APath: string): TAFMTransferProgress;
var L: TStringList;
begin
  Result.Valid:=False;
  Result.State:='';
  Result.Units:=0;
  Result.Completed:=0;
  Result.Total:=0;
  Result.Current:='';
  Result.Serial:=0;
  if (Trim(APath)='') or not SysUtils.FileExists(APath) then Exit;
  L:=TStringList.Create;
  try
    try
      L.LoadFromFile(APath);
    except
      Exit;
    end;
    Result.State:=Trim(L.Values['state']);
    if Result.State='' then Exit;
    Result.Units:=StrToIntDef(L.Values['units'],0);
    Result.Completed:=StrToIntDef(L.Values['completed'],0);
    Result.Total:=StrToIntDef(L.Values['total'],0);
    Result.Current:=L.Values['current'];
    Result.Serial:=StrToInt64Def(L.Values['serial'],0);
    Result.Valid:=True;
  finally
    L.Free;
  end;
end;

function AFMReadByteProgress(const APath: string): TAFMTransferByteProgress;
var L: TStringList;
begin
  Result.Valid:=False;
  Result.State:='';
  Result.Direction:='';
  Result.Bytes:=0;
  Result.Total:=0;
  Result.Source:='';
  Result.Target:='';
  Result.Serial:=0;
  if (Trim(APath)='') or not SysUtils.FileExists(APath) then Exit;
  L:=TStringList.Create;
  try
    try
      L.LoadFromFile(APath);
    except
      Exit;
    end;
    Result.State:=Trim(L.Values['state']);
    if Result.State='' then Exit;
    Result.Direction:=Trim(L.Values['direction']);
    Result.Bytes:=StrToInt64Def(L.Values['bytes'],0);
    Result.Total:=StrToInt64Def(L.Values['total'],0);
    Result.Source:=L.Values['source'];
    Result.Target:=L.Values['target'];
    Result.Serial:=StrToInt64Def(L.Values['serial'],0);
    if Result.Bytes<0 then Result.Bytes:=0;
    if Result.Total<0 then Result.Total:=0;
    if (Result.Total>0) and (Result.Bytes>Result.Total) then
      Result.Bytes:=Result.Total;
    Result.Valid:=True;
  finally
    L.Free;
  end;
end;

{ ---- TAFMTransferRequest ------------------------------------------------------ }

constructor TAFMTransferRequest.Create;
begin
  inherited Create;
  FItems:=TStringList.Create;
  FDecisionDestinations:=TStringList.Create;
  Phase:=AFM_PHASE_PLAN;
  Move:=False;
end;

destructor TAFMTransferRequest.Destroy;
begin
  FItems.Free;
  FDecisionDestinations.Free;
  inherited Destroy;
end;

procedure TAFMTransferRequest.AddDecision(const ADestination: string;
  AChoice: TAFMConflictChoice);
begin
  FDecisionDestinations.Add(ADestination);
  SetLength(FDecisionChoices,FDecisionDestinations.Count);
  FDecisionChoices[FDecisionDestinations.Count-1]:=AChoice;
end;

function TAFMTransferRequest.DecisionCount: Integer;
begin
  Result:=FDecisionDestinations.Count;
end;

function TAFMTransferRequest.DecisionDestination(AIndex: Integer): string;
begin
  Result:=FDecisionDestinations[AIndex];
end;

function TAFMTransferRequest.DecisionChoice(AIndex: Integer): TAFMConflictChoice;
begin
  Result:=FDecisionChoices[AIndex];
end;

procedure TAFMTransferRequest.SaveToFile(const APath: string);
var L: TStringList; I: Integer;
begin
  L:=TStringList.Create;
  try
    L.Values['version']:=AFM_TRANSFER_VERSION;
    L.Values['phase']:=Phase;
    if Move then L.Values['operation']:='move' else L.Values['operation']:='copy';
    L.Values['destination']:=Destination;
    L.Values['result']:=ResultPath;
    L.Values['progress']:=ProgressPath;
    L.Values['cancel']:=CancelPath;
    L.Values['pause']:=PausePath;
    L.Values['item.count']:=IntToStr(FItems.Count);
    for I:=0 to FItems.Count-1 do
      L.Values['item.'+IntToStr(I)]:=FItems[I];
    L.Values['decision.count']:=IntToStr(FDecisionDestinations.Count);
    for I:=0 to FDecisionDestinations.Count-1 do
    begin
      L.Values['decision.'+IntToStr(I)+'.destination']:=FDecisionDestinations[I];
      if FDecisionChoices[I]=afccReplace then
        L.Values['decision.'+IntToStr(I)+'.choice']:='replace'
      else
        L.Values['decision.'+IntToStr(I)+'.choice']:='skip';
    end;
    AFMWriteAtomic(APath,L);
  finally
    L.Free;
  end;
end;

procedure TAFMTransferRequest.LoadFromFile(const APath: string);
var L: TStringList; I, N: Integer; S: string;
begin
  FItems.Clear;
  FDecisionDestinations.Clear;
  SetLength(FDecisionChoices,0);
  L:=TStringList.Create;
  try
    L.LoadFromFile(APath);
    { The result path first: with it, every later complaint can be reported
      back instead of being lost. }
    ResultPath:=Trim(L.Values['result']);
    ProgressPath:=Trim(L.Values['progress']);
    CancelPath:=Trim(L.Values['cancel']);
    PausePath:=Trim(L.Values['pause']);
    if L.Values['version']<>AFM_TRANSFER_VERSION then
      raise Exception.Create('the transfer job was written by a different '+
        'AFileManager version (job '+L.Values['version']+', worker '+
        AFM_TRANSFER_VERSION+')');
    Phase:=LowerCase(Trim(L.Values['phase']));
    if (Phase<>AFM_PHASE_PLAN) and (Phase<>AFM_PHASE_RUN) then
      raise Exception.Create('the transfer job has no valid phase');
    Move:=LowerCase(Trim(L.Values['operation']))='move';
    Destination:=L.Values['destination'];
    if Trim(Destination)='' then
      raise Exception.Create('the transfer job has no destination');
    N:=StrToIntDef(L.Values['item.count'],-1);
    if N<1 then raise Exception.Create('the transfer job has no items');
    for I:=0 to N-1 do
    begin
      S:=L.Values['item.'+IntToStr(I)];
      if Trim(S)='' then
        raise Exception.Create('the transfer job contains an empty item');
      FItems.Add(S);
    end;
    N:=StrToIntDef(L.Values['decision.count'],0);
    for I:=0 to N-1 do
    begin
      S:=L.Values['decision.'+IntToStr(I)+'.destination'];
      if Trim(S)='' then Continue;
      if LowerCase(Trim(L.Values['decision.'+IntToStr(I)+'.choice']))='replace' then
        AddDecision(S,afccReplace)
      else
        AddDecision(S,afccSkip);
    end;
  finally
    L.Free;
  end;
end;

{ ---- TAFMTransferReport --------------------------------------------------- }

constructor TAFMTransferReport.Create;
begin
  inherited Create;
  FErrors:=TStringList.Create;
  Clear;
end;

destructor TAFMTransferReport.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

procedure TAFMTransferReport.Clear;
begin
  State:='';
  Completed:=0; Skipped:=0; Failed:=0; Units:=0;
  MovedAsCopy:=False;
  Message:='';
  FConflictCount:=0;
  SetLength(FConflicts,0);
  FErrors.Clear;
end;

function TAFMTransferReport.GetConflict(AIndex: Integer): TAFMConflict;
begin
  Result:=FConflicts[AIndex];
end;

procedure TAFMTransferReport.AddConflict(const AConflict: TAFMConflict);
begin
  if FConflictCount>=Length(FConflicts) then
    SetLength(FConflicts,FConflictCount+16);
  FConflicts[FConflictCount]:=AConflict;
  Inc(FConflictCount);
end;

function TAFMTransferReport.Finished: Boolean;
begin
  Result:=(State=AFM_STATE_OK) or (State=AFM_STATE_PARTIAL) or
    (State=AFM_STATE_CANCELLED) or (State=AFM_STATE_ERROR);
end;

procedure SaveSide(L: TStrings; const AKey: string; const ASide: TAFMConflictSide);
begin
  if not ASide.Known then begin L.Values[AKey+'.known']:='0'; Exit; end;
  L.Values[AKey+'.known']:='1';
  if ASide.IsDirectory then L.Values[AKey+'.kind']:='D' else L.Values[AKey+'.kind']:='F';
  L.Values[AKey+'.size']:=IntToStr(ASide.Size);
  L.Values[AKey+'.modified']:=ASide.Modified;
end;

procedure LoadSide(L: TStrings; const AKey: string; out ASide: TAFMConflictSide);
begin
  ASide.Known:=L.Values[AKey+'.known']='1';
  ASide.IsDirectory:=L.Values[AKey+'.kind']='D';
  ASide.Size:=StrToInt64Def(L.Values[AKey+'.size'],0);
  ASide.Modified:=L.Values[AKey+'.modified'];
end;

procedure TAFMTransferReport.SaveToFile(const APath: string);
var L: TStringList; I: Integer; K: string;
begin
  L:=TStringList.Create;
  try
    L.Values['version']:=AFM_TRANSFER_VERSION;
    L.Values['state']:=State;
    L.Values['completed']:=IntToStr(Completed);
    L.Values['skipped']:=IntToStr(Skipped);
    L.Values['failed']:=IntToStr(Failed);
    L.Values['units']:=IntToStr(Units);
    if MovedAsCopy then L.Values['moved-as-copy']:='1';
    L.Values['message']:=OneLine(Message);
    L.Values['conflict.count']:=IntToStr(FConflictCount);
    for I:=0 to FConflictCount-1 do
    begin
      K:='conflict.'+IntToStr(I);
      L.Values[K+'.source']:=FConflicts[I].Source;
      L.Values[K+'.destination']:=FConflicts[I].Destination;
      SaveSide(L,K+'.incoming',FConflicts[I].Incoming);
      SaveSide(L,K+'.existing',FConflicts[I].Existing);
    end;
    L.Values['error.count']:=IntToStr(FErrors.Count);
    for I:=0 to FErrors.Count-1 do
      L.Values['error.'+IntToStr(I)]:=OneLine(FErrors[I]);
    AFMWriteAtomic(APath,L);
  finally
    L.Free;
  end;
end;

function TAFMTransferReport.LoadFromFile(const APath: string): Boolean;
var L: TStringList; I, N: Integer; K: string; C: TAFMConflict;
begin
  Result:=False;
  Clear;
  if (Trim(APath)='') or not SysUtils.FileExists(APath) then Exit;
  L:=TStringList.Create;
  try
    try
      L.LoadFromFile(APath);
    except
      Exit;   { being replaced right now; the caller polls again }
    end;
    State:=LowerCase(Trim(L.Values['state']));
    if State='' then Exit;
    Completed:=StrToIntDef(L.Values['completed'],0);
    Skipped:=StrToIntDef(L.Values['skipped'],0);
    Failed:=StrToIntDef(L.Values['failed'],0);
    Units:=StrToIntDef(L.Values['units'],0);
    MovedAsCopy:=L.Values['moved-as-copy']='1';
    Message:=L.Values['message'];
    N:=StrToIntDef(L.Values['conflict.count'],0);
    for I:=0 to N-1 do
    begin
      K:='conflict.'+IntToStr(I);
      C.Source:=L.Values[K+'.source'];
      C.Destination:=L.Values[K+'.destination'];
      LoadSide(L,K+'.incoming',C.Incoming);
      LoadSide(L,K+'.existing',C.Existing);
      if (C.Source<>'') and (C.Destination<>'') then AddConflict(C);
    end;
    N:=StrToIntDef(L.Values['error.count'],0);
    for I:=0 to N-1 do
      FErrors.Add(L.Values['error.'+IntToStr(I)]);
    Result:=True;
  finally
    L.Free;
  end;
end;

end.
