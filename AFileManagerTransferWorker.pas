// Copyright (c) 2026 DaniloS
// MPL-2.0
program AFileManagerTransferWorker;

{ Detached provider/resource transfer worker.

  This is deliberately a REAL executable, not a Pascal routine entered through
  CreateNewProc/NP_Entry. AmigaDOS Run creates a normal Process and the FPC
  startup code initializes a separate runtime/stack before any AROSA service
  code executes. Blocking LIST/STAT/AGet/APut work therefore cannot occupy the
  AFileManager Intuition task. }

{$MODE OBJFPC}{$H+}

uses
  Classes, SysUtils,
  Arosa.ObjectModel, Arosa.Version,
  Arosa.Platform.Api, Arosa.Platform.Registry,
  {$IFDEF AROS}Arosa.Platform.Aros.Application,{$ELSE}Arosa.Platform.Null.Application,{$ENDIF}
  Arosa.Services.System, Arosa.Services.Shell, Arosa.Services.Locations,
  Arosa.Services.Content, Arosa.Services.ResourceAccess,
  Arosa.Services.LocationResourceAccess, Arosa.Services.ResourceOperations,
  Arosa.Services.DataTransfer;

type
  TTransferCallbacks = class
  private
    FErrors: TStringList;
    FConflicts: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function ErrorDecision(const AOperation, ASource, ADestination,
      AMessage: string): TArosaOperationErrorDecision;
    function ConflictDecision(const ASource, ADestination: string;
      ASourceIsDirectory, ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
    function Summary: string;
    property ErrorCount: Integer read FConflicts; { compatibility not used }
    property Errors: TStringList read FErrors;
    property ConflictCount: Integer read FConflicts;
  end;

constructor TTransferCallbacks.Create;
begin
  inherited Create;
  FErrors:=TStringList.Create;
  FConflicts:=0;
end;

destructor TTransferCallbacks.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

function TTransferCallbacks.ErrorDecision(const AOperation, ASource,
  ADestination, AMessage: string): TArosaOperationErrorDecision;
begin
  FErrors.Add(AOperation+': '+ASource+' -> '+ADestination+' - '+AMessage);
  Result:=aoedSkip;
end;

function TTransferCallbacks.ConflictDecision(const ASource,
  ADestination: string; ASourceIsDirectory,
  ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
begin
  Inc(FConflicts);
  FErrors.Add('conflict skipped: '+ASource+' -> '+ADestination);
  Result:=arcdSkip;
  if ASourceIsDirectory and ADestinationIsDirectory then ;
end;

function TTransferCallbacks.Summary: string;
begin
  if FErrors.Count=0 then Exit('completed');
  Result:=FErrors[0];
  if FErrors.Count>1 then Result:=Result+' (+'+IntToStr(FErrors.Count-1)+' more)';
end;

procedure WriteResultAtomic(const APath, AState: string; ACompleted: Integer;
  const AMessage: string);
var R: TStringList; Tmp: string;
begin
  if Trim(APath)='' then Exit;
  Tmp:=APath+'.tmp';
  R:=TStringList.Create;
  try
    R.Values['state']:=AState;
    R.Values['completed']:=IntToStr(ACompleted);
    R.Values['message']:=StringReplace(StringReplace(AMessage,#13,' ',[rfReplaceAll]),#10,' ',[rfReplaceAll]);
    SysUtils.DeleteFile(Tmp);
    R.SaveToFile(Tmp);
    SysUtils.DeleteFile(APath);
    if not SysUtils.RenameFile(Tmp,APath) then
    begin
      { Last-resort publication. The parent only reads after FileExists and
        never retries synchronously inside an input callback. }
      R.SaveToFile(APath);
      SysUtils.DeleteFile(Tmp);
    end;
  finally
    R.Free;
  end;
end;

procedure RunWorker(var APlatform: IArosaPlatform; const AJobPath: string);
var
  Job, Items: TStringList;
  Paths: TArosaPathService;
  Files: TArosaFileService;
  Locations: TArosaLocationService;
  Shell: TArosaShellService;
  Content: TArosaContentService;
  Access: TArosaLocationResourceAccess;
  Ops: TArosaResourceOperationService;
  Callbacks: TTransferCallbacks;
  I, Count, Completed: Integer;
  Destination, ResultPath, OpText, State, MessageText: string;
  Operation: TArosaTransferOperation;
  Ok: Boolean;
begin
  Job:=TStringList.Create;
  Items:=TStringList.Create;
  Paths:=nil; Files:=nil; Locations:=nil; Shell:=nil; Content:=nil;
  Access:=nil; Callbacks:=nil;
  ResultPath:=''; Completed:=0;
  try
    Job.LoadFromFile(AJobPath);
    ResultPath:=Trim(Job.Values['result']);
    if Job.Values['version']<>'1' then
      raise Exception.Create('unsupported transfer job version');
    Destination:=Job.Values['destination'];
    if Trim(Destination)='' then
      raise Exception.Create('destination is empty');
    OpText:=LowerCase(Trim(Job.Values['operation']));
    if OpText='move' then Operation:=atoMove else Operation:=atoCopy;
    Count:=StrToIntDef(Job.Values['item.count'],-1);
    if Count<1 then raise Exception.Create('transfer job has no items');
    for I:=0 to Count-1 do
    begin
      if Trim(Job.Values['item.'+IntToStr(I)])='' then
        raise Exception.Create('transfer job contains an empty item');
      Items.Add(Job.Values['item.'+IntToStr(I)]);
    end;

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
      IntToHex(PtrUInt(@Job),SizeOf(Pointer)*2),APlatform,Paths,Files);
    Locations.RegisterProvider(TArosaATransferLocationProvider.CreateProvider(Shell,Paths));
    Content:=TArosaContentService.CreateForLocations(Locations,Paths,Files);
    Access:=TArosaLocationResourceAccess.CreateForLocations(Locations,Content,Paths,Files);
    Ops:=Shell.Operations;
    Ops.ResourceAccess:=Access;

    Callbacks:=TTransferCallbacks.Create;
    Ops.OnError:=@Callbacks.ErrorDecision;
    Ops.OnConflict:=@Callbacks.ConflictDecision;

    Ok:=Ops.Transfer(Items,Destination,Operation,Completed);
    Ok:=Ok and (Completed=Items.Count) and (Callbacks.Errors.Count=0);
    if Ok then
    begin
      State:='ok';
      MessageText:='completed';
    end
    else
    begin
      State:='error';
      MessageText:=Callbacks.Summary;
      if (MessageText='completed') and (Completed<Items.Count) then
        MessageText:='not every requested resource was transferred';
    end;
    WriteResultAtomic(ResultPath,State,Completed,MessageText);
  except
    on E: Exception do
      WriteResultAtomic(ResultPath,'error',Completed,E.Message);
  end;

  { Destroy in dependency order while the platform interface is alive. }
  Callbacks.Free;
  if Shell<>nil then Shell.Operations.ResourceAccess:=nil;
  Access.Free;
  Content.Free;
  Shell.Free;
  Locations.Free;
  Files.Free;
  Paths.Free;
  Items.Free;
  Job.Free;
end;

var Platform: IArosaPlatform;
begin
  Platform:=nil;
  if ParamCount<>1 then Halt(5);
  try
    RunWorker(Platform,ParamStr(1));
  finally
    ArosaDestroyPlatform(Platform);
  end;
end.
