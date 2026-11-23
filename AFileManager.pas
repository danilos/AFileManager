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


program AFileManager;

{ AROSA 0.5.97.00 - Structured list columns and typed preview foundation.-composed locations and draggable splitters.

  Uses existing AROSA controls and services:
    * assignment catalogue
    * dual highlighted file views
    * Windows/Linux-style path navigation, Up and Refresh
    * multiselect
    * copy from active view to the other view
    * delete and execute script
    * menu, toolbar and operation surfaces built as tab controls

  UI code consumes AROSA shell/path/file services; resource activation, process
  execution, localization, DataTypes and sound are provided by AROSA rather than
  reimplemented by AFileManager. It does not call native DOS APIs directly. }

{$MODE OBJFPC}{$H+}

{ 0.8.6.3: an HTML page is laid out and painted by procedures that call
  themselves for every level of the page, at the end of the long chain of
  calls that paints the window; pictures and fonts are opened by system
  libraries from in there.  The 256 KB a program gets on i386 AROS by
  default leave little room for that, and a stack that overflows on AROS is
  not reported - it overwrites memory.  (ABrowser has had 1 MB since
  0.8.6.2.)

  0.8.29.1: 4 MB.  The Free Pascal start-up code allocates this stack
  with AllocVec and frees it with FreeVec after the program has ended
  (rtl/aros/si_prc.pp).  Growing past its bottom overwrites the AllocVec
  header, which surfaces only in that last FreeVec as "Program failed -
  Memory header not located" in the Shell task, after the log has stopped.
  Arosa.Platform.Aros.StackProbe measures the use and the shutdown log
  reports it (stack-used=...). }
{$IFDEF AROS}{$M 4194304,0}{$ENDIF}

{ Transfers that touch a remote location run in a detached worker process on
  AROS.  The symbol can also be given on the command line of a host build
  (-dAFM_EXTERNAL_TRANSFER) to compile that path where it cannot run. }
{$IFDEF AROS}{$DEFINE AFM_EXTERNAL_TRANSFER}{$ENDIF}

uses
  Arosa.Instrumentation.AFileManager,
  Classes, SysUtils,
  { 0.8.27.10: first, so the RTL's implicit Ctrl-C Halt is off before any
    other unit runs (see Arosa.Platform.Aros.Process) }
  Arosa.Platform.Aros.Process, Arosa.Platform.Aros.MonotonicClock,
  Arosa.Platform.Aros.Screens,
  Arosa.Platform.Aros.StackProbe,
  Arosa.Platform.Aros.ApplicationEndpoint,
  Arosa.ObjectModel, Arosa.Version, Arosa.Messages.Contracts, Arosa.Services.Diagnostics, Arosa.DebugTrace, Arosa.Geometry, Arosa.Graphics,
  Arosa.Lifecycle,
  Arosa.Platform.Api, Arosa.Platform.Registry,
  Arosa.Platform.Aros.FileEnumerationWorker,
  {$IFDEF AROS}
  Arosa.Platform.Aros.Application, Arosa.Platform.Aros.ExecTasks,
  {$ELSE}
  Arosa.Platform.Null.Application,
  {$ENDIF}
  Arosa.Services.System, Arosa.Services.Shortcuts, Arosa.Services.Worker, Arosa.Platform.Aros.Worker, Arosa.Services.Locations, Arosa.Services.LocationChanges, Arosa.Services.VirtualLocations, Arosa.Services.Workspaces, Arosa.Services.WorkspaceStatus, Arosa.Services.Registry, Arosa.Services.Persistence, Arosa.Services.WorkspaceModules, Arosa.Services.Content, Arosa.Services.ResourceAccess, Arosa.Services.LocationResourceAccess, Arosa.Services.History, Arosa.Services.Resources, Arosa.Services.ResourceKnowledge, Arosa.Services.ResourceState, Arosa.Services.Session.Client,
  Arosa.Services.Clipboard, Arosa.Services.ResourceOperations, Arosa.Services.DataTransfer,
  Arosa.Services.ResourceSearch, Arosa.Services.Trash, Arosa.Services.Shell,
  Arosa.Services.Macro, Arosa.Services.ARexx,
  Arosa.Services.DataTypes, Arosa.Services.DataTypeMetadata,
  Arosa.Services.FontMetadata, Arosa.Services.Presentation.Font,
  Arosa.Services.SVGMetadata,
  Arosa.Services.Presentation, Arosa.Services.Presentation.Probe, Arosa.Services.Presentation.AmigaGuide,
  Arosa.UI.HtmlView, Arosa.Services.Presentation.Html, Arosa.Services.Presentation.Image,
  Arosa.Services.Presentation.Archive, Arosa.UI.Breadcrumbs,
  Arosa.Services.ArchiveVerification, Arosa.Services.ArchiveListing, Arosa.UI.Bubbles, Arosa.UI.ThemeLayers,
  Arosa.Services.ServiceSettings, Arosa.Services.ShellSession, Arosa.UI.CommandBar,
  Arosa.Services.Sound, Arosa.Services.AudioProbe, Arosa.Services.Localization, Arosa.Services.Fonts, Arosa.Services.Archive, Arosa.UI.MusicBars,
  {$IFDEF AROS}Arosa.Platform.Aros.Fonts,{$ENDIF}
  { 0.8.23: SVG text, masks, clip paths, patterns, blur (beside NanoSVG) }
  {$IFDEF AROS}Arosa.Platform.VectorGraphics.ThorVG,{$ENDIF}
  { 0.8.24: Unicode text in the system's outline fonts (FONTS:) }
  {$IFDEF AROS}Arosa.Platform.WebFont.FreeType, Arosa.Services.SystemOutlineFonts,{$ENDIF}
  Arosa.UI.Commands, Arosa.UI.Console, Arosa.UI.ApplicationFrames, Arosa.UI.ContentConsumers, Arosa.UI.Desktop, Arosa.UI.WorkspaceShell,
  Arosa.Services.Environment,
  Arosa.Services.ExecutionPlacement, Arosa.Services.ProcessorTelemetry,
  Arosa.Services.CompositionTelemetry,
  {$IFDEF AROS}Arosa.Platform.Aros.ExecutionPlacement, Arosa.Platform.Aros.ProcessorTelemetry,{$ENDIF}
  Arosa.Services.ApplicationFrames,
  Arosa.Services.Images.Contracts, Arosa.Services.Images,
  Arosa.UI.Visual, Arosa.UI.Layout, Arosa.UI.Controls, Arosa.UI.Metadata, Arosa.UI.Theme,
  Arosa.UI.Forms, Arosa.UI.FormHost, Arosa.UI.Dialogs, Arosa.UI.FileDialog, Arosa.UI.PermissionDialog,
  Arosa.Services.Permissions, Arosa.UI.NetworkLocationDialog, Arosa.UI.LocationPicker, Arosa.UI.WindowDescriptors,
  Arosa.UI.WindowCapabilities, AFileManager.Context, AFileManager.CommandHistory,
  AFileManager.Dialogs, AFileManager.Help, AFileManager.TransferProtocol,
  AFileManager.TransferWorker, AFileManager.Launch, AFileManager.Settings,
  AFileManager.DropRules;

const
  { TArosaListRow.UserFlags of a file-pane row }
  AFM_ROW_FOLDER = 1;
  AFM_ROW_FILE   = 2;
  AFM_ROW_REMOTE = 4;

  { Targeted diagnostics for spatial file-operation planning.  Keep this
    separate from the root AFileManager source so drag/drop can be traced
    without enabling TRACE for the whole application. }
  AFM_DIAG_DRAGDROP = 'arosa.application.afilemanager.dragdrop';

type
  TFileManagerTabPage = class(TArosaTabPage)
  public
    constructor CreateStyled(ATheme: TArosaTheme; const ACaption: string);
  end;

  { Console application-frame adapter.  The File Manager still owns the shell
    session semantics, while the Application Frame Service owns the visual
    application session/surface and can move that live surface between an
    embedded frame and a floating AROSA window without recreating it. }
  TAFileManagerConsoleFrameSession = class(TArosaApplicationSession)
  private
    FConsole: TArosaCommandConsole;
    FTitle: string;
  protected
    function CreateSurfaceCore: TArosaApplicationSurface; override;
  public
    constructor CreateForConsole(const ASessionId, ATitle: string;
      AConsole: TArosaCommandConsole);
  end;

  { Shared AROSA editor document model; the AIDEa port uses the same
    TArosaTabControl/TArosaEditor pair, without depending on SynEdit. }
  TAFileManagerDocument = class
    Path: string;
    OriginalText: string;
    Editor: TArosaEditor;
    { 0.7.63: editable documents are a two-surface composition. }
    RenditionSplit: TArosaSplitterHost;
    RenditionHost: TArosaColumnPanel;
    RenditionText: TArosaEditor;
    RenditionPresentation: TArosaPresentation;
    RenditionVisible: Boolean;
    Page: TArosaTabPage;
    Toolbar: TArosaRowPanel;
    SaveButton, CloseButton, FindButton, ReplaceButton, GoToLineButton,
      RenditionButton: TArosaButton;
    TabIndex: Integer;
  end;

  TAFileManagerConsoleDocument = class
    Id: Integer;
    Console: TArosaCommandConsole;
    Session: TArosaShellSession;
    Page: TArosaTabPage;
    CloseButton: TArosaButton;
    TabIndex: Integer;
    FrameSession: TAFileManagerConsoleFrameSession;
    FrameSurface: TArosaApplicationSurface;
    EmbeddedFrame: TArosaEmbeddedApplicationFrame;
    FloatingFrame: TArosaFloatingApplicationFrame;
    FloatingToolbarTabs: TArosaTabControl;
    FloatingOperationTabs: TArosaTabControl;
    { Theme context captured from the owning workspace when the Console is
      detached.  A second workspace may use a different theme; it must never
      repaint this floating frame through shared/global presentation state. }
    FloatingTheme: TArosaTheme;
    { Non-blocking native shell command owned by this console document. }
    ProcessId: PtrUInt;
    ProcessOutputLength: Integer;
    ProcessErrorLength: Integer;
    ProcessStartedAt: QWord;
    ProcessTimeoutMs: Integer;
    ProcessLine: string;
  end;

  TAFileManagerCommandTarget = class;

  { 0.7.13.0.0: one file-manager surface of the secondary view.  With split
    view on, the secondary view hosts any number of surfaces (tabs in the
    surface bar); the visible one owns the live list, the others keep their
    state here. }
  TAFMSurface = class
    Location: string;
    ViewMode: Integer;
    History: TArosaHistoryChain;
    Filter, Search: string;
    Selected: Integer;
  end;

  TAFileManagerController = class;

  TAFileManagerWorkspaceBackground = class(TArosaControl)
  private
    FBitmap: TArosaPlatformHandle;
    FSourceRect: TArosaRect;
    FMode: string;
    FColour1, FColour2, FColour3, FColour4: TArosaColour;
    FDirection: string;
    FLayerOrder: string;
    FOpacity: Integer;
    function InterpolatedColour(APosition, AMaximum: Integer): TArosaColour;
    procedure PaintLayer(ACanvas: TArosaCanvas; const R: TArosaRect);
  protected
    procedure PaintContent(ACanvas: TArosaCanvas); override;
  public
    constructor Create; override;
    property Bitmap: TArosaPlatformHandle read FBitmap write FBitmap;
    property SourceRect: TArosaRect read FSourceRect write FSourceRect;
    property Mode: string read FMode write FMode;
    property Colour1: TArosaColour read FColour1 write FColour1;
    property Colour2: TArosaColour read FColour2 write FColour2;
    property Colour3: TArosaColour read FColour3 write FColour3;
    property Colour4: TArosaColour read FColour4 write FColour4;
    property Direction: string read FDirection write FDirection;
    property LayerOrder: string read FLayerOrder write FLayerOrder;
    property Opacity: Integer read FOpacity write FOpacity;
  end;

  { Compatibility adapter over the shared AROSA workspace shell.  The mature
    taskbar/start-menu implementation was extracted from AFileManager into
    Arosa.UI.WorkspaceShell so every workspace host can reuse it. }
  TAFileManagerTaskbar = class
  private
    FController: TAFileManagerController;
    FShell: TArosaWorkspaceShell;
    procedure ShellLaunch(ASender: TArosaObject; const ATarget: string);
    procedure ShellOpenVolume(ASender: TArosaObject; const ATarget: string);
    procedure ShellDiagnostic(ASender: TArosaObject; const AMessage: string);
    function ShellText(ASender: TArosaObject; const AKey, AFallback: string): string;
  public
    constructor CreateTaskbar(const APlatform: IArosaPlatform;
      AApplication: TArosaApplication; AFonts: TArosaFontCache;
      AController: TAFileManagerController; AScreen: TArosaPlatformHandle;
      const AWorkspaceId, AWorkspaceName: string);
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    function IsOpen: Boolean;
    procedure BringToFront;
    function GetTop: Integer;
    property Top: Integer read GetTop;
    procedure Resync;
    function TestPins: string;
    procedure TestStep(AStep: Integer);
  end;

  TAFileManagerWorkspacePrototype = class
  private
    FPlatform: IArosaPlatform;
    FApplication: TArosaApplication;
    FTheme: TArosaTheme;
    FFonts: TArosaFontCache;
    FWorkspace: TArosaWorkspaceDefinition;
    FScreen: TArosaPlatformHandle;
    FBackgroundForm: TArosaForm;
    FBackgroundHost: TArosaFormHost;
    FBackgroundResource: TArosaImageResource;
    FBackgroundSurface: TAFileManagerWorkspaceBackground;
    FForm: TArosaForm;
    FHost: TArosaFormHost;
    FController: TAFileManagerController;
    FOwnerController: TAFileManagerController;
    FClosePending: Boolean;
    FCloseIdleAttached: Boolean;
    FCloseFinalizeAttached: Boolean;
    procedure CloseRequested;
    procedure CloseIdle(var AMoreWorkPending: Boolean);
    procedure CloseFinalizeIdle(var AMoreWorkPending: Boolean);
  public
    constructor CreateWorkspace(const APlatform: IArosaPlatform;
      AApplication: TArosaApplication; ATheme: TArosaTheme;
      AFonts: TArosaFontCache; AWorkspace: TArosaWorkspaceDefinition;
      AOwnerController: TAFileManagerController);
    destructor Destroy; override;
    function Open: Boolean;
    procedure BringToFront;
    procedure Close;
    function IsOpen: Boolean;
    function WorkspaceId: string;
    function Taskbar: TAFileManagerTaskbar;
    function Controller: TAFileManagerController;
  end;

  TAFMTransferNode = record
    Source: string;
    Destination: string;
    PostDirectory: Boolean;
    TopLevel: Boolean;
    RootSource: string;
  end;

  { 0.7.27.5.3: provider directory transfers are cooperatively stepped from
    the application idle loop on AROS. This avoids running Pascal/AROSA service
    code inside a CreateNewProc entry context while still yielding to Intuition
    between individual resource operations. }
  TAFMTransferJob = class(TArosaWorkerJob)
  private
    FOperations: TArosaResourceOperationService;
    FItems: TStringList;
    FDestination: string;
    FOperation: TArosaTransferOperation;
    FCompletedTopLevel: Integer;
    FProgressUnits: Integer;
    FCancelRequested: Boolean;
    FCancelled: Boolean;
    FSuccessful: Boolean;
    FErrors: TStringList;
    FTopLevelFailed: TStringList;
    FQueue: array of TAFMTransferNode;
    FQueueCount: Integer;
    procedure PushNode(const ASource, ADestination: string;
      APostDirectory, ATopLevel: Boolean; const ARootSource: string);
    procedure MarkRootFailed(const ARootSource: string);
    function RootFailed(const ARootSource: string): Boolean;
    function VerifyDirectoryShape(const ASource,
      ADestination: string): Boolean;
    function PopNode(out ANode: TAFMTransferNode): Boolean;
    function ContinueTransfer: Boolean;
    procedure TransferProgress(const ASource, ADestination: string);
    function TransferError(const AOperation, ASource, ADestination,
      AMessage: string): TArosaOperationErrorDecision;
  protected
    procedure Execute; override;
  public
    constructor CreateTransfer(AOperations: TArosaResourceOperationService;
      AItems: TStrings; const ADestination: string;
      AOperation: TArosaTransferOperation);
    destructor Destroy; override;
    procedure RequestCancel;
    { Process at most one file/directory boundary. True means the job has
      finished (successfully, cancelled, or with collected errors). }
    function Step: Boolean;
    property CompletedTopLevel: Integer read FCompletedTopLevel;
    property ProgressUnits: Integer read FProgressUnits;
    property Cancelled: Boolean read FCancelled;
    property Successful: Boolean read FSuccessful;
    property Errors: TStringList read FErrors;
  end;

  { 0.7.5.10: the "Load preview" command offered for a remote file larger
    than the automatic preview limit (generic command contract, so the
    preview command bar renders it with icon, caption and bubble). }
  TAFMLoadPreviewCommand = class(TArosaObject, IArosaCommandProvider, IArosaCommandTarget)
  private
    FOwner: TAFileManagerController;
    FView: Integer;
  public
    constructor CreateFor(AOwner: TAFileManagerController; AView: Integer);
    function CommandCount: Integer;
    function CommandInfo(AIndex: Integer): TArosaCommandInfo;
    function CanHandleCommand(const ACommandId: TArosaCommandId): Boolean;
    function ExecuteCommand(const ACommandId: TArosaCommandId;
      AContext: TArosaCommandContext): Boolean;
    procedure QueryCommandState(const ACommandId: TArosaCommandId;
      var AEnabled, AVisible, AChecked: Boolean);
  end;

  TAFileManagerController = class(TArosaObject)
  private
    FPlatform: IArosaPlatform;
    FWindowFrame: TArosaWindowFrame;
    FContentConsumer: TArosaContentConsumerFrame;
    FPrimaryContentSurface: TArosaContentSurface;
    FNativeHost: TArosaFormHost;
    FNativeDragStart: TArosaRect;
    FNativeRestoreDragStart: TArosaRect;
    FNativePointerStart: TArosaPoint;
    FNativeDragging: Boolean;
    FNativeDragMoved: Boolean;
    FNativeSnapped: Boolean;
    FNativePendingRestore: Boolean;
    FNativeLastPointer: TArosaPoint;
    FNativeMaximized: Boolean;
    FNativeCollapsed: Boolean;
    FNativeRestoreBounds: TArosaRect;
    FCompactFont: TArosaFont; { application/UI role }
    FFileFont: TArosaFont;    { file-list/path role }
    FPaths: TArosaPathService;
    FFiles: TArosaFileService;
    FLocations: TArosaLocationService;
    FLocationChanges: TArosaLocationChangeService;
    FVirtualLocations: TArosaVirtualLocationProvider;
    FWorkspaces: TArosaWorkspaceService;
    FWorkspacePrototypes: TList;
    FActiveWorkspaceId: string;
    FWorkspaceProfilePath: string;
    FPendingDeleteWorkspaceId: string;
    FPendingEditWorkspaceId: string;
    FWorkspaceSessionMode: Boolean;
    FWorkspaceSessionClose: TArosaHostCloseRequest;
    { Non-owning process-level workspace navigator. Workspace child sessions
      delegate workspace activation to the controller that owns the shared
      workspace prototypes, so selecting an already-open workspace raises its
      existing screen instead of creating another screen/session. }
    FWorkspaceNavigationOwner: TAFileManagerController;
    FWorkspaceStatusSource: string;
    FInstanceId: string;
    FInstanceLogPath: string;
    FInstanceLogStream: TFileStream; { legacy field: kept nil; diagnostics are buffered }
    FInstanceLogPending: TStringList;
    FInstanceLogLastFlush: QWord;
    FContent: TArosaContentService;
    FLocationResourceAccess: TArosaLocationResourceAccess;
    FPendingPreviewPath: array[0..1] of string;
    FPendingPreviewTick: array[0..1] of QWord;
    FPendingPreviewActive: array[0..1] of Boolean;
    FDisplayedPreviewPath: array[0..1] of string;
    { 0.7.36.4.0.0: directory activation must not rebuild the list from
      inside the list control's activation callback.  On AROS this can leave
      the control/event path wedged after a remote directory has successfully
      enumerated.  Queue the navigation and perform it from idle instead. }
    FPendingNavigateActive: Boolean;
    FPendingNavigateView: Integer;
    FPendingNavigatePath: string;
    { Application/module launches must not run synchronously from a retained
      list input callback. Queue them to idle just like navigation. }
    FPendingExecLaunch: Boolean;
    FPendingExecTarget: string;
    FPendingExecWorkspace: string;
    FLastExecLaunchTarget: string;
    FLastExecLaunchTick: QWord;
    FForm: TArosaForm;
    FTheme: TArosaTheme;
    FDarkTheme: TArosaTheme;
    FLightTheme: TArosaTheme;
    { 0.7.5.2 layered theme: application layers first, shared AROSA last }
    FThemeLayers: TArosaThemeLayers;
    { 0.7.5.10 remote preview size governance }
    FForcePreviewLocation: array[0..1] of string;
    FLoadPreviewCmd: array[0..1] of TAFMLoadPreviewCommand;
    { 0.7.5.3 icon cache: spec -> TArosaImageResource (nil = known miss) }
    FIconCache: TStringList;
    { 0.7.36.5: per-pane picture rendition cache. Same-location refresh
      reuses decoded resources; navigating a pane releases that pane's cache. }
    FThumbnailCache: array[0..1] of TStringList;
    FThumbnailCacheLocation: array[0..1] of string;
    FFonts: TArosaFontCache;
    FAssignments: TArosaFilteredTreeView;
    FViewsHost: TArosaView;
    FDocumentTabs: TArosaTabControl;
    { Document-tab context belongs to the inner Files/editor/Console host, not
      the outer ContentConsumer surface tab. Store the live page object so a
      close action cannot drift to a different index after tab mutations. }
    FDocumentTabMenu: TArosaContentTabPopup;
    FDocumentTabMenuPage: TArosaTabPage;
    FDocumentTabCloseButton: TArosaButton;
    FDocuments: TList;
    FSaveChangesDialog: TArosaSaveChangesDialog;
    FPendingCloseDocument: TAFileManagerDocument;
    FDeferredCloseDocument: TAFileManagerDocument;
    FClosingApplication: Boolean;
    FPlacesPanel: TArosaColumnPanel;
    FPlacesSplit, FDualViewSplit: TArosaSplitterHost;
    FPlacesDetailSplit: TArosaSplitterHost;
    FPlacesDetailTabs: TArosaTabControl;
    FPlacesMetadata: TArosaMetadataView;
    FPlacesDetailVisible: Boolean;
    FPlacesActive: Boolean;
    FPlacesDetailPercent: Integer;
    FLeftColumn, FRightColumn: TArosaColumnPanel;
    FLeftBrowserColumn, FRightBrowserColumn: TArosaColumnPanel;
    FLeftPreviewSplit, FRightPreviewSplit: TArosaSplitterHost;
    FLeftPreviewPlacementApplied, FRightPreviewPlacementApplied: Integer;
    FLeftTitle, FRightTitle: TArosaLabel;
    FLeftPreviewTitle, FRightPreviewTitle: TArosaLabel;
    FNavigationTitleBar: TArosaRowPanel;
    FLeftPreview, FRightPreview: TArosaEditor;
    FLeftPreviewHost, FRightPreviewHost: TArosaColumnPanel;
    FLeftImagePreview, FRightImagePreview: TArosaImageBox;
    { 0.6.1.4: generic command bar per preview pane, bound to whatever the
      pane shows (a presentation, or the image viewer). }
    FLeftCommandBar, FRightCommandBar: TArosaCommandBar;
    { 0.6.1.6 test hook (environment only, inert otherwise) }
    FTestCloseAfterMs, FTestStartTick, FTestReportTick: QWord;
    FTestPreviewDone: Boolean;
    FTestConsoleDone: Boolean;
    FTestMenuStep: Integer;
    FTestBarStep: Integer;
    FTestModStep: Integer;
    FTestModTick: QWord;
    FTestMenuTick: QWord;
    FApplicationCloseQueued: Boolean;
    FDeferredCloseConsole: TAFileManagerConsoleDocument;
    FConsoleCloseIdleAttached: Boolean;
    FConsoleExecutionIdleAttached: Boolean;
    FApplicationCloseIdleAttached: Boolean;
    FEndpointIdleAttached: Boolean;
    FEndpointQuitRequested: Boolean;
    FLeftImageResource, FRightImageResource: TArosaImageResource;
    FImageLoader: TArosaImageLoaderService;
    FImageTransforms: TArosaImageTransformService;
    FResources: TArosaResourceService;
    FPresentationService: TArosaPresentationService;
    FLeftPresentation, FRightPresentation: TArosaPresentation;
    FMetadataView: TArosaMetadataView;
    FRightMetadataView: TArosaMetadataView;
    FMetadataPage: TArosaTabPage;
    FPreviewPage: TArosaTabPage;
    FRightPreviewPage: TArosaTabPage;
    FRightMetadataPage: TArosaTabPage;
    FMetadataTabs: TArosaTabControl;
    FRightMetadataTabs: TArosaTabControl;
    FLeftPath, FRightPath: TArosaTextBox;
    { 0.5.110.55 (R22): navigable breadcrumbs shown instead of the path box;
      the box appears for typing a path and for name prompts. }
    FLeftCrumbs, FRightCrumbs: TArosaBreadcrumbBar;
    FLeftFilter, FRightFilter, FPlacesFilter: TArosaTextBox;
    FLeftSearch, FRightSearch: TArosaTextBox;
    FLeftClearFilter, FRightClearFilter, FLeftClearSearch, FRightClearSearch: TArosaButton;
    FLeftColumns, FRightColumns: TArosaRowPanel;
    FPreviewMenuButton: TArosaButton;
    FMenuMode: Integer;
    FLeftList, FRightList: TArosaFilteredListView;
    FLeftCurrent, FRightCurrent: string;
    FActiveView: Integer;
    FStatus: TArosaLabel;
    FStatusRow: TArosaRowPanel;
    FTransferCancelButton: TArosaButton;
    FTransferProgressDialog: TArosaProgressDialog;
    FWorkerService: TArosaWorkerService;
    FTaskRunner: TArosaArosTaskRunner;
    { 0.17.14: local filesystem enumeration runs in a DOS-only native worker. }
    FEnumerationWorkerActive: Boolean;
    FEnumerationWorkerIdleAttached: Boolean;
    FEnumerationWorkerView: Integer;
    FEnumerationWorkerPath: string;
    FEnumerationWorkerSyncOther: Boolean;
    FEnumerationWorkerGeneration: LongInt;
    FEnumerationWorkerTargetCPU: LongInt;
    FEnumerationPending: Boolean;
    FEnumerationPendingView: Integer;
    FEnumerationPendingPath: string;
    FEnumerationPendingSyncOther: Boolean;
    FTransferJob: TAFMTransferJob;
    FTransferLastProgress: Integer;
    FTransferIdleAttached: Boolean;
    FExternalTransferActive: Boolean;
    FExternalTransferJobPath: string;
    FExternalTransferResultPath: string;
    FExternalTransferStartedTick: QWord;
    { 0.8.6.1: the worker plans first (phase "plan"), the user decides the
      conflicts, then a second worker runs with the answers. }
    FExternalTransferPhase: string;
    FExternalTransferProgressPath: string;
    FExternalTransferCancelPath: string;
    FExternalTransferPausePath: string;
    FExternalTransferSawWorker: Boolean;
    FExternalTransferSerial: Int64;
    FExternalTransferByteSerial: Int64;
    FExternalTransferDisplayedCompleted: Integer;
    FExternalTransferChangeTick: QWord;
    FExternalTransferPollTick: QWord;
    FExternalTransferCancelAsked: Boolean;
    FExternalTransferPaused: Boolean;
    FMenuPanel: TArosaRowPanel;
    FMenuRootPanel, FMenuSubPanel: TArosaColumnPanel;
    FToolbarTabs, FOperationTabs: TArosaTabControl;
    FActiveEnvironment: string;
    FConsoleOperationsPage: TArosaTabPage;
    FConsoleOperationsIndex: Integer;
    FUndoKind: string;
    FUndoSources: TStringList;
    FUndoDestinations: TStringList;
    FTrashDirectory: string;
    FRecentLocations, FRecentFiles: TStringList;
    { 0.5.110.16 favourites: user-editable Name=Path list, persisted in
      AFileManager.favorites next to the history file. Seeded once from the
      descriptor's [Locations.Favorites] section. }
    FFavorites: TStringList;
    FFavoritesPath: string;
    { 0.8.31: history, favourites, network locations and layout are
      documents of the Resource Service's state worker }
    FStateDocuments: TArosaStateDocuments;
    FShortcutService: TArosaShortcutService;
    FLauncherService: TArosaWorkspaceLauncherService;
    FStartMenuService: TArosaShortcutService;
    { 0.8.6.6 }
    FSeenMembershipGeneration: Integer;
    FWorkspaceScreenName: string;   { public name of the screen of this workspace }
    FLastModuleListing: string;
    FVolumesFailed: Boolean;
    { 0.8.6.5 }
    FTaskbar: TAFileManagerTaskbar;
    FTaskbarTried: Boolean;
    FVolumes: TStringList;          { mounted volumes, 'Name:' }
    FVolumesKnown: Boolean;
    FVolumeNotices: TStringList;    { arrived since the start, not yet opened }
    FVolumePollTick: QWord;
    FNetworkLocations: TStringList;
    FNetworkLocationsPath: string;
    FNetworkDialog: TArosaNetworkLocationDialog;
    FEditingNetworkLocation: string;
    FListMenuBase: TStringList;     { composed, localized [ContextMenu] }
    FShortcutBindings: TStringList; { active Key=Command shortcut map }
    FListFavoriteTarget: string;    { location the open list menu acts on }
    FPlaceIconResources: TList;
    FToolbarIconResources: TList;
    FHistoryPath: string;
    FLayoutPath: string;
    FShellService: TArosaShellService;
    FDataTypes: TArosaDataTypeService;
    FSoundService: TArosaSoundService;
    FMusicBars: TArosaMusicBars;
    FRightMusicBars: TArosaMusicBars;
    FLeftAudioHost, FRightAudioHost: TArosaColumnPanel;
    FLeftAudioSummary, FRightAudioSummary: TArosaLabel;
    FLeftAudioPlayback, FRightAudioPlayback: TArosaLabel;
    FLeftAudioTransport, FRightAudioTransport: TArosaRowPanel;
    FLeftAudioProgress, FRightAudioProgress: TArosaProgressBar;
    FCurrentSound: TArosaSound;
    FAudioPath: string;
    FAudioDurationMS: Int64;
    FAudioBasePositionMS: Int64;
    FAudioRunTick: QWord;
    FAudioLastTelemetryTick: QWord;
    FAudioPreviewView: Integer;
    FShowHiddenFiles: Boolean;
    { 0.7.11.0.0: file-view icon geometry is configuration-driven.  The same
      values govern both file panes; row height is derived from the configured
      icon box and current theme font metrics rather than hard-coded. }
    FFileIconSize, FFileRowPadding, FFileIconTextGap: Integer;
    FLeftViewMode, FRightViewMode: Integer; { 0=list, 1=details, 2=icons, 3=Amiga Windows }
    FCommandService: TArosaCommandService;
    FCommandTarget: TAFileManagerCommandTarget;
    FMacroService: TArosaMacroService;
    FARexxService: TArosaARexxService;
    { 0.7.8.0.0: each console document owns its console surface and shell
      session. FConsole/FShellSession remain aliases to the most recently
      activated console for diagnostics/backward-compatible test hooks. }
    FConsole: TArosaCommandConsole;
    FShellSession: TArosaShellSession;
    FConsoles: TList;
    FApplicationFrames: TArosaApplicationFrameService;
    FHistoryService: TArosaHistoryService;
    FLeftNavigationHistory, FRightNavigationHistory: TArosaHistoryChain;
    { 0.7.13.0.0 file-manager surfaces of the secondary view }
    FSurfaces: TList;
    FActiveSurface: Integer;
    FSurfaceBar: TArosaRowPanel;
    FSurfaceCounter: Integer;
    FOperationHistory: TArosaReversibleHistoryChain;
    FResourceClipboard: TArosaResourceClipboard;
    FEditingPath: string;
    FEditingOriginal: string;
    FEditingView: Integer;
    FResourceOperations: TArosaResourceOperationService;
    FSearchService: TArosaResourceSearchService;
    FCommandHistory: TAFileManagerCommandHistory;
    FPendingInputKind: string;
    FPendingInputSource: string;
    FPendingInputView: Integer;
    FDeleteConfirmationPending: Boolean;
    FPendingEmptyTrash: Boolean;
    FPendingPermanentTrashDelete: Boolean;
    FPendingTrashRestore: Boolean;
    FSynchronizingLocationRefresh: Boolean;
    FConfirmDeletion: Boolean;
    FShowThumbnails: Boolean;
    FThumbnailSize: Integer;
    FColumnOrder: TStringList;
    FVisibleColumns: TStringList;
    FDefaultSortColumn: string;
    FDefaultSortAscending: Boolean;
    FActiveThemeId: string;
    FActiveThemePackageId: string;
    FActiveLanguageSpec: string;
    FConfigurationDialog: TAFileManagerConfigurationDialog;
    FConfigurationDialogNeedsRebuild: Boolean;
    FHasFontConfigurationOverride: Boolean;
    FFontConfigurationOverride: TAFMConfigurationSettings;
    FNameDialog: TAFileManagerNameDialog;
    FWorkspacePropertiesDialog: TAFileManagerWorkspacePropertiesDialog;
    FWorkspaceRegistry: TArosaRegistry;
    FWorkspaceRegistryPersistence: TArosaPersistence;
    FWorkspaceModules: TArosaWorkspaceModuleService;
    FWorkspaceModulesDialog: TAFileManagerWorkspaceModulesDialog;
    FWorkspaceRegistryPath: string;
    FBackgroundFileDialog: TAFileManagerOpenFileDialog;
    FInfoDialog: TAFileManagerInfoDialog;
    FHelpSystem: TAFileManagerHelpSystem;
    FDeleteDialog: TArosaConfirmationDialog;
    FInformationDialog: TArosaInformationDialog;
    FPermissionService: TArosaPermissionService;
    FPermissionDialog: TArosaPermissionDialog;
    FArchiveDialog: TArosaArchiveCreateDialog;
    FLocationPicker: TArosaLocationPicker;
    { 0.7.31.0.0.0: shared destination picker for archive and Move To. }
    FLocationPickerPurpose: string;     { '' | 'archive' | 'move-to' }
    FMoveToItems: TStringList;
    FMoveToView: Integer;
    FArchiveOverwriteDialog: TArosaConfirmationDialog;
    FArchiveOverwriteApproved: Boolean;
    { 0.5.110.58 overwrite safety: a copy/move/paste is planned first; each
      conflict is decided in the non-blocking requester; then the operation
      runs with the decisions preset in the Resource Operation Service. }
    FOperationRequester: TArosaOperationRequester;
    FConflictExistingPreview: TArosaImageResource;
    FConflictIncomingPreview: TArosaImageResource;
    FPendingOpKind: string;              { '' | 'paste' | 'transfer' }
    FPendingItems: TStringList;          { sources, snapshot taken at start }
    FPendingDest: string;
    FPendingTransferOp: TArosaTransferOperation;
    FPendingTargetView: Integer;
    FConflictSources, FConflictDests: TStringList;
    FConflictIndex: Integer;
    { the answer for each planned conflict, parallel to FConflictDests }
    FConflictChoices: array of TAFMConflictChoice;
    { size/date of both sides as the transfer worker saw them; nil when the
      conflicts were planned in this process (local files) }
    FConflictPlan: TAFMTransferReport;
    FUnplannedConflicts: Integer;
    { Drag feedback.  Everything the pointer handler needs is worked out
      once and remembered, so a pointer movement never touches a disk or a
      server: the folders the carried items live in, and the volume answer
      for the destination last looked at. }
    { "Create folder": also write the drawer icon.  The last answer is
      remembered for the session; [Files] NewFolderIcon sets the first. }
    FNewFolderIcon: Boolean;
    { [Panes] RemoteRole: theme role for the names of remote things;
      "none" switches the colouring off. }
    FRemoteRole: string;
    FDragSourceParents: TStringList;
    FDragParentsReady: Boolean;
    FDragVolumeDest: string;
    FDragVolumeCrosses: Boolean;
    { 0.10.6.2: what a plain drag does - Move, Copy or Ask - within one
      volume and across volumes ([FileOperations] DragSameVolume /
      DragOtherVolume); a drop that asks waits here for the menu choice }
    FDragSameVolume: string;
    FDragOtherVolume: string;
    FPendingDropItems: TStringList;
    FPendingDropDestination: string;
    FPendingDropView: Integer;
    FDragFeedbackKey: string;
    { 0.5.110.60 visible failures: per-item errors raised during an
      operation are collected and reported WITH its result, instead of each
      SetStatus being overwritten by the final summary. }
    FCollectOperationErrors: Boolean;
    FOperationErrors: TStringList;
    FPendingArchiveName, FPendingArchiveFormat, FPendingArchiveLocation,
      FPendingArchivePassword: string;
    FArchiveToOtherPane: Boolean;
    FArchiveDialogMode: Integer; { 0=compress, 1=expand }
    FArchiveSourcePath: string;
    FHiddenToolbarButton: TArosaButton;
    FThumbnailToolbarButton: TArosaButton;
    FPreviewToolbarButton: TArosaButton;
    FConsoleWrapButton: TArosaButton;
    FConsoleColumnsButton: TArosaButton;
    FConsoleColumnLessButton: TArosaButton;
    FConsoleColumnMoreButton: TArosaButton;
    FConsoleFontSmallerButton: TArosaButton;
    FConsoleFontLargerButton: TArosaButton;
    FMetadataToolbarButton: TArosaButton;
    FPlacesDetailToolbarButton: TArosaButton;
    FSplitToolbarButton: TArosaButton;
    { 0.6.1.2: image toggle buttons (was radio + image). }
    FListModeRadio: TArosaButton;
    FDetailsModeRadio: TArosaButton;
    FIconsModeRadio: TArosaButton;
    FWindowsModeRadio: TArosaButton;
    FUpdatingToolbarState: Boolean;
    FPreviewPercentLabel: TArosaLabel;
    FPreviewVisible: Boolean;
    FEditorRenditionVisible: Boolean;
    FMetadataVisible: Boolean;
    FPreviewPreferredPlacement: Integer;
    FPreviewPercent: Integer;
    FPendingDeleteItems: TStringList;
    FPendingDeleteView: Integer;
    FSyncScrolling: Boolean;
    FSyncWindows: Boolean;
    FSyncingScroll: Boolean;
    FSyncingSplitter: Boolean;
    FRestoringHistory: Boolean;
    FLoggingEnabled: Boolean;
    FConfiguredLoggingEnabled: Boolean;
    FConfiguredLoggingLevel: string;
    FDescriptorBase: string;
    FDescriptor: TArosaWindowDescriptor;
    FContext: TAFileManagerContext;
    FCapabilities: IArosaWindowCapabilityRegistry;
    FWindowDescriptor: TStringList;
    FGadgetDescriptor: TStringList;
    FMenuDescriptor: TStringList;
    FToolbarDescriptor: TStringList;
    FFileDescriptor: TStringList;
    FLocalization: TArosaLocalizationService;
    FFontService: TArosaFontService;
    procedure LoadLocalization;
    procedure LoadLocalizationSpec(const ASpec: string);
    function LocalText(const AKey, AFallback: string): string;
    function MetadataCaption(const ACaptionId: string): string;
    procedure StopCurrentSound;
    procedure AudioPlayClick(ASender: TArosaControl);
    procedure AudioPauseClick(ASender: TArosaControl);
    procedure AudioStopClick(ASender: TArosaControl);
    procedure AudioRewindClick(ASender: TArosaControl);
    procedure AudioForwardClick(ASender: TArosaControl);
    procedure UpdateAudioPlaybackLabels;
    function CurrentAudioPositionMS: Int64;
    procedure UpdateAudioPlaybackTelemetry;
    function LocalValue(const AValue, AFallback: string): string;
    function DescriptorValue(AList: TStringList; const AKey, ADefault: string): string;
    function DescriptorBool(AList: TStringList; const AKey: string; ADefault: Boolean): Boolean;
    function HandlerForCommand(const ACommand: string): TArosaClickEvent;
    procedure BuildCommandTabs(ATabs: TArosaTabControl; ADescriptor: TStringList;
      const ADefaultPage: string; ARegisterConsoleStateButtons: Boolean = True);
    procedure BuildMenuPanel(APanel: TArosaColumnPanel; ADescriptor: TStringList);
    procedure ClearSubMenu;
    procedure BuildRootMenu;
    procedure BuildThemeMenu;
    procedure BuildPreviewMenu;
    procedure MenuBackClick(ASender: TArosaControl);
    procedure MenuThemeClick(ASender: TArosaControl);
    procedure MenuPreviewClick(ASender: TArosaControl);
    procedure ConfigurationClick(ASender: TArosaControl);
    procedure HelpContentsClick(ASender: TArosaControl);
    procedure InfoClick(ASender: TArosaControl);
    procedure InfoExternalLink(ASender: TArosaControl; const AHref: string);
    procedure ConfigurationApply(ASender: TArosaControl;
      const ASettings: TAFMConfigurationSettings; APersist: Boolean);
    function CurrentConfigurationSettings: TAFMConfigurationSettings;
    function SaveUserConfiguration(const ASettings: TAFMConfigurationSettings): Boolean;
    procedure ApplyServiceConfiguration;
    function SaveStartupSelection(const ASettings: TAFMConfigurationSettings): Boolean;
    function InformationText: string;
    procedure ToggleSyncScrollingClick(ASender: TArosaControl);
    procedure ToggleSyncWindowsClick(ASender: TArosaControl);
    procedure PreviewOffClick(ASender: TArosaControl);
    procedure PreviewRightClick(ASender: TArosaControl);
    procedure PreviewBottomClick(ASender: TArosaControl);
    procedure PreviewShareDownClick(ASender: TArosaControl);
    procedure PreviewShareUpClick(ASender: TArosaControl);
    procedure TogglePlacesDetailClick(ASender: TArosaControl);
    procedure UpdateViewToolbarState;
    procedure UpdatePanelTabVisibility;
    procedure ApplyThemeToTree(AVisual: TArosaVisual; ATheme: TArosaTheme);
    procedure ApplyTheme(ATheme: TArosaTheme);
    procedure ApplyConfiguredFontsToTheme(ATheme: TArosaTheme);
    procedure ApplyConfigurationFonts(ATheme: TArosaTheme;
      const ASettings: TAFMConfigurationSettings);
    procedure ApplyLiveApplicationFont(const ASettings: TAFMConfigurationSettings);
    procedure ApplyLiveFileFonts(const ASettings: TAFMConfigurationSettings);
    procedure PopulateConfigurationChoices;
    procedure LoadColumnConfigurationFromDescriptor;
    function IsConfiguredColumnVisible(const AId: string): Boolean;
    function ColumnOrderText: string;
    function VisibleColumnsText: string;
    procedure ApplyPreviewLayout(AView, APlacement: Integer);
    procedure UpdatePaneInfo(AView: Integer);
    function IsProviderLocation(const APath: string): Boolean;
    function BuildDetailsHeader: TArosaRowPanel;
    procedure ConfigureDetailsColumns(AList: TArosaListView);
    function FileIconRowHeight: TArosaCoord;
    procedure ApplyFileViewGeometry(AView: Integer);
    function ColumnWidth(const ASection: string; ADefaultWidth: Integer): Integer;
    function NewDetailsCell(const AText, ASection: string; ADefaultWidth: Integer; AAlign: Integer): TArosaLabel;
    function IsThumbnailPictureResource(const AInfo: TArosaFileInfo): Boolean;
    procedure ClearThumbnailCache(AView: Integer);
    function ThumbnailCacheKey(const AInfo: TArosaFileInfo): string;
    function TryAddCompactThumbnail(ARow: TArosaListRow; const AInfo: TArosaFileInfo;
      AView: Integer; AGhosted: Boolean): Boolean;
    function AddSemanticDetailsIcon(ARow: TArosaListRow;
      const AInfo: TArosaFileInfo; AGhosted: Boolean): Boolean;
    procedure PopulateDetailsRow(ARow: TArosaListRow; const AInfo: TArosaFileInfo; AView: Integer);
    procedure PopulateIconRow(ARow: TArosaListRow;
      const AInfo: TArosaFileInfo; AWorkbench: Boolean = False);
    procedure ToggleHiddenFilesClick(ASender: TArosaControl);
    procedure ToggleThumbnailsClick(ASender: TArosaControl);
    function IsHiddenResource(const AInfo: TArosaFileInfo): Boolean;
    function IsArchivePath(const APath: string): Boolean;
    procedure ArchiveExtractHere(ASender: TArosaControl);
    procedure ArchiveExtractTo(ASender: TArosaControl);
    function ArchiverReady(const AExecutable, AFormat: string): Boolean;
    function ValidateArchiveSourceReadable(const APath: string; out AError: string): Boolean;
    function UploadLocalTreeToLocation(const ALocalDir, ARemoteDir: string; out AError: string): Boolean;
    function ThemeIconPath(const AName: string): string;
    function SemanticFileIconName(const AInfo: TArosaFileInfo): string;
    function AddRowImage(ARow: TArosaListRow; ABitmap: TArosaPlatformHandle;
      const ASource: TArosaRect; const AAltText: string;
      AOwnedResource: TArosaImageResource=nil; AGhosted: Boolean=False): Boolean;
    procedure ArchiveCompressHere(ASender: TArosaControl);
    procedure ArchiveCompressTo(ASender: TArosaControl);
    procedure ArchiveDialogCreate(ASender: TArosaControl; const AArchiveName, AFormat,
      ALocation, APassword: string);
    procedure ArchiveDialogCancel(ASender: TArosaControl);
    procedure ArchiveBrowseLocation(ASender: TArosaControl);
    procedure MoveToSelected(ASender: TArosaControl);
    function LocationPickerList(const ALocation: string;
      out AEntries: TArosaFileInfoArray): Boolean;
    function LocationPickerParent(const ALocation: string): string;
    procedure LocationPicked(ASender: TArosaControl; const ALocation: string);
    procedure LocationPickerCancelled(ASender: TArosaControl);
    procedure ComposeResourceContextMenu(AItems: TStringList);
    procedure LoadFavorites;
    procedure SaveFavorites;
    procedure LoadDesktopShortcuts;
    procedure SaveDesktopShortcuts;
    procedure RebuildVirtualLocations;
    function WorkspaceIdFromLocation(const ALocation: string): string;
    function WorkspaceStatePath(const AWorkspaceId, AKind: string): string;
    function WorkspaceUserConfigurationPath(
      const AWorkspaceId: string): string;
    function WorkspaceTrashDirectory(const AWorkspaceId: string): string;
    function WorkspacePrototypeById(const AId: string):
      TAFileManagerWorkspacePrototype;
    function HasOpenWorkspacePrototypes: Boolean;
    procedure WorkspacePrototypeClosed;
    procedure OpenWorkspacePrototype(AWorkspace: TArosaWorkspaceDefinition);
    procedure CloseWorkspacePrototype(const AId: string);
    procedure LoadWorkspacesFromUserProfile;
    function SaveWorkspacesToUserProfile: Boolean;
    procedure CreateWorkspaceClick(ASender: TArosaControl);
    procedure DeleteWorkspaceClick(ASender: TArosaControl);
    procedure RequestDeleteWorkspace(const AWorkspaceId: string);
    procedure RequestEditWorkspaceProperties(const AWorkspaceId: string);
    procedure WorkspacePropertiesApplied(ASender: TArosaControl;
      const ASettings: TAFMWorkspaceProperties);
    procedure WorkspaceBackgroundBrowse(ASender: TArosaControl);
    procedure ShowWorkspaceModules(const AWorkspaceId: string);
    procedure WorkspaceModuleChanged(ASender: TArosaControl;
      const AWorkspaceId, AModuleId: string; AEnabled: Boolean);
    procedure WorkspaceBackgroundSelected(ASender: TArosaControl;
      const APath: string);
    function StandardDialogList(const ADirectory: string;
      out AEntries: TArosaFileInfoArray): Boolean;
    procedure FileDialogDecorateRow(ASender: TArosaControl;
      ARow: TArosaListRow; const AInfo: TArosaFileInfo);
    function FileDialogResolveIcon(const ASemantic: string;
      out AImage: TArosaPlatformHandle; out ASource: TArosaRect): Boolean;
    procedure ConfigureStandardOpenDialogLocations;
    function ActivateWorkspaceLocation(const ALocation: string): Boolean;
    procedure Diagnostic(const AMessage: string);
    procedure StartInstanceDiagnostics;
    procedure StopInstanceDiagnostics;
    procedure FlushInstanceDiagnostics(AForce: Boolean = False);
    procedure NativeActivated;
    procedure NativeDeactivated;
    procedure UpdateWorkspacePendingWork;
    procedure ShowCrossWorkspacePendingBubble;
    procedure WorkspaceCloseScreenClick(ASender: TArosaControl);
    function ActivateWorkspaceSelfResource(const APath: string): Boolean;
    function DesktopShortcutIndex(const ATarget: string): Integer;
    function AddDesktopShortcut(const ATarget: string): Boolean;
    function RemoveDesktopShortcut(const ATarget: string): Boolean;
    { 0.8.6.4 }
    function ShortcutDisplayName(const ATarget: string): string;
    function StartMenuContains(const ATarget: string): Boolean;
    function AddStartMenuEntry(const ATarget: string): Boolean;
    function RemoveStartMenuEntry(const ATarget: string): Boolean;
    function IsDesktopLocation(const ALocation: string): Boolean;
    procedure EmptyTrash;
    procedure RequestPermanentTrashDelete;
    procedure ExecutePermanentTrashDelete;
    procedure RequestTrashRestore;
    procedure ExecuteTrashRestore;
    function IsWorkspaceTrashLocation(const ALocation: string): Boolean;
    procedure LoadNetworkLocations;
    procedure SaveNetworkLocations;
    function NetworkLocationIndex(const ALocation: string): Integer;
    procedure ShowAddNetworkLocation;
    procedure ShowPlaceProperties(const ALocation: string);
    procedure EditSelectedPlace(ASender: TArosaControl);
    procedure NetworkLocationAdded(ASender: TArosaControl; const ALabel, AScheme, AServer: string; APort: Integer; const APath: string);
    procedure NetworkLocationCancelled(ASender: TArosaControl);
    procedure NetworkLocationTestServer(ASender: TArosaControl; const AScheme, AServer: string;
      APort: Integer; const APath: string; out ASuccess: Boolean; out AMessage: string);
    procedure NetworkLocationTestAccess(ASender: TArosaControl; const AScheme, AServer: string;
      APort: Integer; const APath: string; out ASuccess: Boolean; out AMessage: string);
    function FavoriteKey(const APath: string): string;
    function FavoriteIndex(const APath: string): Integer;
    function AddFavorite(const APath: string): Boolean;
    function RemoveFavorite(const APath: string): Boolean;
    procedure ExpandFavoriteEntry(AItems: TStringList; const ATarget: string);
    function ListFavoriteTarget(AView: Integer): string;
    procedure ShowProperties(AView: Integer; const APath: string);
    procedure BuildPlacesContextMenu;
    procedure PlacesContextCommand(ASender: TArosaControl; const ACommand: string);
    function PlacesContextCommandEnabled(ASender: TArosaControl; const ACommand: string): Boolean;
    procedure PlacesContextMenuOpening(ASender: TArosaControl);
    procedure ResourceContextCommand(ASender: TArosaControl; const ACommand: string);
    function ResourceContextCommandEnabled(ASender: TArosaControl; const ACommand: string): Boolean;
    procedure MetadataContextMenuOpening(ASender: TArosaControl);
    procedure MetadataContextCommand(ASender: TArosaControl; const ACommand: string);
    function MetadataContextCommandEnabled(ASender: TArosaControl;
      const ACommand: string): Boolean;
    function ResourceContextCommandShortcut(ASender: TArosaControl; const ACommand: string): string;
    function TryResourceContextCommand(ASender: TArosaControl; const ACommand: string): Boolean;
    function ListShortcut(ASender: TArosaControl; const AKey: string): Boolean;
    function ResourceOperationError(const AOperation, ASource, ADestination, AMessage: string): TArosaOperationErrorDecision;
    function ResourceConflict(const ASource, ADestination: string; ASourceIsDirectory, ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
    procedure StyleCommandTabs(ATabs: TArosaTabControl);
    procedure SetStatus(const AText: string);
    procedure LogMessage(const AText: string);
    function NewButton(AParent: TArosaView; const ACaption, AHint: string;
      AHandler: TArosaClickEvent; AWidth: Integer = 92): TArosaButton;
    procedure NewMenuSeparator(AParent: TArosaView; AWidth: Integer);
    function NewMenuItem(AParent: TArosaView; const ACaption, AHint: string;
      AHandler: TArosaClickEvent; AWidth: Integer = 148;
      const ACommand: string = ''): TArosaMenuItem;
    function NewPage(ATabs: TArosaTabControl; const ACaption: string): TArosaTabPage;
    procedure PopulateAssignments;
    procedure LoadHistory;
    procedure SaveHistory;
    function StateRead(const ADocument, AFile: string; AGlobal: Boolean;
      out AText: string): Boolean;
    function StateWrite(const ADocument, AFile: string; AGlobal: Boolean;
      const AText: string): Boolean;
    procedure AddRecent(AList: TStringList; const APath: string);
    procedure LoadLayout;
    procedure SaveLayout;
    procedure BackClick(ASender: TArosaControl);
    procedure ForwardClick(ASender: TArosaControl);
    procedure UpClick(ASender: TArosaControl);
    procedure HomeClick(ASender: TArosaControl);
    function LocationMaxEntries(const AGroup: string): Integer;
    procedure SetActiveView(AView: Integer);
    function ViewList(AView: Integer): TArosaFilteredListView;
    function ViewCrumbs(AView: Integer): TArosaBreadcrumbBar;
    procedure SetPathEditing(AView: Integer; AEditing: Boolean);
    procedure SyncCrumbs(AView: Integer);
    procedure LeftCrumbNavigate(ASender: TArosaControl; const APath: string);
    procedure RightCrumbNavigate(ASender: TArosaControl; const APath: string);
    procedure LeftCrumbEdit(ASender: TArosaControl; const APath: string);
    procedure RightCrumbEdit(ASender: TArosaControl; const APath: string);
    function ViewPathBox(AView: Integer): TArosaTextBox;
    function ViewCurrent(AView: Integer): string;
    procedure SetViewCurrent(AView: Integer; const AValue: string);
    function SelectedPath(AView, AIndex: Integer): string;
    function ParentPath(const APath: string): string;
    procedure NavigateView(AView: Integer; const APath: string);
    procedure RefreshView(AView: Integer);
    function StartEnumerationWorker(AView: Integer; const APath: string;
      ASyncOther: Boolean): Boolean;
    procedure EnumerationIdle(var AMoreWorkPending: Boolean);
    procedure PresentEnumerationEntries(AView: Integer; const APath: string;
      var AEntries: TArosaFileInfoArray; ASyncOther: Boolean);
    procedure RefreshBoth;
    function RunCommand(const AExecutable, AArguments,
      AWorkingDirectory: string; out AOutput: string): Boolean;
    procedure AssignmentActivated(ASender: TArosaControl; AIndex: Integer);
    procedure SortEntries(var AEntries: TArosaFileInfoArray);
    procedure LeftSelected(ASender: TArosaControl; AIndex: Integer);
    procedure RightSelected(ASender: TArosaControl; AIndex: Integer);
    procedure LeftActivated(ASender: TArosaControl; AIndex: Integer);
    procedure RightActivated(ASender: TArosaControl; AIndex: Integer);
    procedure ActivateItem(AView, AIndex: Integer);
    function OpenAssociatedResource(const APath: string): Boolean;
    { 0.8.6.2: an http/https address from a previewed page }
    function OpenWebLink(const AAddress: string): Boolean;
    procedure LeftPathEnter(ASender: TArosaControl);
    procedure RightPathEnter(ASender: TArosaControl);
    procedure RefreshClick(ASender: TArosaControl);
    procedure SelectAllClick(ASender: TArosaControl);
    procedure ClearSelectionClick(ASender: TArosaControl);
    procedure CreateFolderClick(ASender: TArosaControl);
    procedure CreateFileClick(ASender: TArosaControl);
    procedure RenameClick(ASender: TArosaControl);
    procedure NameDialogAccepted(ASender: TArosaControl; const AValue: string);
    procedure CopyClick(ASender: TArosaControl);
    procedure CutClick(ASender: TArosaControl);
    procedure PasteClick(ASender: TArosaControl);
    procedure DeleteClick(ASender: TArosaControl);
    procedure ConfirmArchiveOverwrite(ASender: TArosaControl);
    procedure BeginResourceOperation(const AKind: string; AItems: TStrings;
      const ADestination: string; AOperation: TArosaTransferOperation;
      ATargetView: Integer);
    procedure AskNextConflict;
    function BubbleText(const AText: string): string;
    procedure BuildThemeLayers;
    function RemotePreviewDeferred(AView: Integer; const ALocation: string;
      out ASize, ALimit: Int64): Boolean;
    procedure ForcePreview(AView: Integer);
    procedure ApplyServiceSettings;
    function LoadThemeIcon(const ASpec: string; out AImage: TArosaPlatformHandle;
      out ASource: TArosaRect): Boolean;
    function IconSpecFor(const ASection, AKey: string): string;
    function ApplyButtonIcon(AButton: TArosaButton; const ASection, AKey: string;
      AIconWidth: Integer): Boolean;
    function ContextCommandIcon(ASender: TArosaControl; const ACommand: string;
      out AImage: TArosaPlatformHandle; out ASource: TArosaRect): Boolean;
    function CommandBarIcon(const AIconRef: string; out AImage: TArosaPlatformHandle;
      out ASource: TArosaRect): Boolean;
    procedure ApplyWindowIconsTo(AFrame: TArosaWindowFrame);
    procedure ApplyWindowIcons;
    procedure ApplyThemeColourLayers;
    procedure ApplyBubbleConfiguration;
    procedure ApplyBubbleColours(ATheme: TArosaTheme; const ASection: string);
    function CommandBarText(const AKey: string): string;
    procedure PresentationMessage(ASender: TObject; const AText: string);
    procedure ReleasePresentation(var APresentation: TArosaPresentation);
    procedure TestAutoCloseIdle(var AMoreWorkPending: Boolean);
    function ViewCommandBar(AView: Integer): TArosaCommandBar;
    function NewCommandBar: TArosaCommandBar;
    procedure BeginOperationErrors;
    function EndOperationErrors: string;
    function NameOperationFailure(const AKind, ASource, ATarget: string): string;
    function DirectorySignature(const APath: string): string;
    function AvailableArchiveFormats: TStringArray;
    function ArchiveListCommand(const AFormat, AArchive: string;
      out AExe, AArgs: string): Boolean;
    procedure ResourceConflictDecided(ASender: TArosaControl;
      AChoice: TArosaOperationChoice; AApplyToAll: Boolean);
    procedure RunPendingResourceOperation;
    function PendingOperationNeedsWorker: Boolean;
    procedure StartBackgroundResourceOperation(const APhase: string);
    function StartExternalProviderTransfer(const APhase: string): Boolean;
    function PollExternalProviderTransfer(AReport: TAFMTransferReport): Boolean;
    procedure FinishExternalProviderTransfer(AReport: TAFMTransferReport);
    procedure ReleaseExternalTransferFiles;
    procedure ResetPendingResourceOperation;
    function ConflictSideDetail(const ASide: TAFMConflictSide;
      const APath: string; out AInfo: TArosaFileInfo): string;
    function IsRemoteLocation(const APath: string): Boolean;
    function RemoteTextRole: string;
    function RemoteLocationLabel(const APath: string): string;
    function SpawnWorker(AJob: TArosaWorkerJob): Boolean;
    procedure TransferCompleted(AJob: TArosaWorkerJob);
    procedure TransferIdle(var AMoreWorkPending: Boolean);
    procedure CancelTransferClick(ASender: TArosaControl);
    procedure PauseTransferClick(ASender: TArosaControl);
    procedure ResumeTransferClick(ASender: TArosaControl);
    procedure RefreshAffectedViews(ASources: TStrings; const ADestination: string);
    procedure PublishLocationChanged(const ALocation: string;
      AKind: TArosaLocationMutationKind);
    procedure LocationChanged(ASender: TObject; const ALocation: string;
      AKind: TArosaLocationMutationKind);
    function DescribeResource(const APath: string): string;
    function ConflictResourceDetail(const APath: string;
      out AInfo: TArosaFileInfo): string;
    function LoadConflictPreview(const APath: string;
      const AInfo: TArosaFileInfo): TArosaImageResource;
    procedure ClearConflictPreviews;
    procedure CancelArchiveOverwrite(ASender: TArosaControl);
    procedure ConfirmDeleteClick(ASender: TArosaControl);
    procedure CancelDeleteClick(ASender: TArosaControl);
    procedure ExecutePendingDelete;
    procedure ExecuteScriptClick(ASender: TArosaControl);
    procedure UndoClick(ASender: TArosaControl);
    procedure RedoClick(ASender: TArosaControl);
    procedure ConsoleClick(ASender: TArosaControl);
    function CreateConsoleDocument(const ALocation: string): TAFileManagerConsoleDocument;
    function ConsoleDocumentForControl(AControl: TArosaControl): TAFileManagerConsoleDocument;
    function ConsoleDocumentForCommandSender(AControl: TArosaControl): TAFileManagerConsoleDocument;
    function ConsoleCommandDocument(AControl: TArosaControl): TAFileManagerConsoleDocument;
    function ActiveConsoleDocument: TAFileManagerConsoleDocument;
    function AllocateConsoleId: Integer;
    procedure SetConsoleOperationsVisible(AVisible: Boolean);
    procedure ConsoleOperationNewClick(ASender: TArosaControl);
    procedure ConsoleOperationClearClick(ASender: TArosaControl);
    procedure ConsoleOperationCloseClick(ASender: TArosaControl);
    procedure ConsoleSearchClick(ASender: TArosaControl);
    procedure ConsoleWrapClick(ASender: TArosaControl);
    procedure ConsoleColumnsClick(ASender: TArosaControl);
    procedure ConsoleColumnLessClick(ASender: TArosaControl);
    procedure ConsoleColumnMoreClick(ASender: TArosaControl);
    procedure UpdateConsoleToolState;
    procedure FormatConsoleColumns(ALines: TStrings; AConsole: TArosaCommandConsole);
    procedure ReflowConsoleColumns(AConsole: TArosaCommandConsole);
    procedure ConsoleFontSmallerClick(ASender: TArosaControl);
    procedure ConsoleFontLargerClick(ASender: TArosaControl);
    function ConsoleAdjacentFontSize(AConsole: TArosaCommandConsole; ADirection: Integer; out ASize: Integer): Boolean;
    procedure ConsoleHistoryPreviousClick(ASender: TArosaControl);
    procedure ConsoleHistoryNextClick(ASender: TArosaControl);
    procedure ConsoleEnvironmentInfoClick(ASender: TArosaControl);
    procedure DocumentTabChanged(ASender: TObject; AIndex: Integer);
    procedure DocumentTabContextRequested(ASender: TObject; AIndex: Integer;
      const APosition: TArosaPoint);
    procedure DocumentTabCloseClick(ASender: TArosaControl);
    procedure HideDocumentTabMenu;
    procedure ActivateEnvironment(const AEnvironment: string);
    function EnvironmentSection(const AEnvironment, ASurface, AFallback: string): TStringList;
    procedure RebuildCommandSurface(ATabs: TArosaTabControl; ADescriptor: TStringList; const ADefaultPage: string);
    procedure CloseConsoleDocument(ADoc: TAFileManagerConsoleDocument);
    procedure CloseConsoleDocumentNow(ADoc: TAFileManagerConsoleDocument);
    procedure ConsoleCloseIdle(var AMoreWorkPending: Boolean);
    procedure ConsoleExecutionIdle(var AMoreWorkPending: Boolean);
    procedure EnsureConsoleExecutionIdle;
    procedure FinishConsoleExecution(ADoc: TAFileManagerConsoleDocument;
      const AOutput, AError: string; AExitCode: LongInt);
    procedure ConsoleCloseClick(ASender: TArosaControl);
    procedure ConsoleContextCommand(ASender: TArosaControl; const ACommand: string);
    function ConsoleContextCommandEnabled(ASender: TArosaControl;
      const ACommand: string): Boolean;
    function ConsoleDocumentForSurface(ASurface: TArosaApplicationSurface): TAFileManagerConsoleDocument;
    procedure PopOutConsoleDocument(ADoc: TAFileManagerConsoleDocument);
    procedure EmbedConsoleDocument(ADoc: TAFileManagerConsoleDocument);
    procedure ConsoleFrameCloseRequested(ASender: TObject;
      ASurface: TArosaApplicationSurface);
    procedure ConsoleFrameActivated(ASender: TObject;
      ASurface: TArosaApplicationSurface);
    procedure EnsureFloatingConsoleChrome(ADoc: TAFileManagerConsoleDocument);
    procedure ARexxClick(ASender: TArosaControl);
    function ConsoleSubmit(ASender: TArosaControl; const ALine: string): string;
    function DefaultConsoleLocation: string;
    function ConsoleLocationLabel(const ALocation: string): string;
    procedure UpdateConsoleCaption(ADoc: TAFileManagerConsoleDocument);
    function HandleConsoleTargetCommand(ADoc: TAFileManagerConsoleDocument;
      const ALine: string): Boolean;
    procedure OpenConsoleAt(const ALocation: string);
    procedure OpenConsoleFromSource(ASource: TAFileManagerConsoleDocument);
    procedure OpenConsoleHereClick(ASender: TArosaControl);
    procedure MacrosClick(ASender: TArosaControl);
    procedure ShowMetadataClick(ASender: TArosaControl);
    procedure ToggleToolbarClick(ASender: TArosaControl);
    procedure ToggleOperationsClick(ASender: TArosaControl);
    procedure ToggleSplitClick(ASender: TArosaControl);
    procedure NewFileManagerClick(ASender: TArosaControl);
    procedure CloseFileManagerClick(ASender: TArosaControl);
    procedure SurfaceTabClick(ASender: TArosaControl);
    procedure SaveActiveSurface;
    procedure ShowSurface(AIndex: Integer);
    procedure RebuildSurfaceBar;
    procedure TogglePreviewClick(ASender: TArosaControl);
    procedure ShowResourceMetadataClick(ASender: TArosaControl);
    procedure SetPanels(APreview, AMetadata: Boolean; ASelectTab: Integer);
    procedure ThemeDarkClick(ASender: TArosaControl);
    procedure ThemeLightClick(ASender: TArosaControl);
    procedure ViewListClick(ASender: TArosaControl);
    procedure ViewDetailsClick(ASender: TArosaControl);
    procedure ViewIconsClick(ASender: TArosaControl);
    procedure ViewWindowsClick(ASender: TArosaControl);
    procedure LeftFilterChanged(ASender: TArosaControl);
    procedure LeftSearchChanged(ASender: TArosaControl);
    procedure ClearLeftFilterClick(ASender: TArosaControl);
    procedure ClearRightFilterClick(ASender: TArosaControl);
    procedure ClearLeftSearchClick(ASender: TArosaControl);
    procedure ClearRightSearchClick(ASender: TArosaControl);
    procedure ApplyResourceSearch(AView: Integer);
    procedure PropertiesClick(ASender: TArosaControl);
    procedure EditPermissionsClick(ASender: TArosaControl);
    procedure PermissionChanged(ASender: TArosaControl; APaths: TStrings);
    procedure LeftHorizontalScroll(ASender: TArosaControl; AValue: Integer);
    procedure RightHorizontalScroll(ASender: TArosaControl; AValue: Integer);
    procedure LeftVerticalScroll(ASender: TArosaControl; AValue: Integer);
    procedure RightVerticalScroll(ASender: TArosaControl; AValue: Integer);
    function ActivePreviewSplit: TArosaSplitterHost;
    function ActivePathRole: string;
    procedure UpdatePreviewPercentLabel;
    procedure StepPreviewPercent(ADelta: Integer);
    procedure PreviewSplitterChanged(ASender: TArosaSplitterHost; APosition: TArosaCoord);
    procedure ListPointerDown(ASender: TArosaControl);
    procedure ListSortChanged(ASender: TArosaControl;
      const AColumnId: string; AAscending: Boolean);
    procedure ListContextMenuOpening(ASender: TArosaControl);
    procedure FrameMenuOpening(ASender: TArosaControl);
    procedure SyncDetailsHeader(AHeader: TArosaRowPanel; AOffset: Integer);
    procedure RightFilterChanged(ASender: TArosaControl);
    procedure RightSearchChanged(ASender: TArosaControl);
    procedure PlacesFilterChanged(ASender: TArosaControl);
    procedure ClearPlacesFilterClick(ASender: TArosaControl);
    procedure HoverHint(const AHint: string);
    function DetailsHeader: string;
    function DetailsRow(const AInfo: TArosaFileInfo): string;
    function ResourceTypeName(const AInfo: TArosaFileInfo): string;
    procedure ExitClick(ASender: TArosaControl);
    procedure ClearUndo;
    procedure BeginNameInput(const AKind, ADefaultPath, ASource: string);
    procedure CommitNameInput(AView: Integer);
    function CopyResourceRecursive(const ASource, ADestination: string): Boolean;
    function DeleteResourceRecursive(const APath: string): Boolean;
    procedure DualViewClick(ASender: TArosaControl);
    procedure LeftOnlyClick(ASender: TArosaControl);
    procedure RightOnlyClick(ASender: TArosaControl);
    procedure SwapViewsClick(ASender: TArosaControl);
    procedure WindowCloseRequested(ASender: TArosaControl);
    procedure NativeCloseRequested;
    procedure ApplicationCloseIdle(var AMoreWorkPending: Boolean);
    { 0.8.27.10: application endpoint heartbeat and administrative requests
      (activate from a second launch, quit from Foundation, Ctrl-C) }
    procedure EndpointIdle(var AMoreWorkPending: Boolean);
    procedure WindowZoomRequested(ASender: TArosaControl);
    procedure WindowMinimizeRequested(ASender: TArosaControl);
    procedure WindowDepthRequested(ASender: TArosaControl);
    procedure WindowActivateRequested(ASender: TArosaControl);
    procedure WindowNativeDrag(AZone: TArosaWindowHitZone;
      const APosition: TArosaPoint; AStarting, AEnding: Boolean);
    procedure WindowToolbarChanged(ASender: TArosaControl);
    procedure WindowFilePanelChanged(ASender: TArosaControl);
    procedure WindowSplitViewChanged(ASender: TArosaControl);
    procedure WindowPreviewChanged(ASender: TArosaControl);
    procedure UpdatePreview(AView: Integer);
    procedure UpdatePreviewNow(AView: Integer);
    procedure QueuePreview(AView: Integer);
    function PreviewPageActive(AView: Integer): Boolean;
    procedure UpdateSelectionMetadata(AView: Integer);
    procedure PreviewTabsChanged(ASender: TObject; AIndex: Integer);
    procedure PreviewIdle(var AMoreWorkPending: Boolean);
    function SelectedRowIsDirectory(AView, AIndex: Integer): Boolean;
    procedure SaveInternalEdit(ASender: TArosaControl);
    function SaveDocument(ADoc: TAFileManagerDocument): Boolean;
    procedure ReleaseDocumentRendition(ADoc: TAFileManagerDocument);
    procedure RefreshDocumentRendition(ADoc: TAFileManagerDocument);
    procedure DocumentChanged(ASender: TArosaControl);
    procedure ToggleDocumentRendition(ASender: TArosaControl);
    procedure DocumentSaveClick(ASender: TArosaControl);
    procedure DocumentCloseClick(ASender: TArosaControl);
    procedure DocumentFindClick(ASender: TArosaControl);
    procedure DocumentReplaceClick(ASender: TArosaControl);
    procedure DocumentGoToLineClick(ASender: TArosaControl);
    procedure DocumentRenditionClick(ASender: TArosaControl);
    procedure EditorCloseRequested(ASender: TArosaControl);
    procedure EditorCommandFocus(ASender: TArosaControl);
    procedure RequestCloseDocument(ADoc: TAFileManagerDocument);
    procedure FinishCloseDocument(ADoc: TAFileManagerDocument);
    procedure DocumentCloseIdle(var AMoreWorkPending: Boolean);
    procedure QueueCloseDocument(ADoc: TAFileManagerDocument);
    procedure SaveChoiceMade(ASender: TArosaControl; AChoice: TArosaSaveChoice);
    procedure ContinueApplicationClose;
    procedure RequestApplicationClose;
    procedure BeginInternalEdit(const APath: string);
    procedure ConfigureDocumentEditor(AEditor: TArosaEditor);
    procedure ImageTransformRequested(ASender: TArosaControl; ATransform: TArosaImageTransform);
    function ResourceDragBegin(ASender: TArosaControl; AIndex: Integer;
      const ARootPosition: TArosaPoint; const AModifiers: TArosaModifiers;
      out APayload: TArosaDragPayload): Boolean;
    procedure ResourceDragEnd(ASender: TArosaControl; AIndex: Integer;
      APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
      const AModifiers: TArosaModifiers);
    procedure ResourceDragMove(ASender: TArosaControl;
      APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
      const AModifiers: TArosaModifiers);
    procedure ResourceDragFinished(ASender: TArosaControl);
    function ResolveDropTarget(ASender: TArosaControl;
      const ARootPosition: TArosaPoint; AAllowProbe: Boolean;
      out ATargetView, ATargetRow: Integer; out ADestination: string): Boolean;
    function DropOperationFor(APayload: TArosaDragPayload;
      const ADestination: string; const AModifiers: TArosaModifiers;
      out AAsk: Boolean): TArosaTransferOperation;
    function DropIntoItself(APayload: TArosaDragPayload; const ADestination: string): Boolean;
    function TryDropMenuCommand(const ACommand: string): Boolean;
    procedure CollectSelectedPaths(AView: Integer; AItems: TStrings);
  protected
    procedure DoDispose; override;
  public
    constructor CreateManager(const APlatform: IArosaPlatform;
      AForm: TArosaForm; ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const ADescriptorPath: string;
      const AInitialWorkspaceId: string = 'default');
    { Public entry points so the canonical command target (Console/ARexx/Macro)
      can dispatch through the same handler table as the UI. }
    function CanRunCommandId(const ACommandId: string): Boolean;
    function RunCommandId(const ACommandId: string): Boolean;
    procedure BindNativeHost(AHost: TArosaFormHost);
    { 0.7.5.2: the counterpart of BindNativeHost, called while the host and
      the application are still alive (the host is freed before the
      controller): removes every idle handler and forgets the host. }
    procedure UnbindNativeHost;
    procedure ConfigureWorkspaceSession(const AWorkspaceId: string;
      ACloseRequest: TArosaHostCloseRequest;
      ANavigationOwner: TAFileManagerController = nil);
    { 0.8.6.4: what an application started from this workspace is told - the
      workspace it lives in and the theme that workspace is showing }
    function WorkspaceLaunchArguments: string;
    { 0.8.6.6: where a module of a workspace shows (AKind 0 start menu,
      1 taskbar, 2 desktop), for ANY workspace, read from and written to the
      catalogue files of that workspace }
    function ModulePlacement(const AWorkspaceId, AModuleId: string;
      AKind: Integer): Boolean;
    function ApplyModulePlacement(const AWorkspaceId, AModuleId: string;
      AKind: Integer; AEnabled: Boolean): Boolean;
    procedure ModulePlacementChanged(ASender: TArosaControl;
      const AWorkspaceId, AModuleId: string; AKind: Integer; AEnabled: Boolean);
    { every file manager of this program follows a change of membership or
      placement made in any of them }
    procedure SyncWorkspaceMembership;
    { 0.8.6.5: the taskbar of this workspace, on AScreen (nil = the default
      screen).  Closed with the window of the file manager. }
    function OpenTaskbar(AScreen: TArosaPlatformHandle;
      const AWorkspaceName: string): Boolean;
    procedure CloseTaskbar;
    { 0.8.6.5: volumes that come and go.  PollVolumes asks the platform (at
      most every two seconds unless forced) and is true when the set changed. }
    function StartedFromWorkspace: Boolean;
    function PollVolumes(AForce: Boolean = False): Boolean;
    procedure AcknowledgeVolume(const AName: string);
    procedure OpenVolume(const AName: string);
    procedure OpenWorkspaceLocation(const AWorkspaceId: string);
  end;

  { Bridges the canonical command layer (used by the Console, ARexx and Macro
    services) to the controller's existing command handlers. A submitted
    command id is routed through the same HandlerForCommand table the toolbar
    and menus use, so console/script/macro dispatch and UI dispatch share one
    path. }
  TAFileManagerCommandTarget = class(TArosaObject, IArosaCommandTarget)
  private
    FController: TAFileManagerController;
  public
    constructor CreateForController(AController: TAFileManagerController);
    function CanHandleCommand(const ACommandId: TArosaCommandId): Boolean;
    function ExecuteCommand(const ACommandId: TArosaCommandId;
      AContext: TArosaCommandContext): Boolean;
    procedure QueryCommandState(const ACommandId: TArosaCommandId;
      var AEnabled, AVisible, AChecked: Boolean);
  end;

var
  GAFMInstanceSerial: Integer = 0;

procedure AFMWorkerEntry(AUserData: Pointer);
begin
  if AUserData<>nil then TArosaWorkerJob(AUserData).Run;
end;

constructor TAFMTransferJob.CreateTransfer(
  AOperations: TArosaResourceOperationService; AItems: TStrings;
  const ADestination: string; AOperation: TArosaTransferOperation);
var I: Integer; A: TArosaResourceAccess; Dst: string;
begin
  inherited Create;
  FOperations:=AOperations;
  FItems:=TStringList.Create;
  if AItems<>nil then FItems.AddStrings(AItems);
  FDestination:=ADestination;
  FOperation:=AOperation;
  FErrors:=TStringList.Create;
  FTopLevelFailed:=TStringList.Create;
  FTopLevelFailed.CaseSensitive:=False;
  FQueueCount:=0;
  SetLength(FQueue,16);
  if (FOperations<>nil) and (FOperations.ResourceAccess<>nil) then
  begin
    A:=FOperations.ResourceAccess;
    for I:=FItems.Count-1 downto 0 do
    begin
      Dst:=A.Join(FDestination,A.LeafName(FItems[I]));
      PushNode(FItems[I],Dst,False,True,FItems[I]);
    end;
  end;
end;

destructor TAFMTransferJob.Destroy;
begin
  SetLength(FQueue,0);
  FTopLevelFailed.Free;
  FErrors.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TAFMTransferJob.PushNode(const ASource, ADestination: string;
  APostDirectory, ATopLevel: Boolean; const ARootSource: string);
begin
  if FQueueCount>=Length(FQueue) then
  begin
    if Length(FQueue)=0 then SetLength(FQueue,16)
    else SetLength(FQueue,Length(FQueue)*2);
  end;
  FQueue[FQueueCount].Source:=ASource;
  FQueue[FQueueCount].Destination:=ADestination;
  FQueue[FQueueCount].PostDirectory:=APostDirectory;
  FQueue[FQueueCount].TopLevel:=ATopLevel;
  FQueue[FQueueCount].RootSource:=ARootSource;
  Inc(FQueueCount);
end;

procedure TAFMTransferJob.MarkRootFailed(const ARootSource: string);
begin
  if (FTopLevelFailed=nil) or (Trim(ARootSource)='') then Exit;
  if FTopLevelFailed.IndexOf(ARootSource)<0 then FTopLevelFailed.Add(ARootSource);
end;

function TAFMTransferJob.RootFailed(const ARootSource: string): Boolean;
begin
  Result:=(FTopLevelFailed<>nil) and
    (FTopLevelFailed.IndexOf(ARootSource)>=0);
end;

function TAFMTransferJob.VerifyDirectoryShape(
  const ASource, ADestination: string): Boolean;
var
  A: TArosaResourceAccess;
  SEntries, DEntries: TArosaFileInfoArray;
  I, J: Integer;
  Found, SourceIsDir, DestIsDir: Boolean;
begin
  Result:=False;
  if (FOperations=nil) or (FOperations.ResourceAccess=nil) then Exit;
  A:=FOperations.ResourceAccess;

  if not A.Enumerate(ASource,SEntries) then Exit;
  if not A.Enumerate(ADestination,DEntries) then Exit;

  { Merge semantics allow unrelated destination children.  Every immediate
    SOURCE child must nevertheless exist in the destination with the same
    file/directory shape. File bytes themselves were verified by CopyFile. }
  for I:=0 to High(SEntries) do
  begin
    if (SEntries[I].Name='.') or (SEntries[I].Name='..') then Continue;
    Found:=False;
    for J:=0 to High(DEntries) do
      if SameText(SEntries[I].Name,DEntries[J].Name) then
      begin
        SourceIsDir:=SEntries[I].Kind=afekDirectory;
        DestIsDir:=DEntries[J].Kind=afekDirectory;
        if SourceIsDir<>DestIsDir then Exit(False);
        Found:=True;
        Break;
      end;
    if not Found then Exit(False);
  end;

  Result:=True;
end;

function TAFMTransferJob.PopNode(out ANode: TAFMTransferNode): Boolean;
begin
  Result:=FQueueCount>0;
  if not Result then Exit;
  Dec(FQueueCount);
  ANode:=FQueue[FQueueCount];
end;

procedure TAFMTransferJob.RequestCancel;
begin
  FCancelRequested:=True;
end;

function TAFMTransferJob.ContinueTransfer: Boolean;
begin
  Result:=not FCancelRequested;
  if not Result then FCancelled:=True;
end;

procedure TAFMTransferJob.TransferProgress(const ASource, ADestination: string);
begin
  Inc(FProgressUnits);
  if (ASource='') and (ADestination='') then ;
end;

function TAFMTransferJob.TransferError(const AOperation, ASource,
  ADestination, AMessage: string): TArosaOperationErrorDecision;
begin
  FErrors.Add(AOperation+': '+ASource+' -> '+ADestination+' - '+AMessage);
  Result:=aoedSkip;
end;

function TAFMTransferJob.Step: Boolean;
var
  N: TAFMTransferNode;
  A: TArosaResourceAccess;
  E: TArosaFileInfoArray;
  I: Integer;
  Ok: Boolean;
begin
  Result:=False;
  if FCancelRequested then
  begin
    FCancelled:=True;
    FSuccessful:=False;
    FQueueCount:=0;
    Exit(True);
  end;
  if (FOperations=nil) or (FOperations.ResourceAccess=nil) then
  begin
    FErrors.Add('Resource access service unavailable');
    FSuccessful:=False;
    Exit(True);
  end;
  A:=FOperations.ResourceAccess;
  if not PopNode(N) then
  begin
    FSuccessful:=(FErrors.Count=0) and (not FCancelled);
    Exit(True);
  end;

  if N.PostDirectory then
  begin
    Ok:=not RootFailed(N.RootSource);
    if Ok and (not A.Exists(N.Destination) or
       not A.IsDirectory(N.Destination)) then
    begin
      FErrors.Add('verify-directory: '+N.Destination+
        ' - destination directory is missing');
      MarkRootFailed(N.RootSource);
      Ok:=False;
    end;
    if Ok and (not VerifyDirectoryShape(N.Source,N.Destination)) then
    begin
      FErrors.Add('verify-directory: '+N.Source+' -> '+N.Destination+
        ' - destination tree shape does not contain every source child');
      MarkRootFailed(N.RootSource);
      Ok:=False;
    end;
    { Never remove a source directory for MOVE when any descendant failed.
      A deep move must leave the source tree recoverable on partial failure. }
    if Ok and (FOperation=atoMove) then
      Ok:=A.RemoveDirectory(N.Source);
    if not Ok then
    begin
      if (FOperation=atoMove) and (not RootFailed(N.RootSource)) then
        FErrors.Add('move: '+N.Source+' - source directory could not be removed');
      MarkRootFailed(N.RootSource);
    end
    else
    begin
      Inc(FProgressUnits);
      if N.TopLevel then Inc(FCompletedTopLevel);
    end;
  end
  else if A.IsDirectory(N.Source) then
  begin
    if A.Exists(N.Destination) then
    begin
      if not A.IsDirectory(N.Destination) then
      begin
        { Directory -> file type clash. Replace the colliding file, then use
          the same recursive path as a newly-created destination directory. }
        if not A.DeleteFile(N.Destination) or
           not A.CreateDirectory(N.Destination) then
        begin
          FErrors.Add('mkdir: '+N.Source+' -> '+N.Destination+
            ' - destination type clash could not be replaced');
          MarkRootFailed(N.RootSource);
        end
        else
        begin
          PushNode(N.Source,N.Destination,True,N.TopLevel,N.RootSource);
          if A.Enumerate(N.Source,E) then
            for I:=High(E) downto 0 do
              if (E[I].Name<>'.') and (E[I].Name<>'..') then
                PushNode(A.Join(N.Source,E[I].Name),
                  A.Join(N.Destination,E[I].Name),False,False,N.RootSource)
          else
          begin
            FErrors.Add('enumerate: '+N.Source+
              ' - directory could not be read');
            MarkRootFailed(N.RootSource);
          end;
        end;
      end
      else
      begin
        PushNode(N.Source,N.Destination,True,N.TopLevel,N.RootSource);
        if A.Enumerate(N.Source,E) then
          for I:=High(E) downto 0 do
            if (E[I].Name<>'.') and (E[I].Name<>'..') then
              PushNode(A.Join(N.Source,E[I].Name),
                A.Join(N.Destination,E[I].Name),False,False,N.RootSource)
        else
        begin
          FErrors.Add('enumerate: '+N.Source+' - directory could not be read');
          MarkRootFailed(N.RootSource);
        end;
      end;
    end
    else if A.CreateDirectory(N.Destination) then
    begin
      PushNode(N.Source,N.Destination,True,N.TopLevel,N.RootSource);
      if A.Enumerate(N.Source,E) then
        for I:=High(E) downto 0 do
          if (E[I].Name<>'.') and (E[I].Name<>'..') then
            PushNode(A.Join(N.Source,E[I].Name),
              A.Join(N.Destination,E[I].Name),False,False,N.RootSource)
      else
      begin
        FErrors.Add('enumerate: '+N.Source+' - directory could not be read');
        MarkRootFailed(N.RootSource);
      end;
    end
    else
    begin
      FErrors.Add('mkdir: '+N.Destination+' - directory could not be created');
      MarkRootFailed(N.RootSource);
    end;
  end
  else
  begin
    { The recursive stepper already computed the exact destination. Do not
      call Transfer() here: Transfer() recomputes the leaf from a destination
      DIRECTORY and follows a different conflict/planning path. That was the
      cause of flat-copy success while folder-copy leaves failed.

      TransferExactFile uses the exact destination and the same verified
      CopyFile primitive used by ordinary file operations. }
    Ok:=FOperations.TransferExactFile(N.Source,N.Destination,FOperation);
    if Ok then
    begin
      Inc(FProgressUnits);
      if N.TopLevel then Inc(FCompletedTopLevel);
    end
    else
    begin
      FErrors.Add('transfer: '+N.Source+' -> '+N.Destination+
        ' - exact file transfer failed verification');
      MarkRootFailed(N.RootSource);
    end;
  end;

  if FCancelRequested then
  begin
    FCancelled:=True;
    FSuccessful:=False;
    FQueueCount:=0;
    Exit(True);
  end;
  if FQueueCount=0 then
  begin
    FSuccessful:=(FErrors.Count=0);
    Result:=True;
  end;
end;

procedure TAFMTransferJob.Execute;
begin
  { Host fallback: run the same stepper to completion. AROS does not enter
    this path for provider-folder transfers; its UI idle loop calls Step. }
  while not Step do ;
end;

constructor TAFileManagerCommandTarget.CreateForController(
  AController: TAFileManagerController);
begin
  inherited Create;
  FController := AController;
end;

function TAFileManagerCommandTarget.CanHandleCommand(
  const ACommandId: TArosaCommandId): Boolean;
begin
  Result := (FController <> nil) and FController.CanRunCommandId(ACommandId);
end;

function TAFileManagerCommandTarget.ExecuteCommand(
  const ACommandId: TArosaCommandId; AContext: TArosaCommandContext): Boolean;
begin
  Result := (FController <> nil) and FController.RunCommandId(ACommandId);
end;

procedure TAFileManagerCommandTarget.QueryCommandState(
  const ACommandId: TArosaCommandId; var AEnabled, AVisible, AChecked: Boolean);
begin
  AEnabled := CanHandleCommand(ACommandId);
  AVisible := True;
  AChecked := False;
end;

constructor TAFileManagerWorkspaceBackground.Create;
begin
  inherited Create;
  FBitmap:=ArosaNilHandle;
  FSourceRect:=ArosaRectXYWH(0,0,0,0);
  FMode:='color';
  FColour1:=ArosaColour(32,36,44);
  FColour2:=ArosaColour(48,54,66);
  FColour3:=ArosaColour(64,72,88);
  FColour4:=ArosaColour(80,90,108);
  FDirection:='horizontal';
  FLayerOrder:='before';
  FOpacity:=100;
end;

function TAFileManagerWorkspaceBackground.InterpolatedColour(
  APosition, AMaximum: Integer): TArosaColour;
var Segment, LocalPos, LocalMax, Rv, Gv, Bv: Integer; A, B: TArosaColour;
  function Mix(AV, BV, P, M: Integer): Integer;
  begin if M<=0 then Exit(AV); Result:=AV+((BV-AV)*P div M); end;
begin
  if AMaximum<=0 then Exit(FColour1);
  if APosition<0 then APosition:=0 else if APosition>AMaximum then APosition:=AMaximum;
  Segment:=(APosition*3) div AMaximum; if Segment>2 then Segment:=2;
  LocalMax:=AMaximum;
  case Segment of
    0: begin A:=FColour1; B:=FColour2; LocalPos:=APosition*3; end;
    1: begin A:=FColour2; B:=FColour3; LocalPos:=APosition*3-AMaximum; end;
  else begin A:=FColour3; B:=FColour4; LocalPos:=APosition*3-(AMaximum*2); end;
  end;
  if LocalPos<0 then LocalPos:=0 else if LocalPos>LocalMax then LocalPos:=LocalMax;
  Rv:=Mix(ArosaColourRed(A),ArosaColourRed(B),LocalPos,LocalMax);
  Gv:=Mix(ArosaColourGreen(A),ArosaColourGreen(B),LocalPos,LocalMax);
  Bv:=Mix(ArosaColourBlue(A),ArosaColourBlue(B),LocalPos,LocalMax);
  Result:=ArosaColour(Byte(Rv),Byte(Gv),Byte(Bv));
end;

procedure TAFileManagerWorkspaceBackground.PaintLayer(
  ACanvas: TArosaCanvas; const R: TArosaRect);
var I, Count, W, H: Integer; Strip: TArosaRect; C: TArosaColour; Alpha: Byte;
begin
  if ACanvas=nil then Exit;
  if FOpacity<0 then FOpacity:=0 else if FOpacity>100 then FOpacity:=100;
  if FOpacity=0 then Exit;
  Alpha:=Byte((FOpacity*255) div 100);
  if not SameText(FMode,'gradient') then
  begin ArosaFillSurfaceRect(ACanvas,R,FColour1,Alpha); Exit; end;
  W:=ArosaCoordWhole(ArosaRectWidth(R)); H:=ArosaCoordWhole(ArosaRectHeight(R));
  if SameText(FDirection,'vertical') then
  begin
    Count:=H; if Count>128 then Count:=128; if Count<1 then Exit;
    for I:=0 to Count-1 do begin
      C:=InterpolatedColour(I,Count-1);
      Strip:=ArosaRectRaw(R.Left,R.Top+ArosaCoord((I*H) div Count),R.Right,
        R.Top+ArosaCoord(((I+1)*H) div Count));
      ArosaFillSurfaceRect(ACanvas,Strip,C,Alpha);
    end;
  end else begin
    Count:=W; if Count>128 then Count:=128; if Count<1 then Exit;
    for I:=0 to Count-1 do begin
      C:=InterpolatedColour(I,Count-1);
      Strip:=ArosaRectRaw(R.Left+ArosaCoord((I*W) div Count),R.Top,
        R.Left+ArosaCoord(((I+1)*W) div Count),R.Bottom);
      ArosaFillSurfaceRect(ACanvas,Strip,C,Alpha);
    end;
  end;
end;

procedure TAFileManagerWorkspaceBackground.PaintContent(ACanvas: TArosaCanvas);
var R: TArosaRect;
begin
  if ACanvas=nil then Exit;
  R:=ArosaRectXYWH(0,0,ArosaCoordWhole(ArosaRectWidth(Bounds)),ArosaCoordWhole(ArosaRectHeight(Bounds)));
  if SameText(FLayerOrder,'after') then begin
    if (FBitmap<>ArosaNilHandle) and (ArosaRectWidth(FSourceRect)>0) and (ArosaRectHeight(FSourceRect)>0) then
      ACanvas.DrawBitmap(FBitmap,FSourceRect,R);
    PaintLayer(ACanvas,R);
  end else begin
    PaintLayer(ACanvas,R);
    if (FBitmap<>ArosaNilHandle) and (ArosaRectWidth(FSourceRect)>0) and (ArosaRectHeight(FSourceRect)>0) then
      ACanvas.DrawBitmap(FBitmap,FSourceRect,R);
  end;
end;

constructor TAFileManagerWorkspacePrototype.CreateWorkspace(
  const APlatform: IArosaPlatform; AApplication: TArosaApplication;
  ATheme: TArosaTheme; AFonts: TArosaFontCache;
  AWorkspace: TArosaWorkspaceDefinition;
  AOwnerController: TAFileManagerController);
begin
  inherited Create;
  FPlatform:=APlatform;
  FApplication:=AApplication;
  { Never borrow the primary controller's mutable theme object.  A workspace
    controller must own an independent presentation graph or live theme changes
    in one workspace can partially recolour another. }
  if (AWorkspace<>nil) and SameText(AWorkspace.ThemeId,'Light') then
    FTheme:=ArosaCreateArosaLightTheme
  else
    FTheme:=ArosaCreateArosaDarkTheme;
  FFonts:=AFonts;
  if ATheme=nil then ; { retained ABI/source compatibility; intentionally unused }
  FWorkspace:=AWorkspace;
  FOwnerController:=AOwnerController;
  FScreen:=ArosaNilHandle;
  FBackgroundForm:=nil;
  FBackgroundHost:=nil;
  FBackgroundResource:=nil;
  FBackgroundSurface:=nil;
  FClosePending:=False;
  FCloseIdleAttached:=False;
  FCloseFinalizeAttached:=False;
end;

destructor TAFileManagerWorkspacePrototype.Destroy;
begin
  if (FApplication<>nil) and (FApplication.Loop<>nil) then
  begin
    if FCloseIdleAttached then
      FApplication.Loop.RemoveIdleHandler(@CloseIdle);
    if FCloseFinalizeAttached then
      FApplication.Loop.RemoveIdleHandler(@CloseFinalizeIdle);
  end;
  FCloseIdleAttached:=False;
  FCloseFinalizeAttached:=False;
  FClosePending:=False;
  Close;
  FreeAndNil(FTheme);
  FOwnerController:=nil;
  inherited Destroy;
end;

procedure TAFileManagerWorkspacePrototype.CloseRequested;
begin
  { Never free the workspace controller from inside its own close callback.
    Queue destruction to the following idle turn so the current controller
    stack has returned first. }
  if FClosePending then Exit;
  FClosePending:=True;
  if (FApplication<>nil) and (FApplication.Loop<>nil) and
     (not FCloseIdleAttached) then
  begin
    FApplication.Loop.AddIdleHandler(@CloseIdle);
    FCloseIdleAttached:=True;
  end
  else
  begin
    FClosePending:=False;
    Close;
    if FOwnerController<>nil then FOwnerController.WorkspacePrototypeClosed;
  end;
end;

procedure TAFileManagerWorkspacePrototype.CloseIdle(
  var AMoreWorkPending: Boolean);
begin
  if FCloseIdleAttached and (FApplication<>nil) and
     (FApplication.Loop<>nil) then
  begin
    FApplication.Loop.RemoveIdleHandler(@CloseIdle);
    FCloseIdleAttached:=False;
  end;

  { 0.15.5: phase 1 only closes native hosts.  A workspace close originates
    from a mouse/window event on the secondary host; freeing its controller,
    retained tree and screen in the same event/idle generation can leave
    queued native events pointing at freed state. }
  if (FController<>nil) then FController.UnbindNativeHost;
  if (FHost<>nil) and (not FHost.Closed) then FHost.Close;
  if (FBackgroundHost<>nil) and (not FBackgroundHost.Closed) then
    FBackgroundHost.Close;

  if (FApplication<>nil) and (FApplication.Loop<>nil) and
     (not FCloseFinalizeAttached) then
  begin
    FApplication.Loop.AddIdleHandler(@CloseFinalizeIdle);
    FCloseFinalizeAttached:=True;
    AMoreWorkPending:=True;
  end
  else
  begin
    CloseFinalizeIdle(AMoreWorkPending);
  end;
end;

procedure TAFileManagerWorkspacePrototype.CloseFinalizeIdle(
  var AMoreWorkPending: Boolean);
var
  S: IArosaScreenPlatform;
begin
  if FCloseFinalizeAttached and (FApplication<>nil) and
     (FApplication.Loop<>nil) then
    FApplication.Loop.RemoveIdleHandler(@CloseFinalizeIdle);
  FCloseFinalizeAttached:=False;
  FClosePending:=False;

  { phase 2: event handlers are already detached and the native windows have
    completed one event-loop turn closed, so owned retained objects/screens
    can now be destroyed. }
  S:=nil;
  if FPlatform<>nil then S:=FPlatform.Screens;
  FreeAndNil(FHost);
  FreeAndNil(FController);
  FreeAndNil(FForm);
  FreeAndNil(FBackgroundHost);
  FreeAndNil(FBackgroundForm);
  FBackgroundSurface:=nil;
  FreeAndNil(FBackgroundResource);
  if (S<>nil) and (FScreen<>ArosaNilHandle) then S.DestroyScreen(FScreen);
  FScreen:=ArosaNilHandle;

  if FOwnerController<>nil then FOwnerController.WorkspacePrototypeClosed;
  AMoreWorkPending:=False;
end;

{ 0.8.6.6: counted up whenever the modules of a workspace, or where they
  show, change.  Every file manager of this program (the primary one and one
  per open workspace screen) compares it in its idle turn and reads the
  catalogues again: a module added in one window appears in all of them. }
var
  GWorkspaceMembershipGeneration: Integer = 0;

{ ------------------------------------------------------------ taskbar }

constructor TAFileManagerTaskbar.CreateTaskbar(const APlatform: IArosaPlatform;
  AApplication: TArosaApplication; AFonts: TArosaFontCache;
  AController: TAFileManagerController; AScreen: TArosaPlatformHandle;
  const AWorkspaceId, AWorkspaceName: string);
begin
  inherited Create;
  FController:=AController;
  FShell:=TArosaWorkspaceShell.CreateShell(APlatform,AApplication,AFonts,
    AController.FTheme,AScreen,AWorkspaceId,AWorkspaceName,
    AController.FLauncherService,AController.FStartMenuService);
  FShell.SetVolumeNotices(AController.FVolumeNotices);
  FShell.Configure(True,True,True);
  FShell.OnLaunchTarget:=@ShellLaunch;
  FShell.OnOpenVolume:=@ShellOpenVolume;
  FShell.OnDiagnostic:=@ShellDiagnostic;
  FShell.OnText:=@ShellText;
end;

destructor TAFileManagerTaskbar.Destroy;
begin
  if FShell<>nil then
  begin
    { The shared shell stores method callbacks into this adapter.  Make the
      owner boundary explicit before either object is destroyed. }
    FShell.OnLaunchTarget:=nil;
    FShell.OnOpenVolume:=nil;
    FShell.OnDiagnostic:=nil;
    FShell.OnText:=nil;
    FShell.Shutdown;
  end;
  FController:=nil;
  FreeAndNil(FShell);
  inherited Destroy;
end;

function TAFileManagerTaskbar.Open: Boolean;
begin
  Result:=(FShell<>nil) and FShell.Open;
end;

procedure TAFileManagerTaskbar.Close;
begin
  if FShell<>nil then FShell.Close;
end;

function TAFileManagerTaskbar.IsOpen: Boolean;
begin
  Result:=(FShell<>nil) and FShell.IsOpen;
end;

procedure TAFileManagerTaskbar.BringToFront;
begin
  if FShell<>nil then FShell.BringToFront;
end;

function TAFileManagerTaskbar.GetTop: Integer;
begin
  if FShell=nil then Result:=0 else Result:=FShell.Top;
end;

procedure TAFileManagerTaskbar.Resync;
begin
  if FShell<>nil then
  begin
    if FController<>nil then
    begin
      FShell.SetTheme(FController.FTheme);
      FShell.SetServices(FController.FLauncherService,FController.FStartMenuService);
      FShell.SetVolumeNotices(FController.FVolumeNotices);
    end;
    FShell.Resync;
  end;
end;

procedure TAFileManagerTaskbar.ShellDiagnostic(ASender: TArosaObject;
  const AMessage: string);
begin
  if FController<>nil then FController.Diagnostic(AMessage);
  if ASender=nil then ;
end;

function TAFileManagerTaskbar.ShellText(ASender: TArosaObject;
  const AKey, AFallback: string): string;
begin
  if FController<>nil then Result:=FController.LocalText(AKey,AFallback)
  else Result:=AFallback;
  if ASender=nil then ;
end;

procedure TAFileManagerTaskbar.ShellOpenVolume(ASender: TArosaObject;
  const ATarget: string);
begin
  if FController<>nil then FController.OpenVolume(ATarget);
  if ASender=nil then ;
end;

procedure TAFileManagerTaskbar.ShellLaunch(ASender: TArosaObject;
  const ATarget: string);
var T: string;
begin
  T:=Trim(ATarget);
  if (T='') or (FController=nil) then Exit;
  if Pos('exec:',LowerCase(T))=1 then
  begin
    if FController.FShellService<>nil then
    begin
      FController.Diagnostic('WORKSPACE launch target='+Copy(T,6,MaxInt)+
        ' arguments='+StringReplace(FController.WorkspaceLaunchArguments,
          #10,' ',[rfReplaceAll]));
      FController.FShellService.LaunchIndependentArgs(Copy(T,6,MaxInt),
        FController.WorkspaceLaunchArguments);
    end;
    Exit;
  end;
  if Pos('internal:',LowerCase(T))=1 then Exit;
  if (Pos('arosa://',LowerCase(T))=1) or
     ((Length(T)>0) and ((T[Length(T)]=':') or (T[Length(T)]='/'))) then
  begin
    FController.FPendingNavigateView:=FController.FActiveView;
    FController.FPendingNavigatePath:=T;
    FController.FPendingNavigateActive:=True;
    if (FController.FNativeHost<>nil) and (not FController.FNativeHost.Closed) then
      FController.FNativeHost.Activate;
    Exit;
  end;
  FController.OpenAssociatedResource(T);
  if ASender=nil then ;
end;

function TAFileManagerTaskbar.TestPins: string;
begin
  if FShell=nil then Result:='' else Result:=FShell.TestPins;
end;

procedure TAFileManagerTaskbar.TestStep(AStep: Integer);
const Target = 'exec:AROSAApps:ASQLiteManager/ASQLiteManager';
begin
  if (FController=nil) or (FShell=nil) then Exit;
  case AStep of
    0: begin
         FController.RemoveStartMenuEntry(Target);
         FController.RemoveDesktopShortcut(Target);
         FController.Diagnostic('TEST common-workspace-shell taskbar-open='+
           BoolToStr(IsOpen,'TRUE','FALSE'));
         FShell.ToggleStartMenu;
       end;
    1: FController.Diagnostic('TEST common-workspace-shell menu-open='+
         BoolToStr(FShell.MenuOpen,'TRUE','FALSE')+' entries='+
         IntToStr(FShell.MenuEntryCount));
    2: begin
         FShell.ToggleStartMenu;
         FController.AddStartMenuEntry(Target);
         FController.AddDesktopShortcut(Target);
         FShell.Resync;
       end;
    3: FShell.ToggleStartMenu;
    4: begin
         FController.RemoveStartMenuEntry(Target);
         FController.RemoveDesktopShortcut(Target);
         FShell.Resync;
       end;
    10: FController.Diagnostic('TEST common-workspace-shell volumes resync');
    11: FShell.Resync;
  end;
end;

function TAFileManagerWorkspacePrototype.Open: Boolean;
var
  SI: TArosaScreenCreateInfo;
  ScreenBounds: TArosaRect;
  W, H: Integer;
  BGError: string;
begin
  Result:=False;
  if IsOpen then
  begin
    BringToFront;
    Exit(True);
  end;
  if (FPlatform=nil) or (FPlatform.Screens=nil) or
     (FApplication=nil) or (FWorkspace=nil) then Exit;

  FillChar(SI,SizeOf(SI),0);
  SI.Name:=FWorkspace.PreferredScreen;
  SI.Title:=FWorkspace.Name+' - AROSA';
  { 0.8.6.6: a public screen: the applications of the workspace open on it
    by name, whatever screen happens to be in front when they start }
  SI.PublicName:='AROSA.'+LowerCase(Trim(FWorkspace.Id));
  SI.LikeDefaultDesktop:=True;
  SI.Width:=FWorkspace.ScreenWidth;
  SI.Height:=FWorkspace.ScreenHeight;
  SI.Depth:=FWorkspace.ScreenDepth;
  FScreen:=FPlatform.Screens.CreateScreen(SI);
  if FScreen=ArosaNilHandle then Exit;

  ScreenBounds:=FPlatform.Screens.GetScreenBounds(FScreen);
  W:=ArosaCoordWhole(ArosaRectWidth(ScreenBounds));
  H:=ArosaCoordWhole(ArosaRectHeight(ScreenBounds));
  if W<480 then W:=480;
  if H<320 then H:=320;

  FForm:=TArosaForm.Create;
  FForm.Caption:='AFileManager - '+FWorkspace.Name;
  FForm.Resizable:=True;
  { Workspace screens use the same AROSA-owned window chrome as the primary
    AFileManager.  The native Intuition host is deliberately borderless;
    TArosaWindowFrame supplied by CreateManager owns the visible title bar,
    gadgets, resize behaviour and menu presentation.  The custom Intuition
    SCREEN title/depth controls remain available outside the window. }
  FForm.BorderStyle:=afbsNone;
  { Reserve a visible strip for the workspace taskbar. }
  FForm.WindowBounds:=ArosaRectXYWH(12,24,W-24,H-72);
  FForm.MinSize:=ArosaSize(640,420);

  FController:=TAFileManagerController.CreateManager(
    FPlatform,FForm,FTheme,FFonts,'',FWorkspace.Id);
  FController.ConfigureWorkspaceSession(FWorkspace.Id,@CloseRequested,
    FOwnerController);
  FController.FWorkspaceScreenName:=SI.PublicName;

  { Workspace background: solid colour or four-stop gradient, before or after
    the picture.  Before-image mode is the display-management equivalent of a
    screen background; after-image mode is a translucent custom overlay. }
  FBackgroundResource:=nil;
  BGError:='';
  if (Trim(FWorkspace.BackgroundImage)<>'') and (FController.FImageLoader<>nil) then
    if not FController.FImageLoader.TryLoadFile(FWorkspace.BackgroundImage,FBackgroundResource,BGError) then
    begin
      FBackgroundResource:=nil;
      FController.Diagnostic('WORKSPACE background image unavailable path='+FWorkspace.BackgroundImage+' error='+BGError);
    end;
  FBackgroundForm:=TArosaForm.Create;
  FBackgroundForm.Caption:=FWorkspace.Name+' - Background';
  FBackgroundForm.BorderStyle:=afbsNone;
  FBackgroundForm.Resizable:=False;
  FBackgroundForm.WindowBounds:=FPlatform.Screens.GetScreenClientBounds(FScreen);
  FBackgroundSurface:=TAFileManagerWorkspaceBackground.Create;
  FBackgroundSurface.SetTheme(FTheme,FFonts);
  FBackgroundSurface.Mode:=FWorkspace.BackgroundMode;
  FBackgroundSurface.Colour1:=FWorkspace.BackgroundColour1;
  FBackgroundSurface.Colour2:=FWorkspace.BackgroundColour2;
  FBackgroundSurface.Colour3:=FWorkspace.BackgroundColour3;
  FBackgroundSurface.Colour4:=FWorkspace.BackgroundColour4;
  FBackgroundSurface.Direction:=FWorkspace.BackgroundGradientDirection;
  FBackgroundSurface.LayerOrder:=FWorkspace.BackgroundLayerOrder;
  FBackgroundSurface.Opacity:=FWorkspace.BackgroundOpacity;
  if FBackgroundResource<>nil then begin
    FBackgroundSurface.Bitmap:=FBackgroundResource.Bitmap;
    FBackgroundSurface.SourceRect:=ArosaRectXYWH(0,0,FBackgroundResource.Width,FBackgroundResource.Height);
  end;
  FBackgroundSurface.SetConstraintWidth(asmStar,ArosaCoord(1));
  FBackgroundSurface.SetConstraintHeight(asmStar,ArosaCoord(1));
  FBackgroundForm.AddVisual(FBackgroundSurface);
  FBackgroundHost:=TArosaFormHost.Create(FApplication,FBackgroundForm);
  FBackgroundHost.TargetScreen:=FScreen;
  FBackgroundHost.CloseTerminatesApplication:=False;
  FBackgroundHost.Open;
  if (FPlatform.Windows<>nil) and (FBackgroundHost.Window<>ArosaNilHandle) then
    FPlatform.Windows.SendWindowToBack(FBackgroundHost.Window);

  FHost:=TArosaFormHost.Create(FApplication,FForm);
  FHost.TargetScreen:=FScreen;
  FHost.CloseTerminatesApplication:=False;
  FController.BindNativeHost(FHost);
  try
    FHost.Open;
    if (FBackgroundHost<>nil) and (FPlatform.Windows<>nil) and
       (FBackgroundHost.Window<>ArosaNilHandle) then
      FPlatform.Windows.SendWindowToBack(FBackgroundHost.Window);
    FController.OpenWorkspaceLocation(FWorkspace.Id);
    FPlatform.Screens.BringScreenToFront(FScreen);
    FHost.Activate;
    FController.OpenTaskbar(FScreen,FWorkspace.Name);
    Result:=True;
  except
    Close;
    raise;
  end;
end;

procedure TAFileManagerWorkspacePrototype.BringToFront;
begin
  if (FPlatform<>nil) and (FPlatform.Screens<>nil) and
     (FScreen<>ArosaNilHandle) then
    FPlatform.Screens.BringScreenToFront(FScreen);
  if (FHost<>nil) and (not FHost.Closed) then FHost.Activate;
  if Taskbar<>nil then Taskbar.BringToFront;
end;

procedure TAFileManagerWorkspacePrototype.Close;
var
  S: IArosaScreenPlatform;
begin
  S:=nil;
  if FPlatform<>nil then S:=FPlatform.Screens;
  { UnbindNativeHost closes the taskbar of the workspace with it }
  if FController<>nil then FController.UnbindNativeHost;
  FreeAndNil(FHost);
  FreeAndNil(FController);
  FreeAndNil(FForm);
  FreeAndNil(FBackgroundHost);
  FreeAndNil(FBackgroundForm);
  FBackgroundSurface:=nil;
  FreeAndNil(FBackgroundResource);
  if (S<>nil) and (FScreen<>ArosaNilHandle) then
    S.DestroyScreen(FScreen);
  FScreen:=ArosaNilHandle;
end;

function TAFileManagerWorkspacePrototype.IsOpen: Boolean;
begin
  Result:=(FScreen<>ArosaNilHandle) and (FHost<>nil) and
    (FController<>nil) and (not FHost.Closed);
end;

function TAFileManagerWorkspacePrototype.Controller: TAFileManagerController;
begin
  Result:=FController;
end;

function TAFileManagerWorkspacePrototype.Taskbar: TAFileManagerTaskbar;
begin
  if FController=nil then Result:=nil else Result:=FController.FTaskbar;
end;

function TAFileManagerWorkspacePrototype.WorkspaceId: string;
begin
  if FWorkspace=nil then Result:='' else Result:=FWorkspace.Id;
end;

constructor TFileManagerTabPage.CreateStyled(ATheme: TArosaTheme;
  const ACaption: string);
begin
  inherited Create;
  Caption := ACaption;
  { TArosaTabPage is a retained layout panel, not a TArosaControl.
    Styling is inherited from the themed child controls; the page itself
    only exposes a background role. }
  BackgroundRole := AROSA_ROLE_PANEL_BG;
end;

function SizeText(ASize: Int64): string;
begin
  if ASize < 1024 then Result := IntToStr(ASize) + ' B'
  else if ASize < 1024 * 1024 then Result := IntToStr(ASize div 1024) + ' KiB'
  else Result := IntToStr(ASize div (1024 * 1024)) + ' MiB';
end;



procedure TAFileManagerController.LoadLocalizationSpec(const ASpec: string);
var
  Candidates: array of string;
  Lang, Spec: string;

  procedure Add(const APath: string);
  begin
    SetLength(Candidates,Length(Candidates)+1);
    Candidates[High(Candidates)]:=APath;
  end;

  procedure AddLanguage(const ALang: string);
  var I: Integer; F: string;
  begin
    { Application catalogue first, shared AROSA catalogue second.  The
      Localization Service merges all existing candidates and preserves the
      first definition, so application text and reusable platform text remain
      cleanly separated without losing either family. }
    F:='text/afilemanager-'+ALang+'.txt';
    for I:=0 to FThemeLayers.Count-2 do Add(FThemeLayers.Root(I)+F);
    if FDescriptorBase<>'' then Add(FDescriptorBase+'localization/afilemanager-'+ALang+'.txt');
    Add(FThemeLayers.Root(FThemeLayers.Count-1)+F);

    F:='text/arosa-'+ALang+'.txt';
    for I:=0 to FThemeLayers.Count-2 do Add(FThemeLayers.Root(I)+F);
    Add(FThemeLayers.Root(FThemeLayers.Count-1)+F);
  end;
begin
  if FLocalization=nil then Exit;
  BuildThemeLayers;
  Spec:=Trim(ASpec);
  if Spec='' then Spec:='System';
  FActiveLanguageSpec:=Spec;
  Lang:=FLocalization.ResolveLanguage(Spec);
  Candidates:=nil;
  AddLanguage(Lang);
  if not SameText(Lang,'en') then AddLanguage('en');
  if FLocalization.LoadCatalog(Candidates,Spec) then
  begin
    Diagnostic('LOCALIZATION language='+FLocalization.Language+' layers: '+
      StringReplace(Trim(FLocalization.LoadedLayers.Text),LineEnding,'; ',[rfReplaceAll]));
    ArosaTrace('LOCALIZATION','language='+FLocalization.Language+' loaded='+FLocalization.LoadedPath);
  end
  else
  begin
    Diagnostic('LOCALIZATION no language file found; using English fallbacks');
    ArosaTrace('LOCALIZATION','no language file found; using English fallbacks');
  end;
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
end;

procedure TAFileManagerController.LoadLocalization;
var Spec: string;
begin
  Spec:='System';
  if FDescriptor<>nil then
  begin
    Spec:=Trim(FDescriptor.Value('Window','Language',''));
    if Spec='' then Spec:=Trim(FDescriptor.Value('Window','Localization','System'));
  end;
  LoadLocalizationSpec(Spec);
end;

function TAFileManagerController.LocalText(const AKey, AFallback: string): string;
begin
  if FLocalization=nil then Result:=AFallback
  else Result:=FLocalization.Text(AKey,AFallback);
end;

function TAFileManagerController.MetadataCaption(const ACaptionId: string): string;
begin
  { Resolve a metadata caption id from localization; return '' so the view
    falls back to its built-in / derived label when we have no entry. }
  Result := LocalText(ACaptionId, '');
end;

procedure TAFileManagerController.StopCurrentSound;
begin
  if FSoundService<>nil then FSoundService.StopAll;
  FCurrentSound:=nil;
  FAudioPath:='';
  FAudioDurationMS:=0;
  FAudioBasePositionMS:=0;
  FAudioRunTick:=0;
  FAudioLastTelemetryTick:=0;
  if FLeftAudioProgress<>nil then begin FLeftAudioProgress.Position:=0; FLeftAudioProgress.Visible:=False; end;
  if FRightAudioProgress<>nil then begin FRightAudioProgress.Position:=0; FRightAudioProgress.Visible:=False; end;
  if FMusicBars<>nil then begin FMusicBars.Stop; FMusicBars.ClearLevels; FMusicBars.Visible:=False; FMusicBars.InvalidateLayout; end;
  if FRightMusicBars<>nil then begin FRightMusicBars.Stop; FRightMusicBars.ClearLevels; FRightMusicBars.Visible:=False; FRightMusicBars.InvalidateLayout; end;
  if FLeftAudioHost<>nil then begin FLeftAudioHost.Visible:=False; FLeftAudioHost.InvalidateLayout; end;
  if FRightAudioHost<>nil then begin FRightAudioHost.Visible:=False; FRightAudioHost.InvalidateLayout; end;
end;

procedure TAFileManagerController.UpdateAudioPlaybackLabels;
var
  T: string;
  PosMS,Sec,MSec,DurSec,DurMSec: Int64;
begin
  PosMS:=CurrentAudioPositionMS;
  Sec:=PosMS div 1000; MSec:=PosMS mod 1000;
  DurSec:=FAudioDurationMS div 1000; DurMSec:=FAudioDurationMS mod 1000;

  if FCurrentSound=nil then T:='Playback: stopped'
  else if FCurrentSound.State=assPlaying then
    T:='Playback: running  '+IntToStr(Sec)+'.'+Format('%.3d',[MSec])+
      ' / '+IntToStr(DurSec)+'.'+Format('%.3d',[DurMSec])+' s'
  else
    T:='Playback: '+ArosaSoundStateName(FCurrentSound.State)+'  '+
      IntToStr(Sec)+'.'+Format('%.3d',[MSec])+
      ' / '+IntToStr(DurSec)+'.'+Format('%.3d',[DurMSec])+' s';

  if (FLeftAudioPlayback<>nil) and (FLeftAudioHost<>nil) and FLeftAudioHost.Visible then
    FLeftAudioPlayback.Text:=T;
  if (FRightAudioPlayback<>nil) and (FRightAudioHost<>nil) and FRightAudioHost.Visible then
    FRightAudioPlayback.Text:=T;
end;

function TAFileManagerController.CurrentAudioPositionMS: Int64;
begin
  Result:=FAudioBasePositionMS;
  if (FCurrentSound<>nil) and (FCurrentSound.State=assPlaying) and
     (FAudioRunTick<>0) then
    Result:=Result+Int64(GetTickCount64-FAudioRunTick);
  if Result<0 then Result:=0;
  if (FAudioDurationMS>0) and (Result>FAudioDurationMS) then
    Result:=FAudioDurationMS;
end;

procedure TAFileManagerController.UpdateAudioPlaybackTelemetry;
const TelemetryIntervalMS = 90;
var
  NowTick: QWord;
  PosMS: Int64;
  Info: TArosaAudioProbeInfo;
  Err: string;
  Levels: array[0..AROSA_AUDIO_SPECTRUM_BANDS-1] of Double;
  I: Integer;
  Bars: TArosaMusicBars;
  Progress: TArosaProgressBar;
begin
  if (FCurrentSound=nil) or (FAudioPath='') or (FAudioDurationMS<=0) then Exit;

  NowTick:=GetTickCount64;
  if (FAudioLastTelemetryTick<>0) and
     (NowTick-FAudioLastTelemetryTick<TelemetryIntervalMS) then Exit;
  FAudioLastTelemetryTick:=NowTick;

  PosMS:=CurrentAudioPositionMS;
  if FAudioPreviewView=0 then
  begin
    Bars:=FMusicBars; Progress:=FLeftAudioProgress;
  end
  else
  begin
    Bars:=FRightMusicBars; Progress:=FRightAudioProgress;
  end;

  if Progress<>nil then
  begin
    Progress.Maximum:=Integer(FAudioDurationMS);
    Progress.Position:=Integer(PosMS);
    Progress.Visible:=True;
    Progress.InvalidatePaint;
  end;

  { This samples the PCM window at the same logical playback position.  The
    moving bars therefore prove that AFileManager is advancing through the
    selected audio data, not merely displaying a static whole-file spectrum. }
  if (Bars<>nil) and ArosaProbeAudioAtPosition(FAudioPath,PosMS,Info,Err) and
     Info.SpectrumValid then
  begin
    for I:=0 to AROSA_AUDIO_SPECTRUM_BANDS-1 do Levels[I]:=Info.Spectrum[I];
    Bars.SetLevels(Levels);
    Bars.Visible:=True;
    Bars.InvalidatePaint;
  end;

  UpdateAudioPlaybackLabels;

  { sound.datatype provides no portable completion callback here, so the file
    duration is the authoritative preview clock. }
  if (FCurrentSound.State=assPlaying) and (PosMS>=FAudioDurationMS) then
  begin
    FCurrentSound.Stop;
    FAudioBasePositionMS:=FAudioDurationMS;
    FAudioRunTick:=0;
    UpdateAudioPlaybackLabels;
  end;
end;

procedure TAFileManagerController.AudioPlayClick(ASender: TArosaControl);
begin
  if FCurrentSound<>nil then
  begin
    if FCurrentSound.State=assPaused then
    begin
      if FCurrentSound.Resume then FAudioRunTick:=GetTickCount64;
    end
    else if FCurrentSound.Play(False) then
    begin
      if FAudioBasePositionMS>=FAudioDurationMS then FAudioBasePositionMS:=0;
      FAudioRunTick:=GetTickCount64;
    end;
    FAudioLastTelemetryTick:=0;
    UpdateAudioPlaybackTelemetry;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.AudioPauseClick(ASender: TArosaControl);
begin
  if FCurrentSound<>nil then
  begin
    FAudioBasePositionMS:=CurrentAudioPositionMS;
    if FCurrentSound.Pause then FAudioRunTick:=0;
    FAudioLastTelemetryTick:=0;
    UpdateAudioPlaybackTelemetry;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.AudioStopClick(ASender: TArosaControl);
begin
  if FCurrentSound<>nil then
  begin
    FCurrentSound.Stop;
    FAudioBasePositionMS:=0;
    FAudioRunTick:=0;
    FAudioLastTelemetryTick:=0;
    UpdateAudioPlaybackTelemetry;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.AudioRewindClick(ASender: TArosaControl);
begin
  if FCurrentSound<>nil then
  begin
    FCurrentSound.Rewind;
    FAudioBasePositionMS:=CurrentAudioPositionMS-5000;
    if FAudioBasePositionMS<0 then FAudioBasePositionMS:=0;
    if FCurrentSound.State=assPlaying then FAudioRunTick:=GetTickCount64 else FAudioRunTick:=0;
    FAudioLastTelemetryTick:=0;
    UpdateAudioPlaybackTelemetry;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.AudioForwardClick(ASender: TArosaControl);
begin
  if FCurrentSound<>nil then
  begin
    FCurrentSound.FastForward;
    FAudioBasePositionMS:=CurrentAudioPositionMS+5000;
    if (FAudioDurationMS>0) and (FAudioBasePositionMS>FAudioDurationMS) then
      FAudioBasePositionMS:=FAudioDurationMS;
    if FCurrentSound.State=assPlaying then FAudioRunTick:=GetTickCount64 else FAudioRunTick:=0;
    FAudioLastTelemetryTick:=0;
    UpdateAudioPlaybackTelemetry;
  end;
  if ASender=nil then ;
end;

function TAFileManagerController.LocalValue(const AValue, AFallback: string): string;
var
  V: string;
begin
  V := Trim(AValue);
  if (V<>'') and (V[1]='@') then
    Result := LocalText(Copy(V,2,MaxInt), AFallback)
  else if V<>'' then
    Result := V
  else
    Result := AFallback;
end;

function TAFileManagerController.DescriptorValue(AList: TStringList;
  const AKey, ADefault: string): string;
var
  V: string;
begin
  if AList=nil then Exit(ADefault);
  V := Trim(AList.Values[AKey]);
  if V='' then Result:=ADefault else Result:=V;
end;

function TAFileManagerController.DescriptorBool(AList: TStringList;
  const AKey: string; ADefault: Boolean): Boolean;
var
  V: string;
begin
  V := LowerCase(DescriptorValue(AList,AKey,''));
  if V='' then Exit(ADefault);
  Result := (V='true') or (V='yes') or (V='1') or (V='on');
end;

function TAFileManagerController.HandlerForCommand(
  const ACommand: string): TArosaClickEvent;
var
  C: string;
begin
  C := LowerCase(Trim(ACommand));
  Result := nil;
  if (C='file.refresh') or (C='navigation.refresh') then Result:=@RefreshClick
  else if C='file.createfolder' then Result:=@CreateFolderClick
  else if C='file.createfile' then Result:=@CreateFileClick
  else if C='file.rename' then Result:=@RenameClick
  else if C='file.copy' then Result:=@CopyClick
  else if C='file.cut' then Result:=@CutClick
  else if C='file.paste' then Result:=@PasteClick
  else if C='file.delete' then Result:=@DeleteClick
  else if (C='file.undo') or (C='history.undo') then Result:=@UndoClick
  else if (C='file.redo') or (C='history.redo') then Result:=@RedoClick
  else if (C='operations.console') or (C='console.commands') then Result:=@ConsoleClick
  else if C='console.openhere' then Result:=@OpenConsoleHereClick
  else if C='console.new' then Result:=@ConsoleOperationNewClick
  else if C='console.clear' then Result:=@ConsoleOperationClearClick
  else if C='console.close' then Result:=@ConsoleOperationCloseClick
  else if C='console.search' then Result:=@ConsoleSearchClick
  else if C='console.wrap' then Result:=@ConsoleWrapClick
  else if C='console.columns' then Result:=@ConsoleColumnsClick
  else if C='console.columnless' then Result:=@ConsoleColumnLessClick
  else if C='console.columnmore' then Result:=@ConsoleColumnMoreClick
  else if C='console.fontsmaller' then Result:=@ConsoleFontSmallerClick
  else if C='console.fontlarger' then Result:=@ConsoleFontLargerClick
  else if C='view.console.wrap' then Result:=@ConsoleWrapClick
  else if C='view.console.columns' then Result:=@ConsoleColumnsClick
  else if C='view.console.columnless' then Result:=@ConsoleColumnLessClick
  else if C='view.console.columnmore' then Result:=@ConsoleColumnMoreClick
  else if C='view.console.fontsmaller' then Result:=@ConsoleFontSmallerClick
  else if C='view.console.fontlarger' then Result:=@ConsoleFontLargerClick
  else if C='view.console.new' then Result:=@ConsoleOperationNewClick
  else if C='view.console.close' then Result:=@ConsoleOperationCloseClick
  else if C='buffers.console.new' then Result:=@ConsoleOperationNewClick
  else if C='buffers.console.close' then Result:=@ConsoleOperationCloseClick
  else if C='buffers.console.clear' then Result:=@ConsoleOperationClearClick
  else if C='commands.console.clear' then Result:=@ConsoleOperationClearClick
  else if C='commands.console.search' then Result:=@ConsoleSearchClick
  else if C='search.console.search' then Result:=@ConsoleSearchClick
  else if C='commands.console.wrap' then Result:=@ConsoleWrapClick
  else if C='history.console.previous' then Result:=@ConsoleHistoryPreviousClick
  else if C='history.console.next' then Result:=@ConsoleHistoryNextClick
  else if C='sessions.console.new' then Result:=@ConsoleOperationNewClick
  else if C='sessions.console.close' then Result:=@ConsoleOperationCloseClick
  else if C='environment.console.info' then Result:=@ConsoleEnvironmentInfoClick
  else if (C='operations.arexx') or (C='arexx.execute') then Result:=@ARexxClick
  else if (C='operations.macros') or (C='macros.execute') then Result:=@MacrosClick
  else if C='resource.metadata' then Result:=@ShowResourceMetadataClick
  else if C='file.execute' then Result:=@ExecuteScriptClick
  else if C='file.exit' then Result:=@ExitClick
  else if C='navigation.up' then Result:=@UpClick
  else if C='navigation.back' then Result:=@BackClick
  else if C='navigation.forward' then Result:=@ForwardClick
  else if (C='navigation.swap') or (C='view.swap') then Result:=@SwapViewsClick
  else if C='selection.all' then Result:=@SelectAllClick
  else if C='selection.none' then Result:=@ClearSelectionClick
  else if (C='view.dualpane') or (C='view.splitview') then Result:=@ToggleSplitClick
  else if C='view.newfilemanager' then Result:=@NewFileManagerClick
  else if C='view.closefilemanager' then Result:=@CloseFileManagerClick
  else if C='view.toolbar' then Result:=@ToggleToolbarClick
  else if (C='view.operations') or (C='view.filepanel') then Result:=@ToggleOperationsClick
  else if C='view.preview' then Result:=@TogglePreviewClick
  else if C='view.metadata' then Result:=@ShowMetadataClick
  else if C='view.placesdetails' then Result:=@TogglePlacesDetailClick
  else if C='view.hidden' then Result:=@ToggleHiddenFilesClick
  else if C='view.thumbnails' then Result:=@ToggleThumbnailsClick
  else if C='theme.dark' then Result:=@ThemeDarkClick
  else if C='theme.light' then Result:=@ThemeLightClick
  else if C='view.list' then Result:=@ViewListClick
  else if C='view.details' then Result:=@ViewDetailsClick
  else if C='view.icons' then Result:=@ViewIconsClick
  else if C='view.windows' then Result:=@ViewWindowsClick
  else if C='configuration.settings' then Result:=@ConfigurationClick
  else if C='help.contents' then Result:=@HelpContentsClick
  else if (C='help.info') or (C='help.about') then Result:=@InfoClick;
end;

procedure TAFileManagerController.BuildMenuPanel(
  APanel: TArosaColumnPanel; ADescriptor: TStringList);
var
  I, EqPos: Integer;
  Key, Caption: string;
  H: TArosaClickEvent;
  B: TArosaButton;
begin
  if (APanel=nil) or (ADescriptor=nil) then Exit;
  APanel.Spacing:=ArosaCoord(1);
  for I:=0 to ADescriptor.Count-1 do
  begin
    Key:=Trim(ADescriptor[I]);
    if (Key='') or (Key[1]=';') or (Key[1]='#') then Continue;
    EqPos:=Pos('=',Key);
    if EqPos<=1 then Continue;
    Caption:=Trim(Copy(Key,EqPos+1,MaxInt));
    Key:=Trim(Copy(Key,1,EqPos-1));
    Caption:=LocalValue(Caption,Key);
    H:=HandlerForCommand(Key);
    if not Assigned(H) then Continue;
    B:=NewButton(APanel,Caption,Key,H,220);
    B.SetConstraintHeight(asmFixed,ArosaCoord(23));
    if LowerCase(Key)='view.preview' then FPreviewMenuButton:=B;
  end;
end;


procedure TAFileManagerController.ClearSubMenu;
begin
  if FMenuSubPanel=nil then Exit;
  FMenuSubPanel.ClearVisuals;
  FMenuSubPanel.Visible:=False;
  FMenuPanel.SetConstraintWidth(asmFixed,ArosaCoord(150));
end;

procedure TAFileManagerController.BuildRootMenu;
var TrailingSep: TArosaVisual;
begin
  if (FMenuRootPanel=nil) or (FMenuSubPanel=nil) then Exit;
  FMenuMode:=0;
  FMenuRootPanel.ClearVisuals;
  FMenuRootPanel.Spacing:=ArosaCoord(0);
  if (FMenuDescriptor.IndexOfName('Theme.Dark')>=0) or (FMenuDescriptor.IndexOfName('Theme.Light')>=0) then
    NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_theme','Theme')+'  >','Theme submenu',@MenuThemeClick,148,'Theme');
  if FMenuDescriptor.IndexOfName('View.Preview')>=0 then
    NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_panels','Panels')+'  >','Panel placement submenu',@MenuPreviewClick,148,'View.Preview');
  { 0.5.110.16: groups - appearance | panels shown | split/sync }
  NewMenuSeparator(FMenuRootPanel,148);
  if (FMenuDescriptor.IndexOfName('View.Toolbar')>=0) and (FDescriptor<>nil) and FDescriptor.BoolValue('Capabilities','Toolbar',False) then
  begin
    if (FWindowFrame<>nil) and FWindowFrame.ToolbarVisible then
      NewMenuItem(FMenuRootPanel,'[x] Toolbar','Show or hide the toolbar',@ToggleToolbarClick,148,'View.Toolbar')
    else
      NewMenuItem(FMenuRootPanel,'[ ] Toolbar','Show or hide the toolbar',@ToggleToolbarClick,148,'View.Toolbar');
  end;
  if (FMenuDescriptor.IndexOfName('View.Operations')>=0) and (FDescriptor<>nil) and
     (FDescriptor.BoolValue('Capabilities','Operations',False) or
      FDescriptor.BoolValue('Capabilities','FileOperations',False)) then
  begin
    if (FWindowFrame<>nil) and FWindowFrame.FilePanelVisible then
      NewMenuItem(FMenuRootPanel,'[x] Operations','Show or hide the operations panel',@ToggleOperationsClick,148,'View.Operations')
    else
      NewMenuItem(FMenuRootPanel,'[ ] Operations','Show or hide the operations panel',@ToggleOperationsClick,148,'View.Operations');
  end;
  if (FMenuDescriptor.IndexOfName('View.SplitView')>=0) and (FDescriptor<>nil) and FDescriptor.BoolValue('Capabilities','SplitView',False) then
  begin
    NewMenuSeparator(FMenuRootPanel,148);
    if (FWindowFrame<>nil) and FWindowFrame.SplitView then
    begin
      NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_split_checked','[x] Split view'),
        'Show or hide the second location pane',@ToggleSplitClick,148,'View.SplitView');
      NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_new_file_manager','New file manager'),
        LocalText('afilemanager_hint_new_file_manager','Open another file manager in the second view (Ctrl+T)'),
        @NewFileManagerClick,148,'View.NewFileManager');
      if (FSurfaces<>nil) and (FSurfaces.Count>1) then
        NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_close_file_manager','Close file manager'),
          LocalText('afilemanager_hint_close_file_manager','Close the file manager shown in the second view (Ctrl+W)'),
          @CloseFileManagerClick,148,'View.CloseFileManager');
    end
    else
      NewMenuItem(FMenuRootPanel,LocalText('afilemanager_menu_split_unchecked','[ ] Split view'),
        'Show or hide the second location pane',@ToggleSplitClick,148,'View.SplitView');
    if FMenuDescriptor.IndexOfName('View.SyncScrolling')>=0 then begin
    if FSyncScrolling then
      NewMenuItem(FMenuRootPanel,'[x] Sync scrolling','Keep both file lists at the same vertical position',@ToggleSyncScrollingClick,148,'View.SyncScrolling')
    else
      NewMenuItem(FMenuRootPanel,'[ ] Sync scrolling','Keep both file lists at the same vertical position',@ToggleSyncScrollingClick,148,'View.SyncScrolling');
    end;
    if FMenuDescriptor.IndexOfName('View.SyncWindows')>=0 then begin
    if FSyncWindows then
      NewMenuItem(FMenuRootPanel,'[x] Sync windows','Align both preview splitters',@ToggleSyncWindowsClick,148,'View.SyncWindows')
    else
      NewMenuItem(FMenuRootPanel,'[ ] Sync windows','Align both preview splitters',@ToggleSyncWindowsClick,148,'View.SyncWindows');
    end;
  end;
  { Application services.  These entries remain descriptor-authoritative: if
    a command is absent from [Menu], it does not appear in the burger menu. }
  if (FMenuDescriptor.IndexOfName('Configuration.Settings')>=0) or
     (FMenuDescriptor.IndexOfName('Help.Contents')>=0) or
     (FMenuDescriptor.IndexOfName('Help.Info')>=0) or
     (FMenuDescriptor.IndexOfName('Help.About')>=0) then
    NewMenuSeparator(FMenuRootPanel,148);
  if FMenuDescriptor.IndexOfName('Configuration.Settings')>=0 then
    NewMenuItem(FMenuRootPanel,
      LocalValue(FMenuDescriptor.Values['Configuration.Settings'],'Configuration'),
      'Configure AFileManager',@ConfigurationClick,148,'Configuration.Settings');
  if FMenuDescriptor.IndexOfName('Help.Contents')>=0 then
    NewMenuItem(FMenuRootPanel,
      LocalValue(FMenuDescriptor.Values['Help.Contents'],'Help'),
      'Open AFileManager help',@HelpContentsClick,148,'Help.Contents');
  if FMenuDescriptor.IndexOfName('Help.Info')>=0 then
    NewMenuItem(FMenuRootPanel,
      LocalValue(FMenuDescriptor.Values['Help.Info'],'Info'),
      'AFileManager build and configuration information',@InfoClick,148,'Help.Info')
  else if FMenuDescriptor.IndexOfName('Help.About')>=0 then
    NewMenuItem(FMenuRootPanel,
      LocalValue(FMenuDescriptor.Values['Help.About'],'Info'),
      'AFileManager build and configuration information',@InfoClick,148,'Help.About');
  { drop a trailing divider left by an empty group }
  if (FMenuRootPanel.ChildVisualCount>0) and
     (FMenuRootPanel.ChildVisuals[FMenuRootPanel.ChildVisualCount-1] is TArosaMenuSeparator) then
  begin
    TrailingSep:=FMenuRootPanel.ChildVisuals[FMenuRootPanel.ChildVisualCount-1];
    FMenuRootPanel.RemoveVisual(TrailingSep);
    TrailingSep.Free;
  end;
  ClearSubMenu;
end;

procedure TAFileManagerController.BuildThemeMenu;
begin
  if FMenuSubPanel=nil then Exit;
  FMenuMode:=1;
  FMenuSubPanel.ClearVisuals;
  FMenuSubPanel.Spacing:=ArosaCoord(0);
  if FMenuDescriptor.IndexOfName('Theme.Dark')>=0 then NewMenuItem(FMenuSubPanel,LocalText('afilemanager_menu_dark','Dark'),'Dark theme',@ThemeDarkClick,148,'Theme.Dark');
  if FMenuDescriptor.IndexOfName('Theme.Light')>=0 then NewMenuItem(FMenuSubPanel,LocalText('afilemanager_menu_light','Light'),'Light theme',@ThemeLightClick,148,'Theme.Light');
  FMenuSubPanel.Visible:=True;
  FMenuPanel.SetConstraintWidth(asmFixed,ArosaCoord(300));
  FMenuPanel.InvalidateLayout;
end;

procedure TAFileManagerController.BuildPreviewMenu;
begin
  if FMenuSubPanel=nil then Exit;
  FMenuMode:=2;
  FMenuSubPanel.ClearVisuals;
  FMenuSubPanel.Spacing:=ArosaCoord(0);
  if FMenuDescriptor.IndexOfName('View.PreviewRight')>=0 then
    if FPreviewPreferredPlacement=1 then
      NewMenuItem(FMenuSubPanel,'[x] '+LocalText('afilemanager_menu_preview_right','Right side'),'Preview right',@PreviewRightClick,148,'View.PreviewRight')
    else
      NewMenuItem(FMenuSubPanel,'[ ] '+LocalText('afilemanager_menu_preview_right','Right side'),'Preview right',@PreviewRightClick,148,'View.PreviewRight');
  if FMenuDescriptor.IndexOfName('View.PreviewBottom')>=0 then
    if FPreviewPreferredPlacement=2 then
      NewMenuItem(FMenuSubPanel,'[x] '+LocalText('afilemanager_menu_preview_bottom','Bottom'),'Preview bottom',@PreviewBottomClick,148,'View.PreviewBottom')
    else
      NewMenuItem(FMenuSubPanel,'[ ] '+LocalText('afilemanager_menu_preview_bottom','Bottom'),'Preview bottom',@PreviewBottomClick,148,'View.PreviewBottom');
  FMenuSubPanel.Visible:=True;
  FMenuPanel.SetConstraintWidth(asmFixed,ArosaCoord(300));
  FMenuPanel.InvalidateLayout;
end;

procedure TAFileManagerController.MenuBackClick(ASender: TArosaControl);
begin ClearSubMenu; end;
procedure TAFileManagerController.MenuThemeClick(ASender: TArosaControl);
begin BuildThemeMenu; end;
procedure TAFileManagerController.MenuPreviewClick(ASender: TArosaControl);
begin BuildPreviewMenu; end;

procedure TAFileManagerController.PopulateConfigurationChoices;
var
  Entries: TArosaFileInfoArray;
  Descriptors, Profiles, Languages, Themes: array of string;
  D,P,G,T: TStringList;
  I: Integer;

  procedure CollectThemes(const ARoot: string);
  var J: Integer;
  begin
    if (FPaths=nil) or not FPaths.Enumerate(ARoot,Entries) then Exit;
    for J:=0 to High(Entries) do
      if (Entries[J].Kind=afekDirectory) and
         (Trim(Entries[J].Name)<>'') and (T.IndexOf(Entries[J].Name)<0) then
        T.Add(Entries[J].Name);
  end;

  procedure CollectLanguages(const ALocation: string);
  var
    J: Integer;
    N, LangId: string;
  begin
    if (FPaths=nil) or not FPaths.Enumerate(ALocation,Entries) then Exit;
    for J:=0 to High(Entries) do
      if Entries[J].Kind=afekFile then
      begin
        N:=LowerCase(Entries[J].Name);
        if (Copy(N,1,13)='afilemanager-') and
           SameText(ExtractFileExt(N),'.txt') then
        begin
          LangId:=Copy(N,14,Length(N)-13-4);
          if (LangId<>'') and (G.IndexOf(LangId)<0) then G.Add(LangId);
        end;
      end;
  end;
begin
  if FConfigurationDialog=nil then Exit;
  D:=TStringList.Create; P:=TStringList.Create; G:=TStringList.Create; T:=TStringList.Create;
  try
    if (FPaths<>nil) and FPaths.Enumerate('PROGDIR:descriptors',Entries) then
      for I:=0 to High(Entries) do
        if (Entries[I].Kind=afekFile) and SameText(ExtractFileExt(Entries[I].Name),'.window') then
          D.Add('descriptors/'+Entries[I].Name);
    if (FPaths<>nil) and FPaths.Enumerate('PROGDIR:configurations',Entries) then
      for I:=0 to High(Entries) do
        if (Entries[I].Kind=afekFile) and SameText(ExtractFileExt(Entries[I].Name),'.user') then
          P.Add('configurations/'+Entries[I].Name);
    CollectThemes('PROGDIR:themes');
    if (FDescriptorBase<>'') and (not SameText(FDescriptorBase,'PROGDIR:')) then
      CollectThemes(FDescriptorBase+'themes');
    CollectThemes('SYS:Arosa/themes');
    if T.IndexOf('default')<0 then T.Add('default');
    T.Sort;
    for I:=0 to T.Count-1 do
    begin
      CollectLanguages('PROGDIR:themes/'+T[I]+'/text');
      if (FDescriptorBase<>'') and (not SameText(FDescriptorBase,'PROGDIR:')) then
        CollectLanguages(FDescriptorBase+'themes/'+T[I]+'/text');
      CollectLanguages('SYS:Arosa/themes/'+T[I]+'/text');
    end;
    CollectLanguages('PROGDIR:text');
    D.Sort; P.Sort; G.Sort;
    SetLength(Descriptors,D.Count);
    for I:=0 to D.Count-1 do Descriptors[I]:=D[I];
    SetLength(Profiles,P.Count);
    for I:=0 to P.Count-1 do Profiles[I]:=P[I];
    SetLength(Languages,G.Count);
    for I:=0 to G.Count-1 do Languages[I]:=G[I];
    FConfigurationDialog.SetStartupOptions(Descriptors,Profiles);
    SetLength(Themes,T.Count);
    for I:=0 to T.Count-1 do Themes[I]:=T[I];
    FConfigurationDialog.SetThemeOptions(Themes);
    FConfigurationDialog.SetLanguageOptions(Languages);
  finally
    D.Free; P.Free; G.Free; T.Free;
  end;
end;

procedure TAFileManagerController.LoadColumnConfigurationFromDescriptor;
const
  DEFAULT_ORDER =
    'resource.thumbnail,resource.type,resource.name,resource.size,'+
    'resource.modified,resource.permissions';
var
  S: string;
  I: Integer;

  procedure EnsureId(AList: TStringList; const AId: string);
  begin
    if AList.IndexOf(AId)<0 then AList.Add(AId);
  end;

begin
  if FColumnOrder=nil then FColumnOrder:=TStringList.Create;
  if FVisibleColumns=nil then FVisibleColumns:=TStringList.Create;

  FColumnOrder.CaseSensitive:=False;
  FVisibleColumns.CaseSensitive:=False;
  FColumnOrder.StrictDelimiter:=True;
  FVisibleColumns.StrictDelimiter:=True;
  FColumnOrder.Delimiter:=',';
  FVisibleColumns.Delimiter:=',';

  S:=FDescriptor.Value('FileView','ColumnOrder',DEFAULT_ORDER);
  if Trim(S)='' then S:=DEFAULT_ORDER;
  FColumnOrder.DelimitedText:=S;

  S:=FDescriptor.Value('FileView','VisibleColumns','');
  if Trim(S)='' then
  begin
    S:='resource.type,resource.name,resource.size,resource.modified,'+
       'resource.permissions';
    if FDescriptor.BoolValue('FileView','ShowThumbnails',True) then
      S:='resource.thumbnail,'+S;
  end;
  FVisibleColumns.DelimitedText:=S;

  EnsureId(FColumnOrder,'resource.thumbnail');
  EnsureId(FColumnOrder,'resource.type');
  EnsureId(FColumnOrder,'resource.name');
  EnsureId(FColumnOrder,'resource.size');
  EnsureId(FColumnOrder,'resource.modified');
  EnsureId(FColumnOrder,'resource.permissions');

  { Name remains the stable identity column. }
  EnsureId(FVisibleColumns,'resource.name');

  FShowThumbnails:=FVisibleColumns.IndexOf('resource.thumbnail')>=0;
  FDefaultSortColumn:=
    FDescriptor.Value('FileView','DefaultSortColumn','resource.name');
  if Trim(FDefaultSortColumn)='' then FDefaultSortColumn:='resource.name';
  FDefaultSortAscending:=
    FDescriptor.BoolValue('FileView','DefaultSortAscending',True);

  { Drop unknown duplicate/empty order entries without changing first occurrence. }
  I:=FColumnOrder.Count-1;
  while I>=0 do
  begin
    if Trim(FColumnOrder[I])='' then FColumnOrder.Delete(I);
    Dec(I);
  end;
end;

function TAFileManagerController.IsConfiguredColumnVisible(
  const AId: string): Boolean;
begin
  Result:=(FVisibleColumns<>nil) and (FVisibleColumns.IndexOf(AId)>=0);
end;

function TAFileManagerController.ColumnOrderText: string;
begin
  if FColumnOrder=nil then Result:='' else Result:=FColumnOrder.CommaText;
end;

function TAFileManagerController.VisibleColumnsText: string;
begin
  if FVisibleColumns=nil then Result:='' else Result:=FVisibleColumns.CommaText;
end;

function TAFileManagerController.CurrentConfigurationSettings: TAFMConfigurationSettings;
var Shortcuts: TStringList;
begin
  { Every field is assigned below; ThemeId is a managed string. }
  Result.ThemeId:=FActiveThemeId;
  Result.ThemePackageId:=FActiveThemePackageId;
  if Result.ThemePackageId='' then Result.ThemePackageId:='default';
  Result.InterfaceLanguage:=Trim(FActiveLanguageSpec);
  if Result.InterfaceLanguage='' then Result.InterfaceLanguage:='System';
  if FWindowFrame<>nil then
  begin
    Result.ToolbarVisible:=FWindowFrame.ToolbarVisible;
    Result.OperationsVisible:=FWindowFrame.FilePanelVisible;
    Result.SplitView:=FWindowFrame.SplitView;
  end;
  Result.PreviewVisible:=FPreviewVisible;
  Result.EditorRenditionVisible:=FEditorRenditionVisible;
  Result.MetadataVisible:=FMetadataVisible;
  Result.ConfirmDeletion:=FConfirmDeletion;
  Result.DragSameVolume:=FDragSameVolume;
  Result.DragOtherVolume:=FDragOtherVolume;
  Result.LoggingEnabled:=FConfiguredLoggingEnabled;
  Result.LoggingLevel:=FConfiguredLoggingLevel;
  if Trim(Result.LoggingLevel)='' then Result.LoggingLevel:='Info';
  Result.ShowThumbnails:=FShowThumbnails;
  Result.ThumbnailSize:=FThumbnailSize;
  Result.ColumnOrder:=ColumnOrderText;
  Result.VisibleColumns:=VisibleColumnsText;
  if (ViewList(FActiveView)<>nil) and
     (Trim(ViewList(FActiveView).SortColumnId)<>'') then
  begin
    Result.DefaultSortColumn:=ViewList(FActiveView).SortColumnId;
    Result.DefaultSortAscending:=ViewList(FActiveView).SortAscending;
  end
  else
  begin
    Result.DefaultSortColumn:=FDefaultSortColumn;
    Result.DefaultSortAscending:=FDefaultSortAscending;
  end;
  Result.IconSize:=FFileIconSize;
  Result.RowPadding:=FFileRowPadding;
  Result.IconTextGap:=FFileIconTextGap;
  if FLeftViewMode=3 then Result.DefaultViewMode:='Windows'
  else if FLeftViewMode=2 then Result.DefaultViewMode:='Icons'
  else if FLeftViewMode=0 then Result.DefaultViewMode:='List'
  else Result.DefaultViewMode:='Details';
  if FDescriptor<>nil then
  begin
    Result.DefaultDescriptor:=FDescriptor.Value('Descriptor','Inherits','descriptors/AFileManager.release.window');
    Result.UserProfile:=WorkspaceUserConfigurationPath(FActiveWorkspaceId);
    Result.UIFontFamily:=FDescriptor.Value('Fonts','UIFamily','JetBrains Mono');
    Result.UIFontSize:=FDescriptor.IntValue('Fonts','UISize',12);
    Result.FileFontFamily:=FDescriptor.Value('Fonts','FileFamily','JetBrains Mono');
    Result.FileFontSize:=FDescriptor.IntValue('Fonts','FileSize',10);
    Result.FixedFontFamily:=FDescriptor.Value('Fonts','FixedFamily','JetBrains Mono');
    Result.FixedFontSize:=FDescriptor.IntValue('Fonts','FixedSize',12);
    Result.DocumentFontFamily:=FDescriptor.Value('Fonts','DocumentFamily','JetBrains Mono');
    Result.DocumentFontSize:=FDescriptor.IntValue('Fonts','DocumentSize',10);
    Result.InfoFontFamily:=FDescriptor.Value('Fonts','InfoFamily','JetBrains Mono');
    Result.InfoFontSize:=FDescriptor.IntValue('Fonts','InfoSize',11);
  end
  else
  begin
    Result.DefaultDescriptor:='descriptors/AFileManager.release.window';
    Result.UserProfile:=WorkspaceUserConfigurationPath(FActiveWorkspaceId);
    Result.UIFontFamily:='JetBrains Mono'; Result.UIFontSize:=10;
    Result.FileFontFamily:='JetBrains Mono'; Result.FileFontSize:=9;
    Result.FixedFontFamily:='JetBrains Mono'; Result.FixedFontSize:=10;
    Result.DocumentFontFamily:='JetBrains Mono'; Result.DocumentFontSize:=10;
    Result.InfoFontFamily:='JetBrains Mono'; Result.InfoFontSize:=10;
  end;

  if FShortcutBindings<>nil then
    Result.ShortcutBindings:=FShortcutBindings.Text
  else if FDescriptor<>nil then
  begin
    Shortcuts:=FDescriptor.Section('Shortcuts');
    try
      Result.ShortcutBindings:=Shortcuts.Text;
    finally
      Shortcuts.Free;
    end;
  end
  else
    Result.ShortcutBindings:='';

  if FHasFontConfigurationOverride then
  begin
    Result.UIFontFamily:=FFontConfigurationOverride.UIFontFamily;
    Result.UIFontSize:=FFontConfigurationOverride.UIFontSize;
    Result.FileFontFamily:=FFontConfigurationOverride.FileFontFamily;
    Result.FileFontSize:=FFontConfigurationOverride.FileFontSize;
    Result.FixedFontFamily:=FFontConfigurationOverride.FixedFontFamily;
    Result.FixedFontSize:=FFontConfigurationOverride.FixedFontSize;
    Result.DocumentFontFamily:=FFontConfigurationOverride.DocumentFontFamily;
    Result.DocumentFontSize:=FFontConfigurationOverride.DocumentFontSize;
    Result.InfoFontFamily:=FFontConfigurationOverride.InfoFontFamily;
    Result.InfoFontSize:=FFontConfigurationOverride.InfoFontSize;
  end;
end;

function TAFileManagerController.SaveUserConfiguration(
  const ASettings: TAFMConfigurationSettings): Boolean;
var Path, Text, Report: string; Lines: TStringList;

  procedure SetValue(const ASection,AKey,AValue:string);
  var I,P,SecStart,SecEnd: Integer; Cur,Line,Key: string;
  begin
    SecStart:=-1; SecEnd:=Lines.Count;
    Cur:='';
    for I:=0 to Lines.Count-1 do
    begin
      Line:=Trim(Lines[I]);
      if (Line<>'') and (Line[1]='[') and (Line[Length(Line)]=']') then
      begin
        Cur:=Trim(Copy(Line,2,Length(Line)-2));
        if SameText(Cur,ASection) then SecStart:=I
        else if SecStart>=0 then begin SecEnd:=I; Break; end;
      end;
    end;
    if SecStart<0 then
    begin
      if (Lines.Count>0) and (Trim(Lines[Lines.Count-1])<>'') then Lines.Add('');
      Lines.Add('['+ASection+']');
      Lines.Add(AKey+'='+AValue);
      Exit;
    end;
    for I:=SecStart+1 to SecEnd-1 do
    begin
      Line:=Trim(Lines[I]);
      if Line='' then Continue;
      if (Line[1]=';') or (Line[1]='#') then Continue;
      P:=Pos('=',Line);
      if P<=1 then Continue;
      Key:=Trim(Copy(Line,1,P-1));
      if SameText(Key,AKey) then
      begin
        Lines[I]:=AKey+'='+AValue;
        Exit;
      end;
    end;
    Lines.Insert(SecEnd,AKey+'='+AValue);
  end;

  procedure ReplaceSection(const ASection, AText: string);
  var
    I, SecStart, SecEnd: Integer;
    Line, Cur: string;
    NewLines: TStringList;
  begin
    SecStart:=-1;
    SecEnd:=Lines.Count;
    Cur:='';
    for I:=0 to Lines.Count-1 do
    begin
      Line:=Trim(Lines[I]);
      if (Line<>'') and (Line[1]='[') and (Line[Length(Line)]=']') then
      begin
        Cur:=Trim(Copy(Line,2,Length(Line)-2));
        if SameText(Cur,ASection) then SecStart:=I
        else if SecStart>=0 then begin SecEnd:=I; Break; end;
      end;
    end;
    if SecStart>=0 then
      for I:=SecEnd-1 downto SecStart do Lines.Delete(I);
    if (Lines.Count>0) and (Trim(Lines[Lines.Count-1])<>'') then Lines.Add('');
    Lines.Add('['+ASection+']');
    NewLines:=TStringList.Create;
    try
      NewLines.Text:=AText;
      for I:=0 to NewLines.Count-1 do
      begin
        Line:=Trim(NewLines[I]);
        if (Line='') or (Line[1]=';') or (Line[1]='#') then Continue;
        if Pos('=',Line)>1 then Lines.Add(Line);
      end;
    finally
      NewLines.Free;
    end;
  end;

begin
  Result:=False;
  if (FDescriptor=nil) or (FFiles=nil) then Exit;
  Path:=WorkspaceUserConfigurationPath(FActiveWorkspaceId);
  if (Path<>'') and (Pos(':',Path)=0) and ((Path='') or (Path[1]<>'/')) then
    Path:=FDescriptorBase+Path;
  if Path='' then begin SetStatus('No user configuration file is selected'); Exit; end;
  Lines:=TStringList.Create;
  try
    if FFiles.ReadAllText(Path,Text) then Lines.Text:=Text;
    SetValue('Presentation','ThemePackage',ASettings.ThemePackageId);
    SetValue('Presentation','Theme',ASettings.ThemeId);
    SetValue('Window','Language',ASettings.InterfaceLanguage);
    SetValue('Visibility','Toolbar',BoolToStr(ASettings.ToolbarVisible,True));
    SetValue('Visibility','Operations',BoolToStr(ASettings.OperationsVisible,True));
    SetValue('Visibility','SplitView',BoolToStr(ASettings.SplitView,True));
    SetValue('Visibility','Preview',BoolToStr(ASettings.PreviewVisible,True));
    SetValue('Editor','RenditionVisible',BoolToStr(ASettings.EditorRenditionVisible,True));
    SetValue('Visibility','Metadata',BoolToStr(ASettings.MetadataVisible,True));
    SetValue('AFileManager','ConfirmDeletion',BoolToStr(ASettings.ConfirmDeletion,True));
    SetValue('FileOperations','DragSameVolume',AfmDragRule(ASettings.DragSameVolume,'Move'));
    SetValue('FileOperations','DragOtherVolume',AfmDragRule(ASettings.DragOtherVolume,'Copy'));
    SetValue('Diagnostics','Logging',BoolToStr(ASettings.LoggingEnabled,True));
    SetValue('Diagnostics','Level',ASettings.LoggingLevel);
    SetValue('FileView','ShowThumbnails',BoolToStr(ASettings.ShowThumbnails,True));
    SetValue('FileView','ThumbnailSize',IntToStr(ASettings.ThumbnailSize));
    SetValue('FileView','IconSize',IntToStr(ASettings.IconSize));
    SetValue('FileView','RowPadding',IntToStr(ASettings.RowPadding));
    SetValue('FileView','IconTextGap',IntToStr(ASettings.IconTextGap));
    SetValue('FileView','ColumnOrder',ASettings.ColumnOrder);
    SetValue('FileView','VisibleColumns',ASettings.VisibleColumns);
    SetValue('FileView','DefaultSortColumn',ASettings.DefaultSortColumn);
    SetValue('FileView','DefaultSortAscending',
      BoolToStr(ASettings.DefaultSortAscending,True));
    SetValue('CurrentLocation','ViewMode',ASettings.DefaultViewMode);
    SetValue('SecondaryLocation','ViewMode',ASettings.DefaultViewMode);
    SetValue('Fonts','UIFamily',ASettings.UIFontFamily);
    SetValue('Fonts','UISize',IntToStr(ASettings.UIFontSize));
    SetValue('Fonts','FileFamily',ASettings.FileFontFamily);
    SetValue('Fonts','FileSize',IntToStr(ASettings.FileFontSize));
    SetValue('Fonts','FixedFamily',ASettings.FixedFontFamily);
    SetValue('Fonts','FixedSize',IntToStr(ASettings.FixedFontSize));
    SetValue('Fonts','DocumentFamily',ASettings.DocumentFontFamily);
    SetValue('Fonts','DocumentSize',IntToStr(ASettings.DocumentFontSize));
    SetValue('Fonts','InfoFamily',ASettings.InfoFontFamily);
    SetValue('Fonts','InfoSize',IntToStr(ASettings.InfoFontSize));
    ReplaceSection('Shortcuts',ASettings.ShortcutBindings);
    Result:=FFiles.SafeSaveText(Path,Lines.Text);
    { 0.10.6: the same keys go to the Configuration Service }
    if AfmStoreServiceConfiguration(FActiveWorkspaceId,Lines.Text,Report) then
      Diagnostic('CONFIG service stored '+Report)
    else
      Diagnostic('CONFIG service not used ('+Report+')');
    if Result then
      Diagnostic('CONFIG saved '+Path+' fonts ui='+ASettings.UIFontFamily+'/'+
        IntToStr(ASettings.UIFontSize)+' list='+ASettings.FileFontFamily+'/'+
        IntToStr(ASettings.FileFontSize)+' console='+ASettings.FixedFontFamily+'/'+
        IntToStr(ASettings.FixedFontSize)+' help='+ASettings.DocumentFontFamily+'/'+
        IntToStr(ASettings.DocumentFontSize)+' info='+ASettings.InfoFontFamily+'/'+
        IntToStr(ASettings.InfoFontSize))
    else
      Diagnostic('CONFIG save failed '+Path);
  finally
    Lines.Free;
  end;
end;

procedure TAFileManagerController.ApplyServiceConfiguration;
var Path, Text, Report: string;
begin
  if FDescriptor=nil then Exit;
  Text:='';
  Path:=FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId);
  if (FFiles<>nil) and not FFiles.ReadAllText(Path,Text) then Text:='';
  if AfmApplyServiceConfiguration(FDescriptor,FActiveWorkspaceId,Text,Report) then
    Diagnostic('CONFIG service '+Report)
  else
    Diagnostic('CONFIG service not used ('+Report+'); profile file only');
end;

function TAFileManagerController.SaveStartupSelection(
  const ASettings: TAFMConfigurationSettings): Boolean;
var DescriptorPath, ProfilePath, Text: string;
begin
  if FWorkspaceSessionMode then Exit(True);
  Result:=False;
  if FFiles=nil then Exit;
  DescriptorPath:=Trim(ASettings.DefaultDescriptor);
  ProfilePath:=Trim(ASettings.UserProfile);
  if DescriptorPath='' then DescriptorPath:='descriptors/AFileManager.release.window';
  if ProfilePath='' then ProfilePath:='configurations/default.user';
  Text:='; AFileManager startup selection. Managed by Configuration.'+LineEnding+
    '[Descriptor]'+LineEnding+
    'Inherits='+DescriptorPath+LineEnding+LineEnding+
    '[Configuration]'+LineEnding+
    'UserConfig='+ProfilePath+LineEnding;
  Result:=FFiles.SafeSaveText(FDescriptorBase+'AFileManager.window',Text);
  if Result then Diagnostic('CONFIG startup descriptor='+DescriptorPath+' profile='+ProfilePath)
  else Diagnostic('CONFIG failed saving startup selection');
end;

procedure TAFileManagerController.ConfigurationApply(ASender: TArosaControl;
  const ASettings: TAFMConfigurationSettings; APersist: Boolean);
var NeedRefresh, LanguageChanged, ThemePackageChanged: Boolean;
begin
  LanguageChanged:=False;
  ThemePackageChanged:=not SameText(Trim(FActiveThemePackageId),Trim(ASettings.ThemePackageId));
  if FDescriptor<>nil then
    LanguageChanged:=not SameText(Trim(FDescriptor.Value('Window','Language','System')),Trim(ASettings.InterfaceLanguage));
  NeedRefresh:=(FFileIconSize<>ASettings.IconSize) or
    (FFileRowPadding<>ASettings.RowPadding) or
    (not SameText(ColumnOrderText,ASettings.ColumnOrder)) or
    (not SameText(VisibleColumnsText,ASettings.VisibleColumns)) or
    (not SameText(FDefaultSortColumn,ASettings.DefaultSortColumn)) or
    (FDefaultSortAscending<>ASettings.DefaultSortAscending) or
    (FFileIconTextGap<>ASettings.IconTextGap) or
    ((FLeftViewMode=2)<>SameText(ASettings.DefaultViewMode,'Icons')) or
    ((FLeftViewMode=0)<>SameText(ASettings.DefaultViewMode,'List')) or
    ((FLeftViewMode=1)<>SameText(ASettings.DefaultViewMode,'Details'));

  if ThemePackageChanged then
  begin
    FActiveThemePackageId:=Trim(ASettings.ThemePackageId);
    if FActiveThemePackageId='' then FActiveThemePackageId:='default';
    BuildThemeLayers;
    ApplyThemeColourLayers;
    Diagnostic('THEME package preview='+FActiveThemePackageId);
  end;

  if SameText(ASettings.ThemeId,'Light') then
  begin
    if not SameText(FActiveThemeId,'Light') then ThemeLightClick(nil);
  end
  else if not SameText(FActiveThemeId,'Dark') then ThemeDarkClick(nil);

  if (FWindowFrame<>nil) and
     (FWindowFrame.ToolbarVisible<>ASettings.ToolbarVisible) then
    FWindowFrame.ToggleToolbar;
  if (FWindowFrame<>nil) and
     (FWindowFrame.FilePanelVisible<>ASettings.OperationsVisible) then
    FWindowFrame.ToggleFilePanel;
  if (FWindowFrame<>nil) and (FRightColumn<>nil) and
     (FWindowFrame.SplitView<>ASettings.SplitView) then
    FWindowFrame.ToggleSplitView;

  if (FPreviewVisible<>ASettings.PreviewVisible) or
     (FMetadataVisible<>ASettings.MetadataVisible) then
    SetPanels(ASettings.PreviewVisible,ASettings.MetadataVisible,-1);
  FConfirmDeletion:=ASettings.ConfirmDeletion;
  FDragSameVolume:=AfmDragRule(ASettings.DragSameVolume,'Move');
  FDragOtherVolume:=AfmDragRule(ASettings.DragOtherVolume,'Copy');
  FEditorRenditionVisible:=ASettings.EditorRenditionVisible;
  FConfiguredLoggingEnabled:=ASettings.LoggingEnabled;
  FConfiguredLoggingLevel:=Trim(ASettings.LoggingLevel);
  if FConfiguredLoggingLevel='' then FConfiguredLoggingLevel:='Info';
  if not DiagnosticCommandLineOverride then
    DiagnosticConfigure(FConfiguredLoggingEnabled,
      DiagnosticSeverityFromName(FConfiguredLoggingLevel,amsInfo),'user-configuration');
  FLoggingEnabled:=DiagnosticLoggingEnabled;
  if FColumnOrder=nil then FColumnOrder:=TStringList.Create;
  if FVisibleColumns=nil then FVisibleColumns:=TStringList.Create;
  FColumnOrder.CaseSensitive:=False;
  FVisibleColumns.CaseSensitive:=False;
  FColumnOrder.StrictDelimiter:=True;
  FVisibleColumns.StrictDelimiter:=True;
  FColumnOrder.Delimiter:=',';
  FVisibleColumns.Delimiter:=',';
  FColumnOrder.DelimitedText:=ASettings.ColumnOrder;
  FVisibleColumns.DelimitedText:=ASettings.VisibleColumns;
  if FVisibleColumns.IndexOf('resource.name')<0 then
    FVisibleColumns.Add('resource.name');
  FShowThumbnails:=FVisibleColumns.IndexOf('resource.thumbnail')>=0;
  FDefaultSortColumn:=ASettings.DefaultSortColumn;
  if Trim(FDefaultSortColumn)='' then FDefaultSortColumn:='resource.name';
  FDefaultSortAscending:=ASettings.DefaultSortAscending;
  FThumbnailSize:=ASettings.ThumbnailSize;
  if FThumbnailSize<12 then FThumbnailSize:=12 else if FThumbnailSize>64 then FThumbnailSize:=64;
  FFileIconSize:=ASettings.IconSize;
  FFileRowPadding:=ASettings.RowPadding;
  FFileIconTextGap:=ASettings.IconTextGap;
  if SameText(ASettings.DefaultViewMode,'Windows') then begin FLeftViewMode:=3; FRightViewMode:=3; end
  else if SameText(ASettings.DefaultViewMode,'Icons') then begin FLeftViewMode:=2; FRightViewMode:=2; end
  else if SameText(ASettings.DefaultViewMode,'List') then begin FLeftViewMode:=0; FRightViewMode:=0; end
  else begin FLeftViewMode:=1; FRightViewMode:=1; end;

  if FShortcutBindings=nil then
  begin
    FShortcutBindings:=TStringList.Create;
    FShortcutBindings.NameValueSeparator:='=';
  end;
  FShortcutBindings.Text:=ASettings.ShortcutBindings;

  { Column headers and row visuals are one retained-list schema. Rebuild the
    canonical columns BEFORE rebuilding rows so new row children are measured
    and arranged against the same column order/visibility immediately. }
  ConfigureDetailsColumns(FLeftList);
  if FRightList<>nil then ConfigureDetailsColumns(FRightList);

  ApplyFileViewGeometry(0);
  ApplyFileViewGeometry(1);
  if NeedRefresh then
  begin
    RefreshView(0);
    if FRightList<>nil then RefreshView(1);
  end;
  UpdateViewToolbarState;

  { Font selection is a presentation setting. Apply it immediately as well as
    persisting it, so the user can verify the chosen family/size without a
    restart. Controls that carry an explicit file-list font are updated too. }
  ApplyConfigurationFonts(FTheme,ASettings);
  ApplyConfigurationFonts(FDarkTheme,ASettings);
  ApplyConfigurationFonts(FLightTheme,ASettings);

  { ApplyTheme refreshes retained file rows, so semantic font handles must be
    updated before that refresh, not afterward. }
  FCompactFont:=FFonts.Acquire(FTheme.FontFor(afrUI));
  FFileFont:=FFonts.Acquire(FTheme.FontFor(afrSmall));
  ApplyTheme(FTheme);
  ApplyLiveApplicationFont(ASettings);
  ApplyLiveFileFonts(ASettings);
  if FHelpSystem<>nil then
    FHelpSystem.ApplyDocumentFont(
      ASettings.DocumentFontFamily,ASettings.DocumentFontSize);

  FFontConfigurationOverride:=ASettings;
  FHasFontConfigurationOverride:=True;

  if FInfoDialog<>nil then
  begin
    FInfoDialog.Dismiss;
    if FWindowFrame<>nil then FWindowFrame.RemoveVisual(FInfoDialog);
    FreeAndNil(FInfoDialog);
  end;

  UpdateViewToolbarState;
  if LanguageChanged then
  begin
    { Apply is the test action: switch the active catalogue immediately.
      Surfaces rebuilt after this point (menus/help/status and refreshed rows)
      use the selected language. Save additionally makes it the next-launch
      default. }
    LoadLocalizationSpec(ASettings.InterfaceLanguage);
    { The Configuration dialog owns retained controls whose captions were
      resolved when it was constructed. Rebuild it on next open using the new
      catalogue; do not free it while its Apply handler is on the stack. }
    FConfigurationDialogNeedsRebuild:=True;
    if FHelpSystem<>nil then
    begin
      FHelpSystem.CloseForApplicationExit;
      FreeAndNil(FHelpSystem);
    end;
    RefreshView(0);
    if FRightList<>nil then RefreshView(1);
  end;
  BuildRootMenu;

  if APersist then
  begin
    if SaveUserConfiguration(ASettings) and
       (FWorkspaceSessionMode or SaveStartupSelection(ASettings)) then
    begin
      if LanguageChanged then
        SetStatus('Configuration saved; language preview applied and saved as default')
      else
        SetStatus('Configuration saved; font changes applied now; startup descriptor/profile apply on next launch');
    end
    else
      SetStatus('Configuration applied, but one or more configuration files could not be saved');
  end
  else
  begin
    if LanguageChanged then
      SetStatus('Language preview applied; Save makes it the default')
    else
      SetStatus('Configuration applied');
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConfigurationClick(ASender: TArosaControl);
begin
  ClearSubMenu;

  if FConfigurationDialogNeedsRebuild and (FWindowFrame<>nil) then
  begin
    if FConfigurationDialog<>nil then
    begin
      FWindowFrame.RemoveVisual(FConfigurationDialog);
      FreeAndNil(FConfigurationDialog);
    end;
    FConfigurationDialog:=TAFileManagerConfigurationDialog.CreateConfiguration(
      FTheme,FFonts,FPlatform.Clipboard,FLocalization);
    FConfigurationDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
    FConfigurationDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
    FConfigurationDialog.ZOrder:=23000;
    FConfigurationDialog.OnApply:=@ConfigurationApply;
    FConfigurationDialog.SetAvailableFonts(FFontService);
    FWindowFrame.AddVisual(FConfigurationDialog);
    FConfigurationDialogNeedsRebuild:=False;
  end;

  if FConfigurationDialog<>nil then
  begin
    { Re-scan installed themes/languages each time Configuration opens so
      packages copied into the runtime become selectable without restarting. }
    PopulateConfigurationChoices;
    FConfigurationDialog.ShowSettings(CurrentConfigurationSettings);
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.HelpContentsClick(ASender: TArosaControl);
begin
  ClearSubMenu;
  Diagnostic('HELP open requested');
  if (FNativeHost=nil) or (FNativeHost.Application=nil) then
  begin
    SetStatus('Help is unavailable until the application host is ready');
    Exit;
  end;
  try
    if FHelpSystem=nil then
      FHelpSystem:=TAFileManagerHelpSystem.CreateHelp(FPaths,FFiles,
        FPresentationService,FTheme,FFonts,'PROGDIR:help',FLocalization.Language);
    FHelpSystem.ConfigureWindowChrome(FWindowFrame,FNativeHost);
    FHelpSystem.ConfigureCommandResolvers(@CommandBarText,@CommandBarIcon);
    FHelpSystem.Show(FNativeHost.Application);
    Diagnostic('HELP show returned root='+FHelpSystem.RootPath);
  except
    on E: Exception do
    begin
      Diagnostic('HELP open failed: '+E.Message);
      SetStatus('Help failed: '+E.Message);
    end;
  end;
  if ASender=nil then ;
end;

function TAFileManagerController.InformationText: string;
var I: Integer; ChainText: string;
begin
  ChainText:='';
  if FDescriptor<>nil then
    for I:=0 to FDescriptor.Chain.Count-1 do
      ChainText:=ChainText+'  '+FDescriptor.Chain[I]+LineEnding;
  Result:='AFileManager '+ArosaBuildTag+LineEnding+
    'Solution idea created with AIDEa by DaniloS'+LineEnding+LineEnding+
    ArosaBuildLine+LineEnding+LineEnding+
    'AROSA subsystems'+LineEnding+
    '  Core: '+ArosaCore+LineEnding+
    '  UI: '+ArosaUI+LineEnding+
    '  Platform AROS: '+ArosaPlatformAros+LineEnding+
    '  System services: '+ArosaSystemServices+LineEnding+LineEnding+
    'Workspace'+LineEnding+
    '  File-manager surfaces: '+IntToStr(FSurfaces.Count)+LineEnding+
    '  Console sessions: '+IntToStr(FConsoles.Count)+LineEnding+
    '  Active environment: '+FActiveEnvironment+LineEnding+LineEnding+
    'Project updates, downloads, reports and discussions'+LineEnding+
    '  https://sourceforge.net/p/afilemanager/'+LineEnding+LineEnding+
    'Credits'+LineEnding+
    '  AROSA and AFileManager stand on the work of others, with thanks:'+LineEnding+LineEnding+
    '  NanoSVG    Mikko Mononen (zlib licence)'+LineEnding+
    '             https://github.com/memononen/nanosvg'+LineEnding+
    '  ThorVG     Hermet Park and the ThorVG contributors (MIT licence)'+LineEnding+
    '             https://www.thorvg.org/'+LineEnding+
    '  Brotli     the Brotli authors, Google (MIT licence)'+LineEnding+
    '             https://github.com/google/brotli'+LineEnding+
    '  tinf       Joergen Ibsen (zlib licence)'+LineEnding+
    '             https://github.com/jibsen/tinf'+LineEnding+
    '  QuickJS    Fabrice Bellard and Charlie Gordon (MIT licence)'+LineEnding+
    '             https://bellard.org/quickjs/'+LineEnding+
    '  SQLite     D. Richard Hipp and the SQLite contributors'+LineEnding+
    '             (public domain)  https://www.sqlite.org/'+LineEnding+
    '  MiniZip    Gilles Vollant, with Zip64 work by Mathias Svensson'+LineEnding+
    '             (zlib licence)  part of the zlib distribution'+LineEnding+
    '  zlib       Jean-loup Gailly and Mark Adler (zlib licence)'+LineEnding+
    '             https://zlib.net/'+LineEnding+
    '  FreeType   David Turner, Robert Wilhelm, Werner Lemberg and the'+LineEnding+
    '             FreeType contributors (FreeType licence)'+LineEnding+
    '             https://freetype.org/'+LineEnding+
    '  Mbed TLS   the Mbed TLS contributors (Apache 2.0 licence)'+LineEnding+
    '             https://www.trustedfirmware.org/projects/mbed-tls/'+LineEnding+
    '  AROS       the AROS Development Team  https://aros.org/'+LineEnding+
    '  Free Pascal  the Free Pascal team  https://www.freepascal.org/'+LineEnding+LineEnding+
    'Configuration chain'+LineEnding+ChainText;
end;

procedure TAFileManagerController.InfoClick(ASender: TArosaControl);
var
  Settings: TAFMConfigurationSettings;
begin
  ClearSubMenu;
  Diagnostic('INFO open requested');
  try
    if FInfoDialog=nil then
    begin
      Diagnostic('INFO create begin');
      Settings:=CurrentConfigurationSettings;
      FInfoDialog:=TAFileManagerInfoDialog.CreateInfo(
        FTheme,FFonts,FPlatform.Clipboard,FImageLoader,
        Settings.InfoFontFamily,Settings.InfoFontSize);
      FInfoDialog.OnExternalLink:=@InfoExternalLink;
      FInfoDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
      FInfoDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
      FInfoDialog.ZOrder:=23100;
      FWindowFrame.AddVisual(FInfoDialog);
      Diagnostic('INFO create end');
    end;
    FInfoDialog.ShowInfo(InformationText);
    Diagnostic('INFO show returned');
  except
    on E: Exception do
    begin
      Diagnostic('INFO open failed: '+E.Message);
      SetStatus('Information failed: '+E.Message);
      FInfoDialog:=nil;
    end;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.InfoExternalLink(
  ASender: TArosaControl; const AHref: string);
begin
  if (FShellService<>nil) and FShellService.OpenUrl(AHref) then
  begin
    SetStatus('Opening '+AHref);
    Diagnostic('INFO external link '+AHref);
  end
  else
  begin
    SetStatus('Unable to open URL: '+AHref);
    Diagnostic('INFO external link failed '+AHref);
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.PreviewOffClick(ASender: TArosaControl);
begin
  FWindowFrame.SetPreviewPlacement(0);
  BuildPreviewMenu;
  SetStatus(LocalText('afilemanager_status_preview_hidden','Preview hidden'));
end;
procedure TAFileManagerController.PreviewRightClick(ASender: TArosaControl);
begin
  FPreviewPreferredPlacement:=1;
  if FPreviewVisible or FMetadataVisible then FWindowFrame.SetPreviewPlacement(1);
  BuildPreviewMenu;
  SetStatus(LocalText('afilemanager_status_preview_right','Preview on right'));
end;
procedure TAFileManagerController.PreviewBottomClick(ASender: TArosaControl);
begin
  FPreviewPreferredPlacement:=2;
  if FPreviewVisible or FMetadataVisible then FWindowFrame.SetPreviewPlacement(2);
  BuildPreviewMenu;
  SetStatus(LocalText('afilemanager_status_preview_bottom','Preview at bottom'));
end;

procedure TAFileManagerController.ToggleSyncScrollingClick(ASender: TArosaControl);
begin
  FSyncScrolling:=not FSyncScrolling;
  if FSyncScrolling and (FLeftList<>nil) and (FRightList<>nil) then
    FRightList.ScrollOffset:=FLeftList.ScrollOffset;
  BuildRootMenu;
  if FSyncScrolling then SetStatus('Synchronized scrolling enabled')
  else SetStatus('Synchronized scrolling disabled');
end;

procedure TAFileManagerController.ToggleSyncWindowsClick(ASender: TArosaControl);
begin
  FSyncWindows:=not FSyncWindows;
  if FSyncWindows and (FLeftPreviewSplit<>nil) and (FRightPreviewSplit<>nil) then
    FRightPreviewSplit.SetPercent(FLeftPreviewSplit.Percent);
  BuildRootMenu;
  if FSyncWindows then SetStatus('Synchronized preview splitters enabled')
  else SetStatus('Synchronized preview splitters disabled');
end;

procedure TAFileManagerController.ListPointerDown(ASender: TArosaControl);
begin
  { The active file list must own keyboard focus so shared ListView
    type-to-select receives printable characters immediately after browsing. }
  if (FNativeHost<>nil) and (ASender is TArosaListView) then
    FNativeHost.FocusControl(TArosaListView(ASender));

  if ASender=FRightList then
  begin
    if FLeftList<>nil then FLeftList.DismissContextMenu;
    SetActiveView(1);
  end
  else if ASender=FLeftList then
  begin
    if FRightList<>nil then FRightList.DismissContextMenu;
    SetActiveView(0);
  end;
end;

procedure TAFileManagerController.ListSortChanged(
  ASender: TArosaControl; const AColumnId: string; AAscending: Boolean);
var
  S: TAFMConfigurationSettings;
begin
  if Trim(AColumnId)='' then Exit;

  FDefaultSortColumn:=AColumnId;
  FDefaultSortAscending:=AAscending;

  { Header sort is a user presentation preference. Persist it immediately so
    the next launch restores the last selected sort column and direction,
    without requiring the Configuration dialog to be opened afterward. }
  S:=CurrentConfigurationSettings;
  S.DefaultSortColumn:=AColumnId;
  S.DefaultSortAscending:=AAscending;
  SaveUserConfiguration(S);

  if ASender=FLeftList then FActiveView:=0
  else if ASender=FRightList then FActiveView:=1;
end;

procedure TAFileManagerController.ListContextMenuOpening(ASender: TArosaControl);
var Items: TStringList; TargetValue: string;
begin
  if (FWindowFrame<>nil) and FWindowFrame.MenuOpen then FWindowFrame.ToggleMenu;
  if FAssignments<>nil then FAssignments.DismissContextMenu;
  if ASender=FLeftList then
  begin
    if FRightList<>nil then FRightList.DismissContextMenu;
    SetActiveView(0);
  end
  else if ASender=FRightList then
  begin
    if FLeftList<>nil then FLeftList.DismissContextMenu;
    SetActiveView(1);
  end;
  { 0.5.110.16: the menu is rebuilt for what was right-clicked, so it can
    offer "Add to favourites" OR "Remove from favourites" (never both). }
  if (FListMenuBase=nil) or (FListMenuBase.Count=0) then Exit;
  FListFavoriteTarget:=ListFavoriteTarget(FActiveView);
  Items:=TStringList.Create;
  try
    Items.NameValueSeparator:='=';
    Items.Assign(FListMenuBase);

    if IsWorkspaceTrashLocation(ViewCurrent(FActiveView)) then
    begin
      Items.Clear;
      if (ViewList(FActiveView)<>nil) and
         (ViewList(FActiveView).SelectedCount=1) then
      begin
        Items.Add('Resource.Open=@afilemanager_action_open');
        Items.Add('Resource.Preview=@afilemanager_action_view_preview');
        if (FShellService<>nil) and (FShellService.Trash<>nil) and
           FShellService.Trash.OriginalPathFor(
             SelectedPath(FActiveView,ViewList(FActiveView).SelectedIndex),
             TargetValue) then
          Items.Add('Trash.Restore=@afilemanager_trash_restore');
        Items.Add('Separator.TrashItem=-');
        Items.Add('Trash.DeletePermanently=@afilemanager_trash_delete_permanently');
        Items.Add('Resource.Properties=@afilemanager_action_properties');
      end;
      Items.Add('Separator.Trash=-');
      Items.Add('Trash.Empty=@afilemanager_trash_empty');
      Items.Add('Navigation.Refresh=@afilemanager_action_refresh');
      Items.Add('Selection.All=@afilemanager_action_select_all');
      Items.Add('Selection.None=@afilemanager_action_select_none');
      if ASender is TArosaListView then
        TArosaListView(ASender).SetContextMenuItems(Items);
      Exit;
    end;

    ExpandFavoriteEntry(Items,FListFavoriteTarget);

    if SameText(ViewCurrent(FActiveView),'arosa://workspaces') then
    begin
      Items.Add('Separator.Workspaces=-');
      Items.Add('Workspace.Create=@afilemanager_workspace_create');
      if (ViewList(FActiveView)<>nil) and
         (ViewList(FActiveView).SelectedCount=1) and
         (ViewList(FActiveView).SelectedIndex>=0) and
         (WorkspaceIdFromLocation(SelectedPath(FActiveView,
           ViewList(FActiveView).SelectedIndex))<>'') then
        Items.Add('Workspace.Delete=@afilemanager_workspace_delete');
    end;

    if (ViewList(FActiveView)<>nil) and
       (ViewList(FActiveView).SelectedCount=1) and
       (ViewList(FActiveView).SelectedIndex>=0) then
    begin
      FListFavoriteTarget:=SelectedPath(FActiveView,
        ViewList(FActiveView).SelectedIndex);

      if Pos('exec:',LowerCase(Trim(FListFavoriteTarget)))=1 then
      begin
        Items.Add('Separator.WorkspaceLauncher=-');
        if (FLauncherService<>nil) and
           FLauncherService.ContainsTarget(FListFavoriteTarget) then
          Items.Add('Workspace.UnpinSelected=Remove from workspace taskbar')
        else
          Items.Add('Workspace.PinSelected=Pin to workspace taskbar');
      end;

      { 0.8.6.4: anything that can be opened can sit in the start menu of the
        workspace; the entry offered is the one that changes what is there.
        Offered where the workspace has its taskbar (0.8.6.5: every workspace). }
      if (FTaskbar<>nil) and FTaskbar.IsOpen and
         (Pos('internal:',LowerCase(Trim(FListFavoriteTarget)))<>1) then
      begin
        if StartMenuContains(FListFavoriteTarget) then
          Items.Add('StartMenu.Remove='+LocalText('afilemanager_startmenu_remove',
            'Remove from start menu'))
        else
          Items.Add('StartMenu.Add='+LocalText('afilemanager_startmenu_add',
            'Add to start menu'));
      end;

      Items.Add('Separator.Desktop=-');
      { a shortcut is removed from wherever its target is shown, not only
        from inside the Desktop itself }
      if DesktopShortcutIndex(FListFavoriteTarget)>=0 then
        Items.Add('Desktop.Remove=@afilemanager_desktop_remove')
      else if Pos('internal:',LowerCase(Trim(FListFavoriteTarget)))=1 then
        { nothing to place }
      else if not SameText(FListFavoriteTarget,'arosa://favorites') and
              not SameText(FListFavoriteTarget,'arosa://recent-locations') and
              not SameText(FListFavoriteTarget,'arosa://recent-files') and
              not SameText(FListFavoriteTarget,'arosa://assigns') and
              not SameText(FListFavoriteTarget,'arosa://network') and
              not SameText(FListFavoriteTarget,'arosa://devices') and
              not SameText(FListFavoriteTarget,FTrashDirectory) then
        Items.Add('Desktop.Add=@afilemanager_desktop_add');

      if SameText(FListFavoriteTarget,FTrashDirectory) then
      begin
        Items.Add('Separator.Trash=-');
        Items.Add('Trash.Empty=@afilemanager_trash_empty');
      end;
    end;

    if ASender is TArosaListView then TArosaListView(ASender).SetContextMenuItems(Items);
  finally Items.Free; end;
end;

procedure TAFileManagerController.FrameMenuOpening(ASender: TArosaControl);
begin
  if FLeftList<>nil then FLeftList.DismissContextMenu;
  if FRightList<>nil then FRightList.DismissContextMenu;
end;

procedure TAFileManagerController.LeftVerticalScroll(ASender: TArosaControl; AValue: Integer);
begin
  if FSyncScrolling and not FSyncingScroll and (FRightList<>nil) then
  begin FSyncingScroll:=True; try FRightList.ScrollOffset:=AValue; finally FSyncingScroll:=False; end; end;
end;

procedure TAFileManagerController.RightVerticalScroll(ASender: TArosaControl; AValue: Integer);
begin
  if FSyncScrolling and not FSyncingScroll and (FLeftList<>nil) then
  begin FSyncingScroll:=True; try FLeftList.ScrollOffset:=AValue; finally FSyncingScroll:=False; end; end;
end;

procedure TAFileManagerController.PreviewSplitterChanged(ASender: TArosaSplitterHost; APosition: TArosaCoord);
begin
  if ASender=FPlacesDetailSplit then
  begin
    FPlacesDetailPercent:=ASender.Percent;
    if FPlacesActive then UpdatePreviewPercentLabel;
    Exit;
  end;
  { 0.5.110.14.1: the two preview splitters start at the same Panel Size
    and move together while "synchronized windows" is on; when it is off
    each side is resized independently. Synchronisation is by PERCENT (the
    two panes need not have equal pixel heights). The Panel Size readout
    always shows the ACTIVE side. }
  if FSyncWindows and not FSyncingSplitter then
  begin
    FSyncingSplitter:=True;
    try
      if (ASender=FLeftPreviewSplit) and (FRightPreviewSplit<>nil) then
        FRightPreviewSplit.SetPercent(ASender.Percent)
      else if (ASender=FRightPreviewSplit) and (FLeftPreviewSplit<>nil) then
        FLeftPreviewSplit.SetPercent(ASender.Percent);
    finally FSyncingSplitter:=False; end;
  end;
  UpdatePreviewPercentLabel;
  if APosition=0 then ;
end;

function TAFileManagerController.ActivePathRole: string;
begin
  Result:='Error';
  if FDescriptor<>nil then
    Result:=Trim(FDescriptor.Value('Panes','ActivePathRole','Error'));
  if Result='' then Result:='Error';
end;

function TAFileManagerController.ActivePreviewSplit: TArosaSplitterHost;
begin
  if (FActiveView=1) and (FRightPreviewSplit<>nil) then Result:=FRightPreviewSplit
  else Result:=FLeftPreviewSplit;
end;

procedure TAFileManagerController.UpdatePreviewPercentLabel;
var Sp: TArosaSplitterHost; P: Integer;
begin
  if FPreviewPercentLabel=nil then Exit;
  if FPlacesActive and (FPlacesDetailSplit<>nil) then
  begin
    if FPlacesDetailSplit.Proportional then FPlacesDetailPercent:=FPlacesDetailSplit.Percent;
    P:=FPlacesDetailPercent;
  end
  else begin
    Sp:=ActivePreviewSplit;
    if (Sp<>nil) and Sp.Proportional then FPreviewPercent:=Sp.Percent;
    P:=FPreviewPercent;
  end;
  if FPreviewPercentLabel.Text<>IntToStr(P)+'%' then
  begin
    FPreviewPercentLabel.Text:=IntToStr(P)+'%';
    FPreviewPercentLabel.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.StepPreviewPercent(ADelta: Integer);
var Sp: TArosaSplitterHost; P: Integer;
begin
  if FPlacesActive and (FPlacesDetailSplit<>nil) then
  begin
    P:=FPlacesDetailSplit.Percent;
    Inc(P,ADelta); if P<10 then P:=10 else if P>90 then P:=90;
    FPlacesDetailPercent:=P;
    FPlacesDetailSplit.SetPercent(P);
    UpdatePreviewPercentLabel;
    Exit;
  end;
  Sp:=ActivePreviewSplit;
  if (Sp<>nil) and Sp.Proportional then P:=Sp.Percent else P:=FPreviewPercent;
  Inc(P,ADelta);
  if P<10 then P:=10 else if P>90 then P:=90;
  FPreviewPercent:=P;
  { + / - act on the selected side; with synchronized windows (or when the
    other side has never been resized independently) both sides follow. }
  if Sp<>nil then Sp.SetPercent(P);
  if FSyncWindows then
  begin
    if (Sp<>FLeftPreviewSplit) and (FLeftPreviewSplit<>nil) then FLeftPreviewSplit.SetPercent(P);
    if (Sp<>FRightPreviewSplit) and (FRightPreviewSplit<>nil) then FRightPreviewSplit.SetPercent(P);
  end;
  UpdatePreviewPercentLabel;
end;

procedure TAFileManagerController.ApplyThemeToTree(AVisual: TArosaVisual;
  ATheme: TArosaTheme);
var
  I: Integer;
  View: TArosaView;
begin
  if AVisual=nil then Exit;
  if AVisual is TArosaControl then
    TArosaControl(AVisual).SetTheme(ATheme,FFonts);
  { Only TArosaView exposes retained children. Leaf visuals do not. }
  if not (AVisual is TArosaView) then Exit;
  View := TArosaView(AVisual);
  for I:=0 to View.ChildVisualCount-1 do
    ApplyThemeToTree(View.ChildVisuals[I],ATheme);
end;

procedure TAFileManagerController.ApplyConfigurationFonts(
  ATheme: TArosaTheme; const ASettings: TAFMConfigurationSettings);
var
  D: TArosaFontDescription;
  UISize, FileSize, FixedSize, DocSize: Integer;
  UIFamily, FileFamily, FixedFamily, DocFamily: string;
begin
  if ATheme=nil then Exit;

  UIFamily:=Trim(ASettings.UIFontFamily);
  if (UIFamily='') or SameText(UIFamily,'system') then UIFamily:=ATheme.FontFor(afrUI).Family;
  FileFamily:=Trim(ASettings.FileFontFamily);
  if FileFamily='' then FileFamily:=UIFamily;
  FixedFamily:=Trim(ASettings.FixedFontFamily);
  if (FixedFamily='') or SameText(FixedFamily,'courier') then FixedFamily:=ATheme.FontFor(afrEditor).Family;
  DocFamily:=Trim(ASettings.DocumentFontFamily);
  if (DocFamily='') or SameText(DocFamily,'system') then DocFamily:=ATheme.FontFor(afrDocument).Family;

  UISize:=ASettings.UIFontSize;
  FileSize:=ASettings.FileFontSize;
  FixedSize:=ASettings.FixedFontSize;
  DocSize:=ASettings.DocumentFontSize;
  if UISize<8 then UISize:=8 else if UISize>24 then UISize:=24;
  if FileSize<8 then FileSize:=8 else if FileSize>24 then FileSize:=24;
  if FixedSize<8 then FixedSize:=8 else if FixedSize>24 then FixedSize:=24;
  if DocSize<8 then DocSize:=8 else if DocSize>24 then DocSize:=24;

  D:=ArosaFontDescription(UIFamily,UISize,afwNormal);
  D.Fallbacks:='helvetica,topaz';
  ATheme.SetFont(afrUI,D);

  D:=ArosaFontDescription(UIFamily,UISize+3,afwBold);
  D.Fallbacks:='helvetica,topaz';
  ATheme.SetFont(afrHeading,D);

  D:=ArosaFontDescription(FileFamily,FileSize,afwNormal);
  D.Fallbacks:='helvetica,topaz';
  ATheme.SetFont(afrSmall,D);

  D:=ArosaFontDescription(FixedFamily,FixedSize,afwNormal,False,True);
  D.Fallbacks:='courier,topaz';
  ATheme.SetFont(afrEditor,D);
  ATheme.SetFont(afrMonospace,D);

  D:=ArosaFontDescription(DocFamily,DocSize,afwNormal);
  D.Fallbacks:='helvetica,topaz';
  ATheme.SetFont(afrDocument,D);
end;

procedure TAFileManagerController.ApplyLiveApplicationFont(
  const ASettings: TAFMConfigurationSettings);
var
  Family: string;
  Size: Integer;

  procedure ApplyTo(C: TArosaControl);
  begin
    if C=nil then Exit;
    C.FontFamily:=Family;
    C.FontSize:=Size;
    C.InvalidateLayout;
    C.InvalidatePaint;
  end;

begin
  Family:=Trim(ASettings.UIFontFamily);
  if (Family='') or SameText(Family,'system') then Family:=FTheme.FontFor(afrUI).Family;
  Size:=ASettings.UIFontSize;
  if Size<8 then Size:=8 else if Size>24 then Size:=24;

  { Controls created with an explicit compact/application font do not change
    merely because the Theme's afrUI role changed. Update those live controls
    explicitly; ordinary controls still consume afrUI through ApplyTheme. }
  ApplyTo(FPlacesFilter);
  ApplyTo(FAssignments);
  ApplyTo(FLeftTitle);
  ApplyTo(FRightTitle);
  ApplyTo(FLeftPreview);
  ApplyTo(FRightPreview);
  ApplyTo(FLeftPreviewTitle);
  ApplyTo(FRightPreviewTitle);
  ApplyTo(FStatus);
  ApplyTo(FPreviewPercentLabel);

  if FForm<>nil then
  begin
    FForm.InvalidateLayout;
    FForm.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.ApplyLiveFileFonts(
  const ASettings: TAFMConfigurationSettings);
var
  Family: string;
  Size, I: Integer;
  Doc: TAFileManagerDocument;
  ConsoleDoc: TAFileManagerConsoleDocument;

  procedure ApplyTo(C: TArosaControl);
  begin
    if C=nil then Exit;
    C.FontFamily:=Family;
    C.FontSize:=Size;
    C.InvalidateLayout;
    C.InvalidatePaint;
  end;

begin
  { File-list/path role. }
  Family:=Trim(ASettings.FileFontFamily);
  if Family='' then Family:='system';
  Size:=ASettings.FileFontSize;
  if Size<8 then Size:=8 else if Size>24 then Size:=24;

  FFileFont:=FFonts.Acquire(FTheme.FontFor(afrSmall));
  ApplyTo(FLeftList);
  ApplyTo(FRightList);
  ApplyTo(FLeftPath);
  ApplyTo(FRightPath);
  ApplyTo(FLeftCrumbs);
  ApplyTo(FRightCrumbs);
  ApplyTo(FLeftFilter);
  ApplyTo(FRightFilter);
  ApplyTo(FLeftSearch);
  ApplyTo(FRightSearch);

  { Console/editor role. Existing documents keep explicit font properties, so
    update them directly when Apply/Save is pressed. }
  Family:=Trim(ASettings.FixedFontFamily);
  if (Family='') or SameText(Family,'courier') then Family:=FTheme.FontFor(afrEditor).Family;
  Size:=ASettings.FixedFontSize;
  if Size<8 then Size:=8 else if Size>24 then Size:=24;

  if FDocuments<>nil then
    for I:=0 to FDocuments.Count-1 do
    begin
      Doc:=TAFileManagerDocument(FDocuments[I]);
      if (Doc<>nil) and (Doc.Editor<>nil) then ApplyTo(Doc.Editor);
    end;

  if FConsoles<>nil then
    for I:=0 to FConsoles.Count-1 do
    begin
      ConsoleDoc:=TAFileManagerConsoleDocument(FConsoles[I]);
      if (ConsoleDoc<>nil) and (ConsoleDoc.Console<>nil) then
        ApplyTo(ConsoleDoc.Console);
    end;

  { File-row cell labels are retained children created with the file role.
    Rebuild them after changing the file family/size. }
  if FLeftList<>nil then RefreshView(0);
  if FRightList<>nil then RefreshView(1);
end;

procedure TAFileManagerController.ApplyConfiguredFontsToTheme(
  ATheme: TArosaTheme);
var
  S: TAFMConfigurationSettings;
begin
  if (ATheme=nil) or (FDescriptor=nil) then Exit;

  S.UIFontFamily:=FDescriptor.Value('Fonts','UIFamily','JetBrains Mono');
  S.UIFontSize:=FDescriptor.IntValue('Fonts','UISize',12);
  S.FileFontFamily:=FDescriptor.Value('Fonts','FileFamily',S.UIFontFamily);
  S.FileFontSize:=FDescriptor.IntValue('Fonts','FileSize',10);
  S.FixedFontFamily:=FDescriptor.Value('Fonts','FixedFamily','JetBrains Mono');
  S.FixedFontSize:=FDescriptor.IntValue('Fonts','FixedSize',12);
  S.DocumentFontFamily:=FDescriptor.Value('Fonts','DocumentFamily',S.UIFontFamily);
  S.DocumentFontSize:=FDescriptor.IntValue('Fonts','DocumentSize',10);
  ApplyConfigurationFonts(ATheme,S);
end;

procedure TAFileManagerController.ApplyTheme(ATheme: TArosaTheme);
var
  I: Integer;
begin
  if ATheme=nil then Exit;
  FTheme := ATheme;
  if FWindowFrame<>nil then ApplyThemeToTree(FWindowFrame,ATheme);
  if FAssignments<>nil then FAssignments.SetTheme(ATheme,FFonts);
  if FPlacesFilter<>nil then FPlacesFilter.SetTheme(ATheme,FFonts);
  if FLeftTitle<>nil then FLeftTitle.SetTheme(ATheme,FFonts);
  if FRightTitle<>nil then FRightTitle.SetTheme(ATheme,FFonts);
  if FLeftPath<>nil then FLeftPath.SetTheme(ATheme,FFonts);
  if FRightPath<>nil then FRightPath.SetTheme(ATheme,FFonts);
  if FLeftFilter<>nil then FLeftFilter.SetTheme(ATheme,FFonts);
  if FRightFilter<>nil then FRightFilter.SetTheme(ATheme,FFonts);
  if FLeftSearch<>nil then FLeftSearch.SetTheme(ATheme,FFonts);
  if FRightSearch<>nil then FRightSearch.SetTheme(ATheme,FFonts);
  if FLeftClearFilter<>nil then FLeftClearFilter.SetTheme(ATheme,FFonts);
  if FRightClearFilter<>nil then FRightClearFilter.SetTheme(ATheme,FFonts);
  if FLeftClearSearch<>nil then FLeftClearSearch.SetTheme(ATheme,FFonts);
  if FRightClearSearch<>nil then FRightClearSearch.SetTheme(ATheme,FFonts);
  if FLeftList<>nil then FLeftList.SetTheme(ATheme,FFonts);
  if FLeftColumns<>nil then
    for I := 0 to FLeftColumns.ChildVisualCount-1 do
      if FLeftColumns.ChildVisuals[I] is TArosaControl then
        TArosaControl(FLeftColumns.ChildVisuals[I]).SetTheme(ATheme, FFonts);
  if FRightList<>nil then FRightList.SetTheme(ATheme,FFonts);
  if FRightColumns<>nil then
    for I := 0 to FRightColumns.ChildVisualCount-1 do
      if FRightColumns.ChildVisuals[I] is TArosaControl then
        TArosaControl(FRightColumns.ChildVisuals[I]).SetTheme(ATheme, FFonts);
  { Rebuild retained resource cells after a theme transition so foreground
    roles are resolved immediately rather than after the next navigation. }
  if FLeftList<>nil then RefreshView(0);
  if FRightList<>nil then RefreshView(1);
  if FLeftList<>nil then SyncDetailsHeader(FLeftColumns,FLeftList.HorizontalOffset);
  if FRightList<>nil then SyncDetailsHeader(FRightColumns,FRightList.HorizontalOffset);
  if FLeftPreview<>nil then FLeftPreview.SetTheme(ATheme,FFonts);
  if FRightPreview<>nil then FRightPreview.SetTheme(ATheme,FFonts);
  if FLeftImagePreview<>nil then FLeftImagePreview.SetTheme(ATheme,FFonts);
  if FRightImagePreview<>nil then FRightImagePreview.SetTheme(ATheme,FFonts);
  if FMetadataView<>nil then FMetadataView.SetTheme(ATheme,FFonts);
  if FPlacesMetadata<>nil then FPlacesMetadata.SetTheme(ATheme,FFonts);
  if FRightMetadataView<>nil then FRightMetadataView.SetTheme(ATheme,FFonts);
  if FStatus<>nil then FStatus.SetTheme(ATheme,FFonts);
  if FNavigationTitleBar<>nil then
    for I:=0 to FNavigationTitleBar.ChildVisualCount-1 do
      if FNavigationTitleBar.ChildVisuals[I] is TArosaControl then
        TArosaControl(FNavigationTitleBar.ChildVisuals[I]).SetTheme(ATheme,FFonts);
  if FToolbarTabs<>nil then begin
    FToolbarTabs.ActiveBackground:=ATheme.ColourFor(AROSA_ROLE_TAB_ACTIVE);
    FToolbarTabs.InactiveBackground:=ATheme.ColourFor(AROSA_ROLE_TAB_INACTIVE);
    FToolbarTabs.ActiveText:=ATheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT);
    FToolbarTabs.InactiveText:=ATheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT);
    FToolbarTabs.BorderColour:=ATheme.ColourFor(AROSA_ROLE_BORDER);
  end;
  if FOperationTabs<>nil then begin
    FOperationTabs.ActiveBackground:=ATheme.ColourFor(AROSA_ROLE_TAB_ACTIVE);
    FOperationTabs.InactiveBackground:=ATheme.ColourFor(AROSA_ROLE_TAB_INACTIVE);
    FOperationTabs.ActiveText:=ATheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT);
    FOperationTabs.InactiveText:=ATheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT);
    FOperationTabs.BorderColour:=ATheme.ColourFor(AROSA_ROLE_BORDER);
  end;
  { 0.6.1.5: objects that captured the theme outside the visual tree }
  if FPresentationService<>nil then FPresentationService.ThemeChanged(ATheme);
  if FDocuments<>nil then
    for I:=0 to FDocuments.Count-1 do
    begin
      if TAFileManagerDocument(FDocuments[I]).RenditionText<>nil then
        TAFileManagerDocument(FDocuments[I]).RenditionText.SetTheme(ATheme,FFonts);
      if (TAFileManagerDocument(FDocuments[I]).RenditionPresentation<>nil) and
         (TAFileManagerDocument(FDocuments[I]).Editor.Text=
          TAFileManagerDocument(FDocuments[I]).OriginalText) then
        RefreshDocumentRendition(TAFileManagerDocument(FDocuments[I]));
    end;
  if (FNativeHost<>nil) and (FNativeHost.Bubbles<>nil) then FNativeHost.Bubbles.SetTheme(ATheme);
  if FLeftCommandBar<>nil then FLeftCommandBar.SetTheme(ATheme);
  if FRightCommandBar<>nil then FRightCommandBar.SetTheme(ATheme);

  { Floating application frames intentionally do not participate in this
    controller-wide retheme pass.  A detached Console captures the theme of
    the workspace that owns it when it is popped out.  Opening or activating
    another workspace must not mutate that floating frame.  If the Console is
    embedded again, the embedded visual tree resumes the normal controller
    theme path and a later pop-out captures that current workspace theme. }

  { an open presentation may have baked theme colours into its content
    (AmigaGuide): rebuild it with the new theme }
  if FLeftPresentation<>nil then UpdatePreview(0);
  if FRightPresentation<>nil then UpdatePreview(1);
  if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
end;

procedure TAFileManagerController.ApplyPreviewLayout(AView, APlacement: Integer);
var Outer, Browser, PreviewHost: TArosaColumnPanel; Split: TArosaSplitterHost;
    PreviousPlacement: Integer;
begin
  if AView=0 then begin
    Outer:=FLeftColumn; Browser:=FLeftBrowserColumn; PreviewHost:=FLeftPreviewHost;
    Split:=FLeftPreviewSplit; PreviousPlacement:=FLeftPreviewPlacementApplied;
  end
  else begin
    Outer:=FRightColumn; Browser:=FRightBrowserColumn; PreviewHost:=FRightPreviewHost;
    Split:=FRightPreviewSplit; PreviousPlacement:=FRightPreviewPlacementApplied;
  end;
  if (Outer=nil) or (Browser=nil) or (PreviewHost=nil) or (Split=nil) then Exit;
  if APlacement<0 then APlacement:=0 else if APlacement>2 then APlacement:=2;
  { Repeated descriptor/menu notifications must not detach and reparent the
    same retained controls again.  Besides avoiding needless layout work, this
    keeps the ownership graph stable while compilation or other applications
    are active in parallel. }
  if PreviousPlacement=APlacement then
  begin
    PreviewHost.Visible:=(APlacement<>0) and (FPreviewVisible or FMetadataVisible);
    Exit;
  end;
  ArosaTrace('PREVIEW-LAYOUT','begin view='+IntToStr(AView)+
    ' previous='+IntToStr(PreviousPlacement)+' requested='+IntToStr(APlacement));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
  { Detach panes from the previous splitter before rebuilding. Otherwise
    Preview=Off can leave Browser parented to a hidden splitter. }
  if Split<>nil then Split.SetPanes(nil,nil);
  Outer.ClearVisuals;
  PreviewHost.Visible:=(APlacement<>0) and (FPreviewVisible or FMetadataVisible);
  if APlacement=1 then
  begin
    PreviewHost.SetConstraintWidth(asmFixed,ArosaCoord(StrToIntDef(FDescriptor.Value('Preview','Width','260'),260)));
    PreviewHost.SetConstraintHeight(asmStar,ArosaCoord(1));
    Split.Orientation:=aorHorizontal;
    Split.SetInitialPercent(FPreviewPercent);
    Split.SetPanes(Browser,PreviewHost);
    Split.SetConstraintHeight(asmStar,ArosaCoord(1));
    Outer.AddVisual(Split);
  end
  else if APlacement=2 then
  begin
    { Bottom preview is a genuine vertical splitter, not two stacked fixed
      panels.  The descriptor percentage defines the browser share and the
      user can adjust it at runtime. }
    Browser.SetConstraintHeight(asmStar,ArosaCoord(1));
    PreviewHost.SetConstraintHeight(asmStar,ArosaCoord(1));
    PreviewHost.SetConstraintWidth(asmStar,ArosaCoord(1));
    Split.Orientation:=aorVertical;
    Split.SetInitialPercent(FPreviewPercent);
    Split.SetPanes(Browser,PreviewHost);
    Split.SetConstraintHeight(asmStar,ArosaCoord(1));
    Outer.AddVisual(Split);
  end
  else
  begin
    Browser.SetConstraintHeight(asmStar,ArosaCoord(1));
    Outer.AddVisual(Browser);
  end;
  if AView=0 then FLeftPreviewPlacementApplied:=APlacement
  else FRightPreviewPlacementApplied:=APlacement;
  Outer.InvalidateLayout;
  Outer.InvalidatePaint;
  ArosaTrace('PREVIEW-LAYOUT','end view='+IntToStr(AView)+
    ' applied='+IntToStr(APlacement)+' child-count='+IntToStr(Outer.ChildVisualCount));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
end;

function TAFileManagerController.IsProviderLocation(const APath: string): Boolean;
begin
  Result := Pos('://', Trim(APath)) > 0;
end;

{ Remote = reached through a location provider that is not one of AROSA's
  own.  arosa:// (desktop, favourites, workspaces...) is a provider location
  too, but it is this machine's own bookkeeping, not somewhere else. }
function TAFileManagerController.IsRemoteLocation(const APath: string): Boolean;
var S: string;
begin
  S:=LowerCase(Trim(APath));
  Result:=(Pos('://',S)>1) and (Pos('arosa://',S)<>1) and (Pos('file://',S)<>1);
end;

function TAFileManagerController.RemoteTextRole: string;

  function Known(const ARole: string): Boolean;
  begin
    Result:=(ARole<>'') and
      ((FTheme=nil) or FTheme.HasRole(ARole)) and
      ((FDarkTheme=nil) or FDarkTheme.HasRole(ARole)) and
      ((FLightTheme=nil) or FLightTheme.HasRole(ARole));
  end;

begin
  { A label asked for a role its theme does not have cannot paint.  A
    mistyped [Panes] RemoteRole therefore falls back to the built-in role,
    and to no colouring at all if even that is missing from a theme. }
  if (FRemoteRole<>'') and not Known(FRemoteRole) then
  begin
    Diagnostic('THEME remote role "'+FRemoteRole+'" is not defined; using '+
      AROSA_ROLE_REMOTE);
    if Known(AROSA_ROLE_REMOTE) then FRemoteRole:=AROSA_ROLE_REMOTE
    else FRemoteRole:='';
  end;
  Result:=FRemoteRole;
end;

{ "atransfer://nas:8080/music/live" -> "nas:8080" }
function TAFileManagerController.RemoteLocationLabel(const APath: string): string;
var S: string; P: Integer;
begin
  S:=Trim(APath);
  P:=Pos('://',S);
  if P=0 then Exit('');
  Delete(S,1,P+2);
  P:=Pos('/',S);
  if P>0 then S:=Copy(S,1,P-1);
  Result:=S;
end;

procedure TAFileManagerController.UpdatePaneInfo(AView: Integer);
var L: TArosaFilteredListView; Info: TArosaLabel; V: TArosaVolumeInfo; FreeText: string;
begin
  L:=ViewList(AView);
  if AView=0 then Info:=FLeftTitle else Info:=FRightTitle;
  if (L=nil) or (Info=nil) then Exit;
  { Provider URIs are not AmigaDOS paths.  Never ask the local file service
    for volume information about a provider location: AROS interprets the URI
    scheme as a DOS device name and opens an Insert Volume requester. }
  if IsProviderLocation(ViewCurrent(AView)) then
    FreeText:=LocalText('afilemanager_not_available','n/a')
  else if (FFiles<>nil) and FFiles.GetVolumeInfo(ViewCurrent(AView),V) and V.Available then
    FreeText:=SizeText(V.FreeBytes)
  else FreeText:=LocalText('afilemanager_not_available','n/a');
  Info.Text:=LocalText('afilemanager_items','Items')+': '+IntToStr(L.ItemCount)+
    '   '+LocalText('afilemanager_selected','Selected')+': '+IntToStr(L.SelectedCount)+
    '   '+LocalText('afilemanager_volume_free','Volume free')+': '+FreeText;
  { say in words what the colour says, for anyone who cannot rely on colour }
  if IsRemoteLocation(ViewCurrent(AView)) then
    Info.Text:=LocalText('afilemanager_remote','Remote')+' '+
      RemoteLocationLabel(ViewCurrent(AView))+'   '+Info.Text;
end;


function TAFileManagerController.ColumnWidth(const ASection: string; ADefaultWidth: Integer): Integer;
var V: string;
begin
  V:=Trim(FDescriptor.Value('Column.'+ASection,'Width',IntToStr(ADefaultWidth)));
  if SameText(V,'Auto') then
  begin
    if SameText(ASection,'Type') then Result:=72
    else if SameText(ASection,'Name') then Result:=260
    else if SameText(ASection,'Size') then Result:=76
    else if SameText(ASection,'Modified') then Result:=138
    else if SameText(ASection,'Permissions') then Result:=96
    else Result:=ADefaultWidth;
  end
  else if SameText(V,'Fill') then Result:=ADefaultWidth
  else Result:=StrToIntDef(V,ADefaultWidth);
  if Result<32 then Result:=32;
end;

function TAFileManagerController.FileIconRowHeight: TArosaCoord;
var
  Pixels, ThemePixels: Integer;
begin
  Pixels:=FFileIconSize+(FFileRowPadding*2);
  ThemePixels:=ArosaCoordWhole(FTheme.Metrics.RowHeight);
  if Pixels<ThemePixels then Pixels:=ThemePixels;
  Result:=ArosaCoord(Pixels);
end;

procedure TAFileManagerController.ApplyFileViewGeometry(AView: Integer);
var
  L: TArosaFilteredListView;
  Mode: Integer;
begin
  if AView=0 then begin L:=FLeftList; Mode:=FLeftViewMode; end
  else begin L:=FRightList; Mode:=FRightViewMode; end;
  if L=nil then Exit;

  { Workbench mode is a real spatial presentation, not an icon-sized row.
    The previous implementation created the spatial painter but never enabled
    it here, so selecting the fourth mode still rendered ordinary rows. }
  L.SpatialIcons:=Mode=3;
  L.SpatialCellWidth:=FDescriptor.IntValue('FileView','WindowsCellWidth',112);
  L.SpatialCellHeight:=FDescriptor.IntValue('FileView','WindowsCellHeight',94);
  L.SpatialIconSize:=FDescriptor.IntValue('FileView','WindowsIconSize',48);
  L.HeaderVisible:=Mode=1;
  if Mode=2 then L.ItemHeight:=FileIconRowHeight
  else if (Mode=1) and FShowThumbnails then
  begin
    if FFileRowPadding*2>6 then
      L.ItemHeight:=ArosaCoord(FThumbnailSize+(FFileRowPadding*2))
    else
      L.ItemHeight:=ArosaCoord(FThumbnailSize+6);
  end
  else L.ItemHeight:=FTheme.Metrics.RowHeight;
  L.InvalidateLayout;
  L.InvalidatePaint;
end;

function TAFileManagerController.NewDetailsCell(const AText, ASection: string;
  ADefaultWidth: Integer; AAlign: Integer): TArosaLabel;
begin
  Result:=TArosaLabel.CreateControl(FTheme,FFonts);
  Result.Text:=AText;
  Result.FontFamily:=FFileFont.Description.Family;
  Result.FontSize:=FFileFont.Description.SizePoints;
  Result.HorizontalAlignment:=AAlign;
  Result.VerticalAlignment:=AROSA_ALIGN_CENTER;
  Result.Padding:=ArosaMargins(5,0,5,0);
  Result.SetConstraintWidth(asmFixed,ArosaCoord(ColumnWidth(ASection,ADefaultWidth)));
  Result.SetConstraintHeight(asmFixed,FTheme.Metrics.RowHeight);
end;


function TAFileManagerController.SemanticFileIconName(
  const AInfo: TArosaFileInfo): string;
var E: string;
begin
  if Pos('exec:',LowerCase(Trim(AInfo.FullPath)))=1 then Exit('executable');
  if Pos('internal:',LowerCase(Trim(AInfo.FullPath)))=1 then Exit('server');
  if AInfo.Kind=afekDirectory then
  begin
    if SameText(AInfo.FullPath,'arosa://favorites') then Exit('favorites');
    if SameText(AInfo.FullPath,'arosa://recent-locations') then Exit('recent');
    if SameText(AInfo.FullPath,'arosa://recent-files') then Exit('recent-files');
    if SameText(AInfo.FullPath,'arosa://assigns') then Exit('assigns');
    if SameText(AInfo.FullPath,'arosa://network') then Exit('network');
    if SameText(AInfo.FullPath,'arosa://devices') then Exit('devices');
    if SameText(AInfo.FullPath,'arosa://workspaces') then Exit('workspace');
    if Pos('/favorites',LowerCase(AInfo.FullPath))>0 then Exit('favorites');
    if Pos('/recent-files',LowerCase(AInfo.FullPath))>0 then Exit('recent-files');
    if Pos('/recent-edits',LowerCase(AInfo.FullPath))>0 then Exit('recent');
    if Pos('/recent-locations',LowerCase(AInfo.FullPath))>0 then Exit('recent');
    if Pos('/trash',LowerCase(AInfo.FullPath))>0 then Exit('trash');
    if Pos('arosa://workspace/',LowerCase(AInfo.FullPath))=1 then Exit('workspace');
    if SameText(AInfo.FullPath,FTrashDirectory) or
       SameText(ExtractFileName(AInfo.Name),'.arosa-trash') then Exit('trash');
    Exit('folder');
  end;
  E:=LowerCase(ExtractFileExt(AInfo.Name));
  if E='.info' then Exit('metadata');
  if (E='.txt') or (E='.readme') or (E='.md') or (E='.log') or (E='.ini') or (E='.cfg') then Exit('text');
  if (E='.html') or (E='.htm') then Exit('html');
  if E='.json' then Exit('json');
  if E='.xml' then Exit('xml');
  if (E='.pas') or (E='.pp') or (E='.lpr') or (E='.lfm') or (E='.lpi') or (E='.lpk') then Exit('pascal');
  if (E='.c') or (E='.h') then Exit('c');
  if (E='.cpp') or (E='.hpp') or (E='.cc') or (E='.cxx') then Exit('cpp');
  if (E='.js') or (E='.mjs') or (E='.ts') then Exit('javascript');
  if E='.py' then Exit('python');
  if (E='.sh') or (E='.bat') or (E='.cmd') or (E='.rexx') then Exit('shell');
  if E='.png' then Exit('png');
  if (E='.jpg') or (E='.jpeg') then Exit('jpg');
  if E='.svg' then Exit('svg');
  if (E='.ttf') or (E='.otf') then Exit('font');
  if (E='.gif') or (E='.bmp') or (E='.iff') or (E='.ilbm') then Exit('image');
  if E='.pdf' then Exit('pdf');
  if E='.zip' then Exit('zip');
  if (E='.lha') or (E='.lzh') then Exit('lha');
  if E='.lzx' then Exit('lzx');
  if E='.tar' then Exit('tar');
  if E='.7z' then Exit('7z');
  if (E='.gz') or (E='.tgz') then Exit('archive');
  if E='.mp3' then Exit('mp3');
  if E='.wav' then Exit('wav');
  if E='.mod' then Exit('mod');
  if (E='.mp4') or (E='.avi') or (E='.mov') or (E='.mkv') then Exit('video');
  if (E='.a') or (E='.lib') or (E='.so') or (E='.dll') then Exit('library');
  if (E='.exe') or (E='.com') or (E='.bin') or (E='.run') then Exit('executable');
  Result:='file';
end;

function TAFileManagerController.AddRowImage(ARow: TArosaListRow;
  ABitmap: TArosaPlatformHandle; const ASource: TArosaRect;
  const AAltText: string; AOwnedResource: TArosaImageResource=nil;
  AGhosted: Boolean=False): Boolean;
var Image: TArosaImageBox;
begin
  Result:=False;
  if (ARow=nil) or (ABitmap=ArosaNilHandle) then Exit;
  Image:=TArosaImageBox.CreateControl(FTheme,FFonts);
  Image.Bitmap:=ABitmap;
  Image.SourceRect:=ASource;
  Image.StretchMode:=aismFit;
  Image.AltText:=AAltText;
  Image.Ghosted:=AGhosted;
  Image.SetConstraintWidth(asmFixed,ArosaCoord(FFileIconSize));
  Image.SetConstraintHeight(asmFixed,ArosaCoord(FFileIconSize));
  ARow.AddObject(Image);
  if AOwnedResource<>nil then
    ARow.AddObject(AOwnedResource);
  Result:=True;
end;

procedure TAFileManagerController.PopulateIconRow(ARow: TArosaListRow;
  const AInfo: TArosaFileInfo; AWorkbench: Boolean);
var
  IconPath, PhysicalIcon, LoadError, ThemeSpec: string;
  Img: TArosaPlatformHandle;
  Src: TArosaRect;
  Res, ThumbRes: TArosaImageResource;
  Content, ThumbContent: TArosaContentDescriptor;
  NameLabel: TArosaLabel;
  ThumbPhysical, ThumbError: string;
  UsedVisual, Hidden, InvocationTarget: Boolean;
  IconInfo: TArosaFileInfo;
  IconState: TArosaCachedLocationState;
begin
  if ARow=nil then Exit;
  Hidden:=IsHiddenResource(AInfo);
  InvocationTarget:=(Pos('exec:',LowerCase(Trim(AInfo.FullPath)))=1) or
    (Pos('internal:',LowerCase(Trim(AInfo.FullPath)))=1);
  Res:=nil;
  ThumbRes:=nil;
  UsedVisual:=False;
  IconPath:=AInfo.FullPath;
  if (not InvocationTarget) and (LowerCase(ExtractFileExt(IconPath))<>'.info') then IconPath:=IconPath+'.info';
  PhysicalIcon:='';
  if InvocationTarget then PhysicalIcon:=''
  else if IsProviderLocation(IconPath) then
  begin
    { Row rendering is cache-driven. A fresh parent LIST already tells the
      Location Service whether the companion .info exists, including a
      negative answer. Do not issue a STAT from presentation code. If it is
      present, Content Service resolves memory cache -> persistent byte cache
      -> one AGet on a true miss. }
    IconState:=aclsUnknown;
    if FLocations<>nil then IconState:=FLocations.CachedInfo(IconPath,IconInfo);
    if (IconState=aclsPresent) and (FContent<>nil) and
       FContent.AcquireOriginal(IconPath,Content,LoadError) then
      PhysicalIcon:=Content.PhysicalPath;
  end
  else if (FPaths<>nil) and FPaths.Exists(IconPath) then
    PhysicalIcon:=IconPath;

  { Workbench companion .info presentation is authoritative. }
  if AWorkbench and (PhysicalIcon<>'') and (FImageLoader<>nil) and
     FImageLoader.TryLoadFile(PhysicalIcon,Res,LoadError) then
  begin
    AddRowImage(ARow,Res.Bitmap,ArosaRectXYWH(0,0,Res.Width,Res.Height),
      AInfo.Name,Res,Hidden);
    UsedVisual:=True;
  end;

  { Thumbnail presentation is a user-visible option. In ordinary Icon view it
    is preferred. In Workbench mode it is only a fallback when no .info icon
    exists, preserving Amiga/AROS desktop semantics. Remote resources are never
    mass-downloaded merely to make thumbnails; cached bytes are reused. }
  if (not UsedVisual) and FShowThumbnails and
     IsThumbnailPictureResource(AInfo) and (FImageLoader<>nil) then
  begin
    ThumbPhysical:=AInfo.FullPath;
    if IsProviderLocation(ThumbPhysical) then
    begin
      if (FContent<>nil) and FContent.IsOriginalCached(ThumbPhysical) and
         FContent.AcquireOriginal(ThumbPhysical,ThumbContent,ThumbError) then
        ThumbPhysical:=ThumbContent.PhysicalPath
      else
        ThumbPhysical:='';
    end;
    if (ThumbPhysical<>'') and
       FImageLoader.TryLoadFile(ThumbPhysical,ThumbRes,ThumbError) and
       (ThumbRes<>nil) and (ThumbRes.Bitmap<>ArosaNilHandle) then
    begin
      AddRowImage(ARow,ThumbRes.Bitmap,
        ArosaRectXYWH(0,0,ThumbRes.Width,ThumbRes.Height),
        AInfo.Name,ThumbRes,Hidden);
      UsedVisual:=True;
    end
    else if ThumbRes<>nil then
    begin
      ThumbRes.Free;
      ThumbRes:=nil;
    end;
  end;

  { Icon mode still understands .info when thumbnails are off or unavailable. }
  if (not UsedVisual) and (not AWorkbench) and (PhysicalIcon<>'') and
     (FImageLoader<>nil) and FImageLoader.TryLoadFile(PhysicalIcon,Res,LoadError) then
  begin
    AddRowImage(ARow,Res.Bitmap,ArosaRectXYWH(0,0,Res.Width,Res.Height),
      AInfo.Name,Res,Hidden);
    UsedVisual:=True;
  end;

  if not UsedVisual then
  begin
    ThemeSpec:='theme:'+SemanticFileIconName(AInfo);
    if LoadThemeIcon(ThemeSpec,Img,Src) then
      AddRowImage(ARow,Img,Src,AInfo.Name,nil,Hidden)
    else if LoadThemeIcon('theme:file',Img,Src) then
      AddRowImage(ARow,Img,Src,AInfo.Name,nil,Hidden);
  end;

  NameLabel:=NewDetailsCell(AInfo.Name,'Name',300,AROSA_ALIGN_NEAR);
  if Hidden then NameLabel.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  if IsRemoteLocation(AInfo.FullPath) and (RemoteTextRole<>'') then
    NameLabel.TextRole:=RemoteTextRole;
  NameLabel.Padding:=ArosaMargins(FFileIconTextGap,0,5,0);
  NameLabel.SetConstraintHeight(asmFixed,FileIconRowHeight);
  ARow.AddObject(NameLabel);
end;

function TAFileManagerController.IsThumbnailPictureResource(
  const AInfo: TArosaFileInfo): Boolean;
var
  Group: TArosaDataTypeGroup;
begin
  Result:=False;
  if AInfo.Kind=afekDirectory then Exit;
  if (Pos('exec:',LowerCase(Trim(AInfo.FullPath)))=1) or
     (Pos('internal:',LowerCase(Trim(AInfo.FullPath)))=1) then Exit;

  { Thumbnail generation is capability/type driven.  Do not pass arbitrary
    resources to picture.datatype merely to discover whether they might be
    images: entering a directory such as Fonts: can contain hundreds of
    .font/.otag files and that synchronous probing blocks the UI event loop. }
  if FDataTypes<>nil then
  begin
    Group:=FDataTypes.GroupOf(AInfo.FullPath);
    Result:=Group=adtgPicture;
    Exit;
  end;

  { Conservative compatibility fallback if the datatype service is not
    available.  Keep this list limited to formats already handled by the
    AROSA image path. }
  case LowerCase(ExtractFileExt(AInfo.Name)) of
    '.png','.jpg','.jpeg','.gif','.bmp','.iff','.ilbm','.lbm','.svg':
      Result:=True;
  end;
end;

procedure TAFileManagerController.ClearThumbnailCache(AView: Integer);
var C: TStringList;
begin
  if (AView<0) or (AView>1) then Exit;
  C:=FThumbnailCache[AView];
  if C<>nil then
  begin
    while C.Count>0 do
    begin
      if C.Objects[C.Count-1]<>nil then
        TArosaImageResource(C.Objects[C.Count-1]).Free;
      C.Delete(C.Count-1);
    end;
    FreeAndNil(FThumbnailCache[AView]);
  end;
  FThumbnailCacheLocation[AView]:='';
end;

function TAFileManagerController.ThumbnailCacheKey(
  const AInfo: TArosaFileInfo): string;
begin
  Result:=LowerCase(AInfo.FullPath)+'|'+IntToStr(FThumbnailSize)+'|'+
    IntToStr(AInfo.Size)+'|'+FormatDateTime('yyyymmddhhnnss',AInfo.ModifiedUtc);
end;

function TAFileManagerController.TryAddCompactThumbnail(
  ARow: TArosaListRow; const AInfo: TArosaFileInfo;
  AView: Integer; AGhosted: Boolean): Boolean;
var
  Physical, Err, Key: string;
  Res: TArosaImageResource;
  C: TArosaContentDescriptor;
  Image: TArosaImageBox;
  Cache: TStringList;
  I: Integer;
begin
  Result:=False;
  if (ARow=nil) or (not FShowThumbnails) or
     (AInfo.Kind=afekDirectory) or (FImageLoader=nil) then Exit;
  if not IsThumbnailPictureResource(AInfo) then
  begin
    if ArosaTraceEnabled then
      ArosaTrace('THUMBNAIL','skip non-picture path="'+AInfo.FullPath+'"');
    Exit;
  end;

  Physical:=AInfo.FullPath;
  if IsProviderLocation(Physical) then
  begin
    if (FContent=nil) or not FContent.IsOriginalCached(Physical) then Exit;
    if not FContent.AcquireOriginal(Physical,C,Err) then Exit;
    Physical:=C.PhysicalPath;
  end;

  if (AView<0) or (AView>1) then Exit;
  Cache:=FThumbnailCache[AView];
  if Cache=nil then
  begin
    Cache:=TStringList.Create;
    Cache.CaseSensitive:=False;
    FThumbnailCache[AView]:=Cache;
  end;

  Key:=ThumbnailCacheKey(AInfo);
  I:=Cache.IndexOf(Key);
  if I>=0 then
    Res:=TArosaImageResource(Cache.Objects[I])
  else
  begin
    Res:=nil;
    if not FImageLoader.TryLoadFile(Physical,Res,Err) then Exit;
    if (Res=nil) or (Res.Bitmap=ArosaNilHandle) then
    begin
      if Res<>nil then Res.Free;
      Exit;
    end;
    Cache.AddObject(Key,Res);
    if ArosaTraceEnabled then
      ArosaTrace('THUMBNAIL','cache add view='+IntToStr(AView)+
        ' path="'+AInfo.FullPath+'" entries='+IntToStr(Cache.Count));
  end;

  if (Res=nil) or (Res.Bitmap=ArosaNilHandle) then Exit;
  Image:=TArosaImageBox.CreateControl(FTheme,FFonts);
  Image.Bitmap:=Res.Bitmap;
  Image.SourceRect:=ArosaRectXYWH(0,0,Res.Width,Res.Height);
  Image.StretchMode:=aismFit;
  Image.AltText:=AInfo.Name;
  Image.Ghosted:=AGhosted;
  Image.SetConstraintWidth(asmFixed,ArosaCoord(FThumbnailSize));
  Image.SetConstraintHeight(asmFixed,ArosaCoord(FThumbnailSize));
  ARow.AddObject(Image);
  Result:=True;
end;

function TAFileManagerController.AddSemanticDetailsIcon(
  ARow: TArosaListRow; const AInfo: TArosaFileInfo;
  AGhosted: Boolean): Boolean;
var
  Img: TArosaPlatformHandle;
  Src: TArosaRect;
  Semantic: string;
  Image: TArosaImageBox;
begin
  Result:=False;
  if ARow=nil then Exit;
  Semantic:=SemanticFileIconName(AInfo);

  if not LoadThemeIcon('theme:'+Semantic,Img,Src) then
  begin
    if SameText(Semantic,'trash') then
    begin
      if not LoadThemeIcon('theme:delete',Img,Src) then
        if not LoadThemeIcon('theme:folder',Img,Src) then Exit;
    end
    else if AInfo.Kind=afekDirectory then
    begin
      if not LoadThemeIcon('theme:folder',Img,Src) then Exit;
    end
    else if not LoadThemeIcon('theme:file',Img,Src) then Exit;
  end;

  Image:=TArosaImageBox.CreateControl(FTheme,FFonts);
  Image.Bitmap:=Img;
  Image.SourceRect:=Src;
  Image.StretchMode:=aismFit;
  Image.AltText:=AInfo.Name;
  Image.Ghosted:=AGhosted;
  Image.SetConstraintWidth(asmFixed,ArosaCoord(FThumbnailSize));
  Image.SetConstraintHeight(asmFixed,ArosaCoord(FThumbnailSize));
  ARow.AddObject(Image);
  Result:=True;
end;

procedure TAFileManagerController.PopulateDetailsRow(
  ARow: TArosaListRow; const AInfo: TArosaFileInfo; AView: Integer);
var
  Sz, Dt, Perm, Id: string;
  Hidden, Remote: Boolean;
  I: Integer;
  NameCell: TArosaLabel;

  function Cell(const AText, ASection: string;
    ADefaultWidth: Integer; AAlign: Integer): TArosaLabel;
  begin
    Result:=NewDetailsCell(AText,ASection,ADefaultWidth,AAlign);
    if Hidden then Result.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  end;

  procedure AddColumnVisual(const AId: string);
  begin
    if not IsConfiguredColumnVisible(AId) then Exit;

    if SameText(AId,'resource.thumbnail') then
    begin
      { Thumbnail decoding crosses native DataTypes/image resources. A bad or
        temporarily unavailable rendition must never make directory browsing
        fail: fall back to the semantic file icon and record the resource. }
      try
        if not TryAddCompactThumbnail(ARow,AInfo,AView,Hidden) then
          if not AddSemanticDetailsIcon(ARow,AInfo,Hidden) then
            ARow.AddObject(Cell('','Thumbnail',FThumbnailSize,AROSA_ALIGN_CENTER));
      except
        on E: Exception do
        begin
          Diagnostic('THUMBNAIL failed path='+AInfo.FullPath+' error='+E.Message);
          if not AddSemanticDetailsIcon(ARow,AInfo,Hidden) then
            ARow.AddObject(Cell('','Thumbnail',FThumbnailSize,AROSA_ALIGN_CENTER));
        end;
      end;
    end
    else if SameText(AId,'resource.type') then
      ARow.AddObject(Cell(ResourceTypeName(AInfo),'Type',72,AROSA_ALIGN_NEAR))
    else if SameText(AId,'resource.name') then
    begin
      NameCell:=Cell(AInfo.Name,'Name',260,AROSA_ALIGN_NEAR);
      { the name says where the thing is: remote names take the remote
        colour (which also wins over the dimming of hidden files) }
      if Remote and (RemoteTextRole<>'') then NameCell.TextRole:=RemoteTextRole;
      ARow.AddObject(NameCell);
    end
    else if SameText(AId,'resource.size') then
      ARow.AddObject(Cell(Sz,'Size',76,AROSA_ALIGN_FAR))
    else if SameText(AId,'resource.modified') then
      ARow.AddObject(Cell(Dt,'Modified',138,AROSA_ALIGN_NEAR))
    else if SameText(AId,'resource.permissions') then
      ARow.AddObject(Cell(Perm,'Permissions',96,AROSA_ALIGN_NEAR));
  end;

begin
  if ARow=nil then Exit;
  Remote:=IsRemoteLocation(AInfo.FullPath);
  if Remote then
  begin
    ARow.UserFlags:=ARow.UserFlags or AFM_ROW_REMOTE;
    { icon views and plain rows are drawn by the list itself }
    ARow.TextRole:=RemoteTextRole;
  end;

  { Keep row metadata independent of visual mode. Remote preview policy and
    other selection operations can then reuse the LIST metadata in icon and
    Workbench views too, without a follow-up STAT. }
  ARow.SetSortKey('resource.thumbnail','');
  ARow.SetSortKey('resource.type',ResourceTypeName(AInfo));
  ARow.SetSortKey('resource.name',AInfo.Name);
  if AInfo.Kind=afekDirectory then
    ARow.SetSortKey('resource.size','')
  else
    ARow.SetSortKey('resource.size',Format('%.20d',[AInfo.Size]));
  if AInfo.ModifiedUtc>0 then
    ARow.SetSortKey('resource.modified',FormatDateTime('yyyymmddhhnnss',AInfo.ModifiedUtc))
  else
    ARow.SetSortKey('resource.modified','');
  if AInfo.ReadOnly then ARow.SetSortKey('resource.permissions','1')
  else ARow.SetSortKey('resource.permissions','0');

  if ((AView=0) and (FLeftViewMode in [2,3])) or
     ((AView=1) and (FRightViewMode in [2,3])) then
  begin
    PopulateIconRow(ARow,AInfo,
      ((AView=0) and (FLeftViewMode=3)) or
      ((AView=1) and (FRightViewMode=3)));
    Exit;
  end;

  Hidden:=IsHiddenResource(AInfo);

  if AInfo.Kind=afekDirectory then Sz:='' else Sz:=SizeText(AInfo.Size);
  if AInfo.ModifiedUtc>0 then
    Dt:=FormatDateTime('yyyy-mm-dd hh:nn',AInfo.ModifiedUtc)
  else
    Dt:='';
  if AInfo.ReadOnly then
    Perm:=LocalText('afilemanager_permission_read_only','read-only')
  else
    Perm:=LocalText('afilemanager_permission_read_write','read/write');

  if FColumnOrder<>nil then
    for I:=0 to FColumnOrder.Count-1 do
    begin
      Id:=Trim(FColumnOrder[I]);
      if Id<>'' then AddColumnVisual(Id);
    end;
end;

procedure TAFileManagerController.ConfigureDetailsColumns(
  AList: TArosaListView);
var
  I: Integer;
  Id: string;

  procedure AddConfigured(const AId: string);
  begin
    if not IsConfiguredColumnVisible(AId) then Exit;

    if SameText(AId,'resource.thumbnail') then
    begin
      with AList.AddColumn('resource.thumbnail','',
        ArosaCoord(FThumbnailSize),AROSA_ALIGN_CENTER) do
        Sortable:=False;
    end
    else if SameText(AId,'resource.type') then
      AList.AddColumn('resource.type',
        LocalValue(FDescriptor.Value('Column.Type','Caption',
          '@afilemanager_column_type'),'Type'),
        ArosaCoord(ColumnWidth('Type',72)),AROSA_ALIGN_NEAR)
    else if SameText(AId,'resource.name') then
      AList.AddColumn('resource.name',
        LocalValue(FDescriptor.Value('Column.Name','Caption',
          '@afilemanager_column_name'),'Name'),
        ArosaCoord(ColumnWidth('Name',260)),AROSA_ALIGN_NEAR)
    else if SameText(AId,'resource.size') then
      AList.AddColumn('resource.size',
        LocalValue(FDescriptor.Value('Column.Size','Caption',
          '@afilemanager_column_size'),'Size'),
        ArosaCoord(ColumnWidth('Size',76)),AROSA_ALIGN_FAR)
    else if SameText(AId,'resource.modified') then
      AList.AddColumn('resource.modified',
        LocalValue(FDescriptor.Value('Column.Modified','Caption',
          '@afilemanager_column_modified'),'Date modified'),
        ArosaCoord(ColumnWidth('Modified',138)),AROSA_ALIGN_NEAR)
    else if SameText(AId,'resource.permissions') then
      AList.AddColumn('resource.permissions',
        LocalValue(FDescriptor.Value('Column.Permissions','Caption',
          '@afilemanager_column_permissions'),'Permissions'),
        ArosaCoord(ColumnWidth('Permissions',96)),AROSA_ALIGN_NEAR);
  end;

begin
  if AList=nil then Exit;
  AList.ClearColumns;
  AList.HeaderHeight:=ArosaCoord(23);

  if FColumnOrder<>nil then
    for I:=0 to FColumnOrder.Count-1 do
    begin
      Id:=Trim(FColumnOrder[I]);
      if Id<>'' then AddConfigured(Id);
    end;

  AList.HeaderVisible:=AList.ColumnCount>0;
  AList.SetDefaultSort(FDefaultSortColumn,FDefaultSortAscending);
end;

function TAFileManagerController.BuildDetailsHeader: TArosaRowPanel;
  function AddHeader(const ASection, ACaption: string; ADefaultWidth: Integer): TArosaLabel;
  var W: Integer;
  begin
    Result:=TArosaLabel.CreateControl(FTheme,FFonts);
    Result.Text:=ACaption;
    Result.FontFamily:=FFileFont.Description.Family;
    Result.FontSize:=FFileFont.Description.SizePoints;
    Result.BackgroundRole:=AROSA_ROLE_TAB_INACTIVE;
    Result.BorderVisible:=True;
    Result.BorderRole:=AROSA_ROLE_BORDER;
    Result.Padding:=ArosaMargins(5,0,5,0);
    W:=ColumnWidth(ASection,ADefaultWidth);
    Result.SetConstraintWidth(asmFixed,ArosaCoord(W));
    Result.SetConstraintHeight(asmFixed,ArosaCoord(23));
  end;
var L: TArosaLabel;
begin
  Result:=TArosaRowPanel.Create;
  Result.Spacing:=ArosaCoord(0);
  Result.SetConstraintHeight(asmFixed,ArosaCoord(23));
  if FShowThumbnails then begin L:=AddHeader('Thumbnail','',FThumbnailSize); Result.AddVisual(L); end;
  if FDescriptor.BoolValue('Column.Type','Visible',True) then begin
    L:=AddHeader('Type',LocalValue(FDescriptor.Value('Column.Type','Caption','@afilemanager_column_type'),'Type'),72); Result.AddVisual(L); end;
  if FDescriptor.BoolValue('Column.Name','Visible',True) then begin
    L:=AddHeader('Name',LocalValue(FDescriptor.Value('Column.Name','Caption','@afilemanager_column_name'),'Name'),260); Result.AddVisual(L); end;
  if FDescriptor.BoolValue('Column.Size','Visible',True) then begin
    L:=AddHeader('Size',LocalValue(FDescriptor.Value('Column.Size','Caption','@afilemanager_column_size'),'Size'),76); Result.AddVisual(L); end;
  if FDescriptor.BoolValue('Column.Modified','Visible',True) then begin
    L:=AddHeader('Modified',LocalValue(FDescriptor.Value('Column.Modified','Caption','@afilemanager_column_modified'),'Date modified'),138); Result.AddVisual(L); end;
  if FDescriptor.BoolValue('Column.Permissions','Visible',True) then begin
    L:=AddHeader('Permissions',LocalValue(FDescriptor.Value('Column.Permissions','Caption','@afilemanager_column_permissions'),'Permissions'),96); Result.AddVisual(L); end;
end;

procedure TAFileManagerController.SyncDetailsHeader(
  AHeader: TArosaRowPanel; AOffset: Integer);
var
  I: Integer;
  X, W, H: TArosaCoord;
  R: TArosaRect;
begin
  if AHeader=nil then Exit;
  X := -ArosaCoord(AOffset);
  H := ArosaRectHeight(AHeader.Bounds);
  for I := 0 to AHeader.ChildVisualCount-1 do
  begin
    if not AHeader.ChildVisuals[I].Visible then Continue;
    R := AHeader.ChildVisuals[I].Bounds;
    W := ArosaRectWidth(R);
    AHeader.ChildVisuals[I].Arrange(ArosaRectRaw(X,0,X+W,H));
    X := X + W + AHeader.Spacing;
  end;
  AHeader.InvalidatePaint;
end;

procedure TAFileManagerController.LeftHorizontalScroll(
  ASender: TArosaControl; AValue: Integer);
begin
  SyncDetailsHeader(FLeftColumns,AValue);
end;


procedure TAFileManagerController.ClearLeftFilterClick(ASender: TArosaControl);
begin if FLeftFilter<>nil then FLeftFilter.Text:=''; LeftFilterChanged(ASender); end;
procedure TAFileManagerController.ClearRightFilterClick(ASender: TArosaControl);
begin if FRightFilter<>nil then FRightFilter.Text:=''; RightFilterChanged(ASender); end;
procedure TAFileManagerController.ClearLeftSearchClick(ASender: TArosaControl);
begin if FLeftSearch<>nil then FLeftSearch.Text:=''; ApplyResourceSearch(0); end;
procedure TAFileManagerController.ClearRightSearchClick(ASender: TArosaControl);
begin if FRightSearch<>nil then FRightSearch.Text:=''; ApplyResourceSearch(1); end;

procedure TAFileManagerController.ApplyResourceSearch(AView: Integer);
var Box: TArosaTextBox; List: TArosaFilteredListView; Results: TStringList;
  Opt: TArosaResourceSearchOptions; I: Integer; Info: TArosaFileInfo; R: TArosaListRow;
begin
  if AView=0 then Box:=FLeftSearch else Box:=FRightSearch;
  List:=ViewList(AView);
  if (Box=nil) or (List=nil) then Exit;
  if Trim(Box.Text)='' then begin RefreshView(AView); Exit; end;
  { ResourceSearch is currently a local-filesystem service.  Do not let a
    provider URI fall through to filesystem pattern matching: on AmigaDOS a
    URI scheme can be interpreted as a volume name and open an Insert Volume
    requester.  Provider-side search can be enabled when Location Service
    exposes that capability explicitly. }
  if IsProviderLocation(ViewCurrent(AView)) then
  begin
    SetStatus('Search is not yet supported by this remote location provider');
    Exit;
  end;
  Results:=TStringList.Create;
  try
    Opt.Recursive:=FDescriptor.BoolValue('Search','Recursive',True);
    Opt.IncludeFiles:=FDescriptor.BoolValue('Search','IncludeFiles',True);
    Opt.IncludeFolders:=FDescriptor.BoolValue('Search','IncludeFolders',True);
    Opt.CaseSensitive:=FDescriptor.BoolValue('Search','CaseSensitive',False);
    Opt.MaxResults:=StrToIntDef(FDescriptor.Value('Search','MaxResults','2000'),2000);
    SetStatus('Searching '+ViewCurrent(AView)+' for '+Box.Text+' ...');
    { Plain text is a substring search. Explicit AmigaDOS patterns retain
      their native meaning. This keeps the search box useful without forcing
      users to type #? around ordinary names. }
    if FDescriptor.BoolValue('Search','SimpleSubstring',True) and
       (Pos('#?',Box.Text)=0) and (Pos('*',Box.Text)=0) and
       (Pos('?',Box.Text)=0) and (Pos('(',Box.Text)=0) then
    begin
      if not FSearchService.Search(ViewCurrent(AView),'#?'+Box.Text+'#?',Opt,Results) then begin
        SetStatus('Search cancelled'); Exit; end;
    end
    else if not FSearchService.Search(ViewCurrent(AView),Box.Text,Opt,Results) then begin
      SetStatus('Search cancelled'); Exit; end;
    List.Clear;
    for I:=0 to Results.Count-1 do if FPaths.GetInfo(Results[I],Info) then begin
      R:=List.NewRow(DetailsRow(Info)); R.Tags:=Results[I];
      R.SearchText:=Info.Name+' '+Results[I]; PopulateDetailsRow(R,Info,FActiveView);
      { Recursive search results retain their full resource path so the user
        can distinguish equal names from different directories. }
      R.Text:=Results[I];
    end;
    List.SetSearchPattern('');
    if AView=0 then List.SetFilter(FLeftFilter.Text)
    else if FRightFilter<>nil then List.SetFilter(FRightFilter.Text);
    UpdatePaneInfo(AView);
    SetStatus('Search completed: '+IntToStr(Results.Count)+' match(es)');
  finally Results.Free; end;
end;

procedure TAFileManagerController.PropertiesClick(ASender: TArosaControl);
var I: Integer;
begin
  I:=ViewList(FActiveView).SelectedIndex;
  if I<0 then begin SetStatus('Select a resource to view properties'); Exit; end;
  ShowProperties(FActiveView,SelectedPath(FActiveView,I));
end;

procedure TAFileManagerController.EditPermissionsClick(
  ASender: TArosaControl);
var
  L: TArosaFilteredListView;
  I: Integer;
  P: string;
  Paths: TStringList;
begin
  L:=ViewList(FActiveView);
  if L=nil then Exit;

  if L.SelectedCount=0 then
  begin
    SetStatus(LocalText('afilemanager_status_select_permissions',
      'Select one or more resources to edit permissions'));
    Exit;
  end;

  Paths:=TStringList.Create;
  try
    for I:=0 to L.ItemCount-1 do
      if L.IsItemSelected(I) then
      begin
        P:=SelectedPath(FActiveView,I);
        if IsProviderLocation(P) then
        begin
          SetStatus(LocalText('afilemanager_status_permissions_local_only',
            'Permission editing is currently available for local resources only'));
          Exit;
        end;
        Paths.Add(P);
      end;

    if (Paths.Count>0) and (FPermissionDialog<>nil) then
      FPermissionDialog.ShowForResources(Paths);
  finally
    Paths.Free;
  end;

  if ASender=nil then ;
end;

procedure TAFileManagerController.PermissionChanged(
  ASender: TArosaControl; APaths: TStrings);
var
  L:TArosaFilteredListView;
  I:Integer;
  P:string;
begin
  { Refresh after permission mutation, then restore the user's exact resource
    selection by path. A security edit must not throw the user out of the
    context from which it was invoked. }
  if (APaths<>nil) and (APaths.Count>0) then
    for I:=0 to APaths.Count-1 do
    begin
      if FLocations<>nil then P:=FLocations.Parent(APaths[I])
      else P:=ParentPath(APaths[I]);
      if P<>'' then PublishLocationChanged(P,almkMetadata);
    end
  else
    RefreshView(FActiveView);

  L:=ViewList(FActiveView);
  if (L<>nil) and (APaths<>nil) then
  begin
    L.ClearSelection;
    for I:=0 to L.ItemCount-1 do
    begin
      P:=SelectedPath(FActiveView,I);
      if APaths.IndexOf(P)>=0 then
        L.SelectItem(I);
    end;
  end;

  if (L<>nil) and (L.SelectedCount>0) then
    UpdatePreview(FActiveView);

  if (APaths<>nil) and (APaths.Count>1) then
    SetStatus(LocalText('afilemanager_status_permissions_updated',
      'Permissions updated')+': '+IntToStr(APaths.Count)+' resources')
  else if (APaths<>nil) and (APaths.Count=1) then
    SetStatus(LocalText('afilemanager_status_permissions_updated',
      'Permissions updated')+': '+APaths[0])
  else
    SetStatus(LocalText('afilemanager_status_permissions_updated',
      'Permissions updated'));

  if ASender=nil then ;
end;

procedure TAFileManagerController.RightHorizontalScroll(
  ASender: TArosaControl; AValue: Integer);
begin
  SyncDetailsHeader(FRightColumns,AValue);
end;

procedure TAFileManagerController.ToggleHiddenFilesClick(ASender: TArosaControl);
begin
  FShowHiddenFiles := not FShowHiddenFiles;
  RefreshView(FActiveView);
  if FRightList<>nil then RefreshView(1-FActiveView);
  UpdateViewToolbarState;
  if FShowHiddenFiles then SetStatus('Hidden files shown')
  else SetStatus('Hidden files hidden');
end;

procedure TAFileManagerController.ToggleThumbnailsClick(ASender: TArosaControl);
var
  S: TAFMConfigurationSettings;
begin
  FShowThumbnails:=not FShowThumbnails;

  { Persist through the controller's real configuration API so the toolbar
    toggle and Configuration dialog remain one setting. }
  S:=CurrentConfigurationSettings;
  S.ShowThumbnails:=FShowThumbnails;
  SaveUserConfiguration(S);

  ConfigureDetailsColumns(FLeftList);
  if FRightList<>nil then ConfigureDetailsColumns(FRightList);
  ApplyFileViewGeometry(0);
  if FRightList<>nil then ApplyFileViewGeometry(1);
  RefreshView(0);
  if FRightList<>nil then RefreshView(1);
  UpdateViewToolbarState;

  if FShowThumbnails then SetStatus('Resource thumbnails shown')
  else SetStatus('Resource thumbnails hidden');

  if ASender=nil then ;
end;

function TAFileManagerController.IsHiddenResource(const AInfo: TArosaFileInfo): Boolean;
var N: string;
begin
  N:=ExtractFileName(AInfo.Name);
  { Amiga/AROS semantics: .info is companion presentation metadata. It is
    hidden as a separate file unless Show hidden files is enabled; Icon view
    consumes it to render the corresponding resource. Dot files are hidden too. }
  Result:=(LowerCase(ExtractFileExt(N))='.info') or
    ((Length(N)>1) and (N[1]='.') and (N<>'.') and (N<>'..'));
end;

function TAFileManagerController.IsArchivePath(const APath: string): Boolean;
var E: string;
begin
  { Provider locations are logical URIs, not AmigaDOS paths.  DataTypes may
    inspect its input through dos.library, so never hand it a scheme:// URI
    merely to decide whether a context-menu archive command is applicable.
    Remote resources are classified from their transport name only; once
    materialised, the local cache path may be identified through DataTypes. }
  E:=LowerCase(ExtractFileExt(APath));
  if IsProviderLocation(APath) then
    Exit((E='.lha') or (E='.lzh') or (E='.lzx') or (E='.zip') or
      (E='.tar') or (E='.tgz') or (E='.gz'));
  if (FDataTypes<>nil) and (FDataTypes.GroupOf(APath)=adtgArchive) then Exit(True);
  Result:=(E='.lha') or (E='.lzh') or (E='.lzx') or (E='.zip') or
    (E='.tar') or (E='.tgz') or (E='.gz');
end;

procedure TAFileManagerController.ArchiveExtractHere(ASender: TArosaControl);
var L: TArosaFilteredListView; P,Ext,Fmt: string;
begin
  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedCount<>1) then begin SetStatus('Select one archive'); Exit; end;
  P:=SelectedPath(FActiveView,L.SelectedIndex);
  if not IsArchivePath(P) then begin SetStatus('Selected resource is not an archive'); Exit; end;
  Ext:=LowerCase(ExtractFileExt(P));
  if (Ext='.lha') or (Ext='.lzh') or (Ext='.lzx') then Fmt:='LHA'
  else if Ext='.zip' then Fmt:='ZIP' else Fmt:='TAR';
  FArchiveDialogMode:=1; FArchiveSourcePath:=P; FArchiveToOtherPane:=False;
  if FArchiveDialog<>nil then
  begin
    FArchiveDialog.ShowArchiveDialog('Expand archive',ExtractFileName(P),
      ViewCurrent(FActiveView),'Expand',[Fmt]);
    if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
  end else SetStatus('Archive dialog unavailable');
end;

procedure TAFileManagerController.ArchiveExtractTo(ASender: TArosaControl);
begin
  { "Expand to ..." uses the same retained dialog, with the target-location
    field ready for editing. The default remains the archive's current folder. }
  ArchiveExtractHere(ASender);
end;

function TAFileManagerController.ValidateArchiveSourceReadable(
  const APath: string; out AError: string): Boolean;
var
  Info: TArosaFileInfo;
  Entries: TArosaFileInfoArray;
  I: Integer;
  S: TStream;
begin
  Result:=False; AError:='';
  if not FPaths.GetInfo(APath,Info) then
  begin
    AError:='Cannot inspect archive source: '+APath;
    Exit;
  end;
  if Info.Kind=afekDirectory then
  begin
    if not FPaths.Enumerate(APath,Entries) then
    begin
      AError:='Cannot enumerate archive source folder: '+APath;
      Exit;
    end;
    for I:=0 to High(Entries) do
      if not ValidateArchiveSourceReadable(Entries[I].FullPath,AError) then Exit;
    Result:=True;
    Exit;
  end;
  S:=nil;
  if not FFiles.OpenRead(APath,S) then
  begin
    AError:='Cannot read '+APath+': '+FFiles.ExplainReadFailure(APath);
    Exit;
  end;
  S.Free;
  Result:=True;
end;

function TAFileManagerController.UploadLocalTreeToLocation(const ALocalDir,
  ARemoteDir: string; out AError: string): Boolean;
var Entries: TArosaFileInfoArray; I: Integer; LocalPath, RemotePath: string;
begin
  Result:=False; AError:='';
  if (FPaths=nil) or (FLocationResourceAccess=nil) then
  begin
    AError:='Resource access service is unavailable';
    Exit;
  end;

  { Ensure every directory in the staged extraction exists remotely.  Existing
    directories are merged; a file occupying a required directory path is
    replaced only when the provider exposes the necessary mutation methods. }
  if FLocationResourceAccess.Exists(ARemoteDir) then
  begin
    if not FLocationResourceAccess.IsDirectory(ARemoteDir) then
    begin
      if not FLocationResourceAccess.DeleteFile(ARemoteDir) then
      begin AError:='Cannot replace remote file with folder: '+ARemoteDir; Exit; end;
      if not FLocationResourceAccess.CreateDirectory(ARemoteDir) then
      begin AError:='Cannot create remote folder: '+ARemoteDir; Exit; end;
    end;
  end
  else if not FLocationResourceAccess.CreateDirectory(ARemoteDir) then
  begin
    AError:='Cannot create remote folder: '+ARemoteDir;
    Exit;
  end;

  if not FPaths.Enumerate(ALocalDir,Entries) then
  begin
    AError:='Cannot enumerate extraction staging folder: '+ALocalDir;
    Exit;
  end;
  for I:=0 to High(Entries) do
  begin
    if (Entries[I].Name='.') or (Entries[I].Name='..') then Continue;
    LocalPath:=FPaths.Join(ALocalDir,Entries[I].Name);
    RemotePath:=FLocationResourceAccess.Join(ARemoteDir,Entries[I].Name);
    if Entries[I].Kind=afekDirectory then
    begin
      if not UploadLocalTreeToLocation(LocalPath,RemotePath,AError) then Exit;
    end
    else
    begin
      if FLocationResourceAccess.Exists(RemotePath) and
         FLocationResourceAccess.IsDirectory(RemotePath) then
        if not FLocationResourceAccess.RemoveDirectory(RemotePath) then
        begin AError:='Cannot replace remote folder with file: '+RemotePath; Exit; end;
      if not FLocationResourceAccess.CopyFile(LocalPath,RemotePath) then
      begin
        AError:='Cannot store extracted file at '+RemotePath;
        Exit;
      end;
    end;
  end;
  Result:=True;
end;

procedure TAFileManagerController.ArchiveCompressHere(ASender: TArosaControl);
var L: TArosaFilteredListView; I: Integer; P,Proposed,CurName: string; Formats: TStringArray;
begin
  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedCount=0) then begin SetStatus('Select resources to compress'); Exit; end;
  Proposed:='Archive';
  if L.SelectedCount=1 then
  begin
    I:=L.SelectedIndex; P:=SelectedPath(FActiveView,I);
    Proposed:=ChangeFileExt(ExtractFileName(P),'');
  end
  else begin
    CurName:=ExtractFileName(ViewCurrent(FActiveView));
    if CurName<>'' then Proposed:=CurName;
  end;
  FArchiveDialogMode:=0; FArchiveSourcePath:=''; FArchiveToOtherPane:=False;
  Diagnostic('COMMAND Archive.CompressHere awaiting-input selection='+IntToStr(L.SelectedCount));
  if FArchiveDialog<>nil then
  begin
    { 0.5.110.59: offer only formats whose archiver is installed. }
    Formats:=AvailableArchiveFormats;
    if Length(Formats)=0 then
    begin
      SetStatus('No archiver is installed: C:zip, C:lha and C:tar were not found');
      Exit;
    end;
    FArchiveDialog.ShowArchiveDialog('Compress selected',Proposed,
      ViewCurrent(FActiveView),'Compress',Formats);
    SetStatus('Waiting for input: archive name, format and destination');
    Diagnostic('DIALOG archive visible='+BoolToStr(FArchiveDialog.Visible,True));
    if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
  end else SetStatus('Archive dialog unavailable');
end;

procedure TAFileManagerController.ArchiveCompressTo(ASender: TArosaControl);
begin
  { "Compress to ..." intentionally starts from the same-folder default; the
    target-location field is editable and is the canonical destination. }
  ArchiveCompressHere(ASender);
end;

procedure TAFileManagerController.ConfirmArchiveOverwrite(ASender: TArosaControl);
begin
  { The confirmation dialog has already dismissed itself. Run the original
    operation with a one-shot authorization; never launch an interactive zip. }
  FArchiveOverwriteApproved:=True;
  try
    ArchiveDialogCreate(nil,FPendingArchiveName,FPendingArchiveFormat,
      FPendingArchiveLocation,FPendingArchivePassword);
  finally
    FArchiveOverwriteApproved:=False;
    FPendingArchivePassword:='';
  end;
end;

procedure TAFileManagerController.CancelArchiveOverwrite(ASender: TArosaControl);
begin
  FArchiveOverwriteApproved:=False;
  FPendingArchivePassword:='';
  SetStatus('Archive replacement cancelled');
end;

{ 0.5.110.51 archive argument helpers.  Argument vectors are LF-separated
  (decoded by TArosaShellService.RunCommand); never emit a separator before
  the first argument. }
procedure AppendArchiveArg(var AArgs: string; const AValue: string);
begin
  if AArgs='' then AArgs:=AValue else AArgs:=AArgs+#10+AValue;
end;

{ Member name relative to ABase (the archiver's working directory) when the
  resource lives directly in it; otherwise the full path is kept. }
function ArchiveMemberName(const APath, ABase: string): string;
var Dir, Base: string;
begin
  Result:=APath;
  Base:=ABase;
  if Base='' then Exit;
  if not (Base[Length(Base)] in [':','/']) then Base:=Base+'/';
  Dir:=ExtractFilePath(APath);
  if (Dir<>'') and (not (Dir[Length(Dir)] in [':','/'])) then Dir:=Dir+'/';
  if SameText(Dir,Base) then Result:=ExtractFileName(APath);
end;

procedure TAFileManagerController.ArchiveDialogCreate(ASender: TArosaControl;
  const AArchiveName, AFormat, ALocation, APassword: string);
var
  L: TArosaFilteredListView;
  I: Integer;
  ArchivePath, BuildPath, BackupPath, Args, OutText, P, Dest, Ext, Exe: string;
  Replacing: Boolean;
  Expected: TArosaArchiveExpectations;
  Info: TArosaFileInfo;
  ListExe, ListArgs, Listing, Problems, VerifyNote, Before: string;
  ProblemList: TStringList;
  Verdict: TArosaArchiveVerdict;
  RemoteDest, StagingDir, MaterializeError: string;
  Content: TArosaContentDescriptor;
  ListingFormat: Arosa.Services.ArchiveListing.TArosaArchiveFormat;
  ListingEntries: Arosa.Services.ArchiveListing.TArosaArchiveEntryArray;
  ListingError, ConflictTarget: string;
  ConflictCount, EntryIndex: Integer;
  EntryTargetIsDir: Boolean;
begin
  Expected:=nil;
  Diagnostic('COMMAND Archive.Create input-received format='+AFormat+' location='+ALocation);
  Dest:=Trim(ALocation);
  if Dest='' then Dest:=ViewCurrent(FActiveView);
  { Native archive tools always run on local paths.  Provider resources are
    bridged through Content/Location services: remote archive inputs are
    materialised locally; remote extraction targets use a local staging tree
    whose files are stored back through the provider after extraction. }
  RemoteDest:='';
  StagingDir:='';
  if (FArchiveDialogMode=0) and IsProviderLocation(Dest) then
  begin
    SetStatus('Remote archive creation is not enabled yet; expand-to/from remote is supported first.');
    Exit;
  end;
  if (FArchiveDialogMode=1) and IsProviderLocation(Dest) then
  begin
    RemoteDest:=Dest;
    StagingDir:=FPaths.Join(FPaths.TemporaryDirectory,
      'arosa-expand-'+FormatDateTime('hhnnsszzz',Now));
    if not FFiles.CreateDirectoryTree(StagingDir) then
    begin
      SetStatus('Cannot create local extraction staging folder: '+StagingDir);
      Exit;
    end;
    Dest:=StagingDir;
  end;
  if not FPaths.Exists(Dest) then
    if not FFiles.CreateDirectoryTree(Dest) then
    begin
      SetStatus('Cannot create target location: '+Dest);
      Exit;
    end;
  if not FPaths.IsDirectory(Dest) then
  begin
    SetStatus('Target is not a folder: '+Dest);
    Exit;
  end;

  if FArchiveDialogMode=1 then
  begin
    P:=FArchiveSourcePath;
    if not IsArchivePath(P) then
    begin
      SetStatus('Archive is no longer available');
      Exit;
    end;
    if IsProviderLocation(P) then
    begin
      if (FContent=nil) or not FContent.AcquireOriginal(P,Content,MaterializeError) then
      begin
        SetStatus('Cannot retrieve remote archive: '+MaterializeError);
        if StagingDir<>'' then DeleteResourceRecursive(StagingDir);
        Exit;
      end;
      P:=Content.PhysicalPath;
    end;
    if SameText(AFormat,'ZIP') then
    begin
      { Native unzip prompts interactively when a destination file already
        exists.  AFileManager owns that policy: preflight the portable ZIP
        listing, ask once through the retained AROSA requester, then invoke
        unzip non-interactively with -o only after explicit approval.  An
        existing directory matching a directory entry is a normal merge, not
        a conflict; file/folder type clashes and existing files are conflicts. }
      ConflictCount:=0;
      ListingEntries:=nil;
      ListingError:='';
      if ArosaReadArchiveListing(P,ListingFormat,ListingEntries,ListingError) then
      begin
        for EntryIndex:=0 to High(ListingEntries) do
        begin
          if Trim(ListingEntries[EntryIndex].Name)='' then Continue;
          ConflictTarget:=FPaths.Join(Dest,ListingEntries[EntryIndex].Name);
          if not FPaths.Exists(ConflictTarget) then Continue;
          EntryTargetIsDir:=FPaths.IsDirectory(ConflictTarget);
          if ListingEntries[EntryIndex].IsDirectory then
          begin
            if not EntryTargetIsDir then Inc(ConflictCount);
          end
          else
            Inc(ConflictCount);
        end;
      end;
      if (ConflictCount>0) and (not FArchiveOverwriteApproved) then
      begin
        FPendingArchiveName:=AArchiveName;
        FPendingArchiveFormat:=AFormat;
        FPendingArchiveLocation:=ALocation;
        FPendingArchivePassword:=APassword;
        if FArchiveOverwriteDialog=nil then
        begin
          SetStatus('ZIP extraction would replace existing resources; confirmation unavailable');
          if StagingDir<>'' then DeleteResourceRecursive(StagingDir);
          Exit;
        end;
        FArchiveOverwriteDialog.ShowConfirmation('Replace extracted resources',
          IntToStr(ConflictCount)+' existing resource(s) conflict with this ZIP. Replace them?',
          'Replace','Cancel');
        if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
        if StagingDir<>'' then DeleteResourceRecursive(StagingDir);
        Exit;
      end;
      Exe:='C:unzip';
      Args:='-o';
      if APassword<>'' then begin AppendArchiveArg(Args,'-P'); AppendArchiveArg(Args,APassword); end;
      AppendArchiveArg(Args,P);
      AppendArchiveArg(Args,'-d');
      AppendArchiveArg(Args,Dest);
    end
    else if SameText(AFormat,'LHA') then
    begin
      if APassword<>'' then
      begin
        SetStatus('Password extraction is not supported by LHA');
        Exit;
      end;
      Exe:='C:lha'; Args:='x'+#10+P+#10+Dest;
    end
    else
    begin
      if APassword<>'' then
      begin
        SetStatus('Password extraction is not supported by TAR');
        Exit;
      end;
      Exe:='C:tar'; Args:='-xf'+#10+P+#10+'-C'+#10+Dest;
    end;
    if not ArchiverReady(Exe,AFormat) then Exit;
    { 0.5.110.60: success needs evidence - the destination must change. }
    Before:=DirectorySignature(Dest);
    if RunCommand(Exe,Args,ViewCurrent(FActiveView),OutText) then
    begin
      if RemoteDest<>'' then
      begin
        if DirectorySignature(Dest)=Before then
          SetStatus('Archiver reported success but produced no changed files in staging')
        else if not UploadLocalTreeToLocation(Dest,RemoteDest,MaterializeError) then
          SetStatus('Archive expanded locally but remote transfer failed: '+MaterializeError)
        else
        begin
          if FLocations<>nil then FLocations.Invalidate(RemoteDest,True);
          SetStatus('Expanded archive to remote location: '+RemoteDest);
        end;
        DeleteResourceRecursive(StagingDir);
        RefreshBoth;
      end
      else
      begin
        RefreshBoth;
        if DirectorySignature(Dest)=Before then
          { Unchanged can also mean every file was already present and
            identical (archivers restore original dates) - say only what
            is known. }
          SetStatus('Archiver reported success but '+Dest+' is unchanged: '+
            'the archive may be empty, or its files were already there')
        else
          SetStatus('Expanded archive to: '+Dest);
      end;
    end
    else
    begin
      if Trim(OutText)='' then OutText:=Exe+' returned an error without output';
      SetStatus('Archive expansion failed: '+OutText);
      if StagingDir<>'' then DeleteResourceRecursive(StagingDir);
    end;
    Exit;
  end;

  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedCount=0) then
  begin
    SetStatus('Selection is no longer available');
    Exit;
  end;
  if SameText(AFormat,'ZIP') then
  begin
    Ext:='.zip'; Exe:='C:zip'; Args:='';
    { MiniZip usage: zip [-o] [-a] [-0..-9] [-p password] [-j] file.zip files.
      Its password switch is lowercase -p; -P is Info-ZIP syntax. }
    if APassword<>'' then Args:='-p'+#10+APassword;
  end
  else if SameText(AFormat,'TAR') then
  begin
    if APassword<>'' then
    begin
      SetStatus('Password compression is not supported by TAR');
      Exit;
    end;
    Ext:='.tar'; Exe:='C:tar'; Args:='-cf';
  end
  else
  begin
    if APassword<>'' then
    begin
      SetStatus('Password compression is not supported by LHA');
      Exit;
    end;
    Ext:='.lha'; Exe:='C:lha'; Args:='a';
  end;
  ArchivePath:=FPaths.Join(Dest,ChangeFileExt(AArchiveName,Ext));
  Replacing:=FPaths.Exists(ArchivePath);
  if Replacing and (not FArchiveOverwriteApproved) then
  begin
    FPendingArchiveName:=AArchiveName;
    FPendingArchiveFormat:=AFormat;
    FPendingArchiveLocation:=ALocation;
    FPendingArchivePassword:=APassword;
    if FArchiveOverwriteDialog=nil then
    begin
      SetStatus('Archive already exists; confirmation unavailable');
      Exit;
    end;
    FArchiveOverwriteDialog.ShowConfirmation('Replace archive',
      'Replace existing archive '+ArchivePath+'?', 'Replace', 'Cancel');
    if FForm<>nil then
    begin
      FForm.InvalidateLayout;
      FForm.InvalidatePaint;
    end;
    Exit;
  end;

  { 0.5.110.59 (register R10/R12): EVERY format, ZIP included, builds into a
    staging file.  The result is verified from the archiver's own listing
    and only a valid archive is moved into place; an invalid one is deleted
    and an existing original is never touched.  (MiniZip previously
    overwrote in place with -o, so a bad result had already destroyed the
    original.)  The staging name never exists beforehand, so no overwrite
    switch is needed for any backend. }
  BuildPath:=ChangeFileExt(ArchivePath,'.arosa-new'+Ext);
  BackupPath:=ChangeFileExt(ArchivePath,'.arosa-backup'+Ext);
  if FPaths.Exists(BuildPath) or (Replacing and FPaths.Exists(BackupPath)) then
  begin
    SetStatus('Archive staging file already exists (left by an interrupted run); '+
      'remove it first: '+BuildPath);
    Exit;
  end;
  { 0.5.110.51: arguments are an LF-separated vector.  The separator is
    only emitted BETWEEN arguments.  The previous code prefixed #10 even
    when Args was empty (plain ZIP, no password), so MiniZip received an
    empty first argument: it created ".zip" and then tried to ADD the
    intended archive path as a member ("creating .zip / error adding
    RAM:Archive.zip").

    Members are passed relative to the working directory (the active view,
    which is where every selected item lives) so the archive stores plain
    names instead of volume-qualified paths. }
  AppendArchiveArg(Args,BuildPath);
  for I:=0 to L.ItemCount-1 do
    if L.IsItemSelected(I) then
    begin
      P:=SelectedPath(FActiveView,I);
      if (P<>'') and (ExtractFileName(P)<>'..') then
      begin
        { MiniZip 1.1 does not recurse into directories.  Refuse explicitly
          rather than producing an archive that silently lacks the content. }
        if SameText(AFormat,'ZIP') and FPaths.IsDirectory(P) then
        begin
          SetStatus('ZIP (MiniZip) cannot archive folders: '+P+
            ' - select files, or use LHA/TAR');
          Diagnostic('COMMAND Archive.Create refused directory-for-zip '+P);
          Exit;
        end;
        AppendArchiveArg(Args,ArchiveMemberName(P,ViewCurrent(FActiveView)));
        SetLength(Expected,Length(Expected)+1);
        if FPaths.GetInfo(P,Info) then
          Expected[High(Expected)]:=ArosaArchiveExpectation(
            ArchiveMemberName(P,ViewCurrent(FActiveView)),
            Info.Kind=afekDirectory,Info.Size,Info.Size)
        else
          Expected[High(Expected)]:=ArosaArchiveExpectation(
            ArchiveMemberName(P,ViewCurrent(FActiveView)),False,-1,-1);
      end;
    end;
  if not ArchiverReady(Exe,AFormat) then Exit;
  for I:=0 to L.ItemCount-1 do
    if L.IsItemSelected(I) then
    begin
      P:=SelectedPath(FActiveView,I);
      if (P<>'') and (ExtractFileName(P)<>'..') then
        if not ValidateArchiveSourceReadable(P,OutText) then
        begin
          SetStatus('Archive creation blocked: '+OutText);
          Diagnostic('COMMAND Archive.Create source-unreadable '+OutText);
          Exit;
        end;
    end;
  Diagnostic('COMMAND Archive.Create run exe='+Exe+' archive='+BuildPath);
  if not RunCommand(Exe,Args,ViewCurrent(FActiveView),OutText) then
  begin
    if Trim(OutText)='' then OutText:=Exe+' returned an error without output';
    SetStatus('Archive creation failed: '+OutText);
    Diagnostic('COMMAND Archive.Create failed output='+OutText);
    Exit;
  end;
  if not FPaths.Exists(BuildPath) then
  begin
    SetStatus('Archiver reported success but no archive was written: '+ArchivePath);
    Exit;
  end;

  { Verify against the archiver's own listing.  Sizes are re-read after the
    run so a source that changed while being archived is recognised. }
  for I:=0 to High(Expected) do
    if (not Expected[I].IsDirectory) and
       FPaths.GetInfo(FPaths.Join(ViewCurrent(FActiveView),Expected[I].Name),Info) then
      Expected[I].SizeAfter:=Info.Size;
  VerifyNote:='';
  Verdict:=aavValid;
  ProblemList:=TStringList.Create;
  try
    if not ArchiveListCommand(AFormat,BuildPath,ListExe,ListArgs) then
      VerifyNote:=' (contents not verified: '+ListExe+' is not installed)'
    else if not RunCommand(ListExe,ListArgs,ViewCurrent(FActiveView),Listing) then
      VerifyNote:=' (contents not verified: '+ListExe+' could not list the archive)'
    else
      Verdict:=ArosaVerifyArchiveListing(Listing,Expected,ProblemList);
    Problems:=StringReplace(Trim(ProblemList.Text),LineEnding,'; ',[rfReplaceAll]);
  finally
    ProblemList.Free;
  end;
  Diagnostic('COMMAND Archive.Verify verdict='+IntToStr(Ord(Verdict))+
    ' note='+VerifyNote+' problems='+Problems);
  if Verdict=aavInvalid then
  begin
    if not FFiles.DeleteFile(BuildPath) then
      Diagnostic('COMMAND Archive.Verify staging-retained path='+BuildPath);
    if Replacing then
      SetStatus('Archive NOT replaced, the original is unchanged: '+Problems)
    else
      SetStatus('Archive NOT created: '+Problems);
    Exit;
  end;

  if Replacing then
  begin
    if not FFiles.RenameFile(ArchivePath,BackupPath) then
    begin
      SetStatus('Cannot back up original archive; new archive remains at: '+BuildPath);
      Exit;
    end;
    if not FFiles.RenameFile(BuildPath,ArchivePath) then
    begin
      if FFiles.RenameFile(BackupPath,ArchivePath) then
        SetStatus('Archive replacement failed; original restored')
      else
        SetStatus('Archive replacement failed; original retained at: '+BackupPath);
      Exit;
    end;
    if not FFiles.DeleteFile(BackupPath) then
      Diagnostic('COMMAND Archive.Create backup-retained path='+BackupPath);
  end
  else if not FFiles.RenameFile(BuildPath,ArchivePath) then
  begin
    SetStatus('Archive was built but could not be moved into place; it remains at: '+BuildPath);
    Exit;
  end;
  RefreshBoth;
  if Verdict=aavValidWithWarnings then
    SetStatus('Created archive: '+ArchivePath+' - warning: '+Problems)
  else
    SetStatus('Created archive: '+ArchivePath+VerifyNote);
  Diagnostic('COMMAND Archive.Create completed archive='+ArchivePath);
end;

{ Runtime theme resources are self-contained under PROGDIR:themes.
  The application must not depend on the optional development Arosa: assign:
  probing an absent AmigaDOS volume/assign can raise an Insert Volume requester.
  Release packaging therefore merges the shared default theme into the
  application theme and this resolver searches packaged/descriptor layers only. }
function TAFileManagerController.ThemeIconPath(const AName: string): string;
var
  AliasName: string;

  function DefaultSvgAlias(const ASemantic: string): string;
  begin
    Result:='';
    { These are semantic equivalences, not file-format rules. They provide
      compatibility for current AIDEa artwork names while keeping the normal
      AROSA semantic name as the public request. Descriptor [IconAliases]
      entries override this built-in compatibility layer. }
    if SameText(ASemantic,'nav-up') then Result:='folder-up'
    else if SameText(ASemantic,'search') then Result:='find'
    else if SameText(ASemantic,'window-zoom') then Result:='maximize-window'
    else if SameText(ASemantic,'guide-contents') then Result:='documentation';
  end;

begin
  { Scalable theme icon resolution:
      1. exact semantic SVG
      2. descriptor/default SVG alias
      3. existing exact semantic PNG fallback

    Applications continue to request semantic icons. The theme/artwork layer
    decides which physical resource satisfies the request. }
  if FThemeLayers=nil then BuildThemeLayers;

  Result:=FThemeLayers.FindFile('icons/svg/'+AName+'.svg');
  if Result<>'' then
  begin
    ArosaTrace('ICON','resolved-svg semantic='+AName+' path='+Result);
    Exit;
  end;

  AliasName:='';
  if (FDescriptor<>nil) and FDescriptor.HasKey('IconAliases',AName) then
    AliasName:=Trim(FDescriptor.Value('IconAliases',AName,''));
  if SameText(AliasName,'none') then AliasName:='';
  if AliasName='' then AliasName:=DefaultSvgAlias(AName);
  if LowerCase(ExtractFileExt(AliasName))='.svg' then
    AliasName:=ChangeFileExt(AliasName,'');

  if AliasName<>'' then
  begin
    Result:=FThemeLayers.FindFile('icons/svg/'+AliasName+'.svg');
    if Result<>'' then
    begin
      ArosaTrace('ICON','resolved-svg-alias semantic='+AName+
        ' resource='+AliasName+' path='+Result);
      Exit;
    end;
  end;

  Result:=FThemeLayers.FindFile('icons/'+AName+'.png');
  if Result<>'' then
  begin
    ArosaTrace('ICON','resolved-png semantic='+AName+' path='+Result);
    Exit;
  end;

  Result:='';
  Diagnostic('ICON not-found name='+AName+
    ' after exact SVG / SVG alias / PNG layered theme lookup');
end;

{ 0.7.5.9: cache policy is AROSA service configuration (services.prefs:
  user layer first, then shared AROSA, then built-in defaults) }
procedure TAFileManagerController.ApplyServiceSettings;
var Settings: TArosaServiceSettings; I: Integer;
begin
  Settings:=TArosaServiceSettings.Create;
  try
    Settings.LoadDefaultLayers;
    Settings.ApplyTo(FLocations,FContent);
    for I:=0 to Settings.Report.Count-1 do Diagnostic('SERVICES '+Settings.Report[I]);
  finally
    Settings.Free;
  end;
end;

procedure TAFileManagerController.BuildThemeLayers;
var ThemeId: string;
begin
  { rebuilt from scratch: the descriptor base or selected installed theme may
    change while Configuration is open.  The selected package inherits the
    default package for any asset it does not provide. }
  FreeAndNil(FThemeLayers);
  FThemeLayers:=TArosaThemeLayers.Create;
  ThemeId:=Trim(FActiveThemePackageId);
  if ThemeId='' then ThemeId:='default';
  { Resource-manager theme chain:
      application overrides -> descriptor-local overrides -> shared AROSA.
    The shared layer is on SYS:, which is guaranteed by the running system.
    Never probe the optional development assign Arosa:, because an absent DOS
    assign can trigger an Insert Volume requester. }
  FThemeLayers.AddLayer('PROGDIR:themes/'+ThemeId+'/');
  if (FDescriptorBase<>'') and (not SameText(FDescriptorBase,'PROGDIR:')) then
    FThemeLayers.AddLayer(FDescriptorBase+'themes/'+ThemeId+'/');
  FThemeLayers.AddLayer('SYS:Arosa/themes/'+ThemeId+'/');

  if not SameText(ThemeId,'default') then
  begin
    FThemeLayers.AddLayer('PROGDIR:themes/default/');
    if (FDescriptorBase<>'') and (not SameText(FDescriptorBase,'PROGDIR:')) then
      FThemeLayers.AddLayer(FDescriptorBase+'themes/default/');
    FThemeLayers.AddLayer('SYS:Arosa/themes/default/');
  end;

  Diagnostic('THEME layers active package='+ThemeId+
    ' roots='+IntToStr(FThemeLayers.Count));
end;

{ per role: application theme.colours, then shared, then AROSA built-in;
  the window descriptor's [Bubbles.*] colours are applied later (most
  specific application layer). }
procedure TAFileManagerController.ApplyThemeColourLayers;
var R: TStringList; N: Integer;
begin
  if FThemeLayers=nil then BuildThemeLayers;
  R:=TStringList.Create;
  try
    N:=FThemeLayers.ApplyColours(FDarkTheme,'Dark',R);
    N:=N+FThemeLayers.ApplyColours(FLightTheme,'Light',R);
    Diagnostic('THEME colours from layers: '+IntToStr(N)+' role(s)'+
      StringReplace(LineEnding+Trim(R.Text),LineEnding,'; ',[rfReplaceAll]));
  finally
    R.Free;
  end;
end;

function TAFileManagerController.ArchiverReady(const AExecutable,
  AFormat: string): Boolean;
begin
  { 0.5.110.13: archive commands used to be launched blind. When the native
    archiver is not installed the process start fails with an empty output
    and the user saw "Archive creation failed:" followed by nothing, which
    looked like the command had not run at all. Check the backend first and
    say exactly what is missing. }
  Result:=FPaths.Exists(AExecutable);
  if Result then Exit;
  SetStatus(AFormat+' archiver is not available: '+AExecutable+
    ' was not found. Install it or choose another format.');
  Diagnostic('COMMAND Archive backend-missing format='+AFormat+' exe='+AExecutable);
end;

{ 0.5.110.59: format availability follows the installed archivers. }
function TAFileManagerController.AvailableArchiveFormats: TStringArray;
  procedure AddIf(const AExe, AFormat: string);
  begin
    if FPaths.Exists(AExe) then
    begin
      SetLength(Result,Length(Result)+1);
      Result[High(Result)]:=AFormat;
    end
    else
      Diagnostic('COMMAND Archive format-unavailable format='+AFormat+' exe='+AExe);
  end;
begin
  Result:=nil;
  AddIf('C:lha','LHA');
  AddIf('C:zip','ZIP');
  AddIf('C:tar','TAR');
end;

{ The archiver's own listing command for verification.  False (with AExe
  set) when that tool is not installed. }
function TAFileManagerController.ArchiveListCommand(const AFormat, AArchive: string;
  out AExe, AArgs: string): Boolean;
begin
  if SameText(AFormat,'ZIP') then begin AExe:='C:unzip'; AArgs:='-l'+#10+AArchive; end
  else if SameText(AFormat,'TAR') then begin AExe:='C:tar'; AArgs:='-tvf'+#10+AArchive; end
  else begin AExe:='C:lha'; AArgs:='l'+#10+AArchive; end;
  Result:=FPaths.Exists(AExe);
end;

procedure TAFileManagerController.ArchiveDialogCancel(ASender: TArosaControl);
begin
  Diagnostic('COMMAND Archive.Cancel cancelled');
  SetStatus('Archive operation cancelled');
end;

procedure TAFileManagerController.ArchiveBrowseLocation(ASender: TArosaControl);
begin
  if (FLocationPicker=nil) or (FArchiveDialog=nil) then Exit;
  FLocationPickerPurpose:='archive';
  FLocationPicker.ShowPicker(
    LocalText('afilemanager_select_target_location','Select target location'),
    FArchiveDialog.Location);
end;

procedure TAFileManagerController.MoveToSelected(ASender: TArosaControl);
var
  L: TArosaFilteredListView;
  I: Integer;
  P, StartLocation: string;
begin
  if FLocationPicker=nil then Exit;
  if ASender=FRightList then SetActiveView(1) else SetActiveView(0);
  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedCount=0) then Exit;

  FMoveToItems.Clear;
  CollectSelectedPaths(FActiveView,FMoveToItems);
  if (FMoveToItems.Count=0) and (L.SelectedIndex>=0) then
    FMoveToItems.Add(SelectedPath(FActiveView,L.SelectedIndex));
  if FMoveToItems.Count=0 then Exit;

  FMoveToView:=FActiveView;
  FLocationPickerPurpose:='move-to';
  StartLocation:=ViewCurrent(FActiveView);
  FLocationPicker.ShowPicker(
    LocalText('afilemanager_action_move_to','Move to...'),StartLocation);
end;

function TAFileManagerController.LocationPickerList(const ALocation: string;
  out AEntries: TArosaFileInfoArray): Boolean;
begin
  SetLength(AEntries,0);
  Result:=(FLocations<>nil) and FLocations.Enumerate(ALocation,AEntries);
end;

function TAFileManagerController.LocationPickerParent(
  const ALocation: string): string;
begin
  if FLocations<>nil then Result:=FLocations.Parent(ALocation)
  else Result:='';
end;

procedure TAFileManagerController.LocationPicked(ASender: TArosaControl;
  const ALocation: string);
var
  Purpose: string;
begin
  Purpose:=FLocationPickerPurpose;
  FLocationPickerPurpose:='';

  if SameText(Purpose,'move-to') then
  begin
    if (FMoveToItems<>nil) and (FMoveToItems.Count>0) and (ALocation<>'') then
      BeginResourceOperation('move-to',FMoveToItems,ALocation,atoMove,FMoveToView);
    FMoveToItems.Clear;
    Exit;
  end;

  if FArchiveDialog<>nil then
  begin
    FArchiveDialog.SetLocation(ALocation);
    if FArchiveDialog.Visible and (FArchiveDialog.RootView<>nil) then
      FArchiveDialog.RootView.ModalOwner:=FArchiveDialog;
  end;
end;

procedure TAFileManagerController.LocationPickerCancelled(
  ASender: TArosaControl);
begin
  if SameText(FLocationPickerPurpose,'move-to') then
    FMoveToItems.Clear;
  FLocationPickerPurpose:='';
  if (FArchiveDialog<>nil) and FArchiveDialog.Visible and
     (FArchiveDialog.RootView<>nil) then
    FArchiveDialog.RootView.ModalOwner:=FArchiveDialog;
end;

procedure TAFileManagerController.LoadNetworkLocations;
var Text: string; I: Integer; K,V: string;
begin
  if FNetworkLocations=nil then Exit;
  FNetworkLocations.Clear;
  if StateRead('network-locations',FNetworkLocationsPath,True,Text) then
  begin
    FNetworkLocations.Text:=Text;
    I:=FNetworkLocations.Count-1;
    while I>=0 do
    begin
      K:=Trim(FNetworkLocations.Names[I]); V:=Trim(FNetworkLocations.ValueFromIndex[I]);
      if (K='') or (V='') or (Pos('|',K)<=1) then FNetworkLocations.Delete(I);
      Dec(I);
    end;
  end;
end;

procedure TAFileManagerController.SaveNetworkLocations;
begin
  if (FNetworkLocations=nil) or (FFiles=nil) then Exit;
  if not StateWrite('network-locations',FNetworkLocationsPath,True,FNetworkLocations.Text) then
    Diagnostic('NETWORK-LOCATIONS save failed path='+FNetworkLocationsPath);
end;

function TAFileManagerController.NetworkLocationIndex(const ALocation: string): Integer;
var I: Integer;
begin
  Result:=-1;
  if FNetworkLocations=nil then Exit;
  for I:=0 to FNetworkLocations.Count-1 do
    if SameText(Trim(FNetworkLocations.ValueFromIndex[I]),Trim(ALocation)) then Exit(I);
end;

procedure TAFileManagerController.ShowPlaceProperties(const ALocation: string);
var
  M: TArosaResourceMetadata;
  I: Integer;
  Key, LabelText, ValueText, ResourceId: string;
  P: TArosaLocationProvider;
begin
  if (FPlacesMetadata=nil) or (Trim(ALocation)='') then Exit;
  M:=TArosaResourceMetadata.Create;
  if NetworkLocationIndex(ALocation)>=0 then
  begin
    I:=NetworkLocationIndex(ALocation);
    Key:=Trim(FNetworkLocations.Names[I]);
    ResourceId:=Key;
    LabelText:=Key;
    if Pos('|',Key)>0 then
    begin
      ResourceId:=Copy(Key,1,Pos('|',Key)-1);
      LabelText:=Copy(Key,Pos('|',Key)+1,MaxInt);
    end;
    M.AddAttribute('resource.name','arosa_metadata_name','general',LabelText,10);
    M.AddAttribute('resource.identity','Resource identity','general',ResourceId,20);
    M.AddAttribute('resource.location','arosa_metadata_location','general',ALocation,30);
    P:=nil; if FLocations<>nil then P:=FLocations.ProviderByScheme(Copy(ALocation,1,Pos('://',ALocation)-1));
    if P<>nil then
    begin
      M.AddAttribute('location.provider','Provider','location',P.DisplayName,40);
      M.AddAttribute('location.scheme','Protocol','location',P.Scheme,50);
      ValueText:=P.LastError;
      if ValueText='' then ValueText:='Not probed';
      M.AddAttribute('location.status','Status','location',ValueText,60);
    end;
  end
  else
  begin
    M.AddAttribute('resource.name','arosa_metadata_name','general',ExtractFileName(ALocation),10);
    M.AddAttribute('resource.location','arosa_metadata_location','general',ALocation,20);
  end;
  FPlacesMetadata.SetMetadata(M);
  if FPlacesDetailTabs<>nil then FPlacesDetailTabs.ActiveIndex:=0;
  if FPlacesDetailSplit<>nil then FPlacesDetailSplit.Visible:=True;
end;

procedure TAFileManagerController.EditSelectedPlace(ASender: TArosaControl);
var
  N: TArosaTreeNode;
  P, S, Scheme, Host, PortText, Remote, LabelText, Key: string;
  Port, SlashPos, ColonPos, SchemePos, I, Count: Integer;
  Schemes: array of string;
  Provider: TArosaLocationProvider;
begin
  if (FAssignments=nil) or (FNetworkDialog=nil) or (FLocations=nil) then Exit;
  N:=FAssignments.SelectedNode;
  if N=nil then Exit;
  P:=Trim(N.Hint);
  I:=NetworkLocationIndex(P);
  if I<0 then Exit;

  Key:=Trim(FNetworkLocations.Names[I]);
  LabelText:=Key;
  if Pos('|',Key)>0 then
    LabelText:=Copy(Key,Pos('|',Key)+1,MaxInt);

  { Parse the saved logical location generically.  Do not hard-code
    ATransfer here: the Location Service owns protocol registration. }
  S:=P;
  SchemePos:=Pos('://',S);
  if SchemePos<=1 then
  begin
    SetStatus('Cannot edit network location: invalid location syntax');
    Exit;
  end;
  Scheme:=LowerCase(Copy(S,1,SchemePos-1));
  Delete(S,1,SchemePos+2);
  SlashPos:=Pos('/',S);
  if SlashPos>0 then
  begin
    Host:=Copy(S,1,SlashPos-1);
    Remote:=Copy(S,SlashPos,MaxInt);
  end
  else
  begin
    Host:=S;
    Remote:='/';
  end;

  Provider:=FLocations.ProviderByScheme(Scheme);
  if Provider<>nil then Port:=Provider.DefaultPort else Port:=0;
  ColonPos:=Pos(':',Host);
  if ColonPos>1 then
  begin
    PortText:=Copy(Host,ColonPos+1,MaxInt);
    Host:=Copy(Host,1,ColonPos-1);
    Port:=StrToIntDef(PortText,Port);
  end;
  if Port<=0 then Port:=8080;

  Count:=0;
  SetLength(Schemes,FLocations.ProviderCount+1);
  for I:=0 to FLocations.ProviderCount-1 do
  begin
    Provider:=FLocations.RegisteredProvider(I);
    if (Provider=nil) or (Trim(Provider.Scheme)='') or SameText(Provider.Scheme,'file') then
      Continue;
    if not Provider.Enabled and not SameText(Provider.Scheme,Scheme) then Continue;
    Schemes[Count]:=Provider.Scheme;
    Inc(Count);
  end;
  { Keep an already-saved scheme editable even when its provider is currently
    unavailable/disabled. }
  if Count=0 then
  begin
    Schemes[0]:=Scheme;
    Count:=1;
  end;
  SetLength(Schemes,Count);

  FEditingNetworkLocation:=P;
  FNetworkDialog.ShowEditNetworkLocation('Edit network location',Schemes,
    Scheme,LabelText,Host,Port,Remote);
  if ASender=nil then ;
end;

procedure TAFileManagerController.ShowAddNetworkLocation;
var Schemes: array of string; Count,I: Integer; P: TArosaLocationProvider; DefaultScheme:string; DefaultPort:Integer;
begin
  if (FNetworkDialog=nil) or (FLocations=nil) then Exit;
  Count:=0; DefaultScheme:=''; DefaultPort:=0;
  for I:=0 to FLocations.ProviderCount-1 do
  begin
    P:=FLocations.RegisteredProvider(I);
    if (P=nil) or not P.Enabled or (Trim(P.Scheme)='') or SameText(P.Scheme,'file') then Continue;
    SetLength(Schemes,Count+1); Schemes[Count]:=P.Scheme;
    if DefaultScheme='' then begin DefaultScheme:=P.Scheme; DefaultPort:=P.DefaultPort; end;
    Inc(Count);
  end;
  if Count=0 then begin SetStatus('No network location providers are registered'); Exit; end;
  FNetworkDialog.ShowNetworkLocation('Add network location',Schemes,DefaultScheme,DefaultPort);
end;

procedure TAFileManagerController.NetworkLocationAdded(ASender: TArosaControl;
  const ALabel, AScheme, AServer: string; APort: Integer; const APath: string);
var Id,Location,PathPart:string; N,I:Integer; Used:Boolean;
begin
  if FNetworkLocations=nil then Exit;
  N:=1;
  repeat
    Id:='network.'+IntToStr(N); Used:=False;
    for I:=0 to FNetworkLocations.Count-1 do
      if Pos(Id+'|',FNetworkLocations.Names[I])=1 then begin Used:=True; Break; end;
    if Used then Inc(N);
  until not Used;
  PathPart:=Trim(APath); if PathPart='' then PathPart:='/'; if PathPart[1]<>'/' then PathPart:='/'+PathPart;
  Location:=LowerCase(Trim(AScheme))+'://'+Trim(AServer)+':'+IntToStr(APort)+PathPart;
  if FEditingNetworkLocation<>'' then
  begin
    I:=NetworkLocationIndex(FEditingNetworkLocation);
    if I>=0 then FNetworkLocations[I]:=Id+'|'+Trim(ALabel)+'='+Location
    else FNetworkLocations.Add(Id+'|'+Trim(ALabel)+'='+Location);
    FEditingNetworkLocation:='';
    SaveNetworkLocations; PopulateAssignments; SetStatus('Network location updated: '+Trim(ALabel));
  end
  else
  begin
    FNetworkLocations.Add(Id+'|'+Trim(ALabel)+'='+Location);
    SaveNetworkLocations; PopulateAssignments; SetStatus('Network location added: '+Trim(ALabel));
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.NetworkLocationCancelled(ASender: TArosaControl);
begin
  FEditingNetworkLocation:=''; SetStatus('Network location edit cancelled'); if ASender=nil then ;
end;

procedure TAFileManagerController.NetworkLocationTestServer(ASender: TArosaControl;
  const AScheme, AServer: string; APort: Integer; const APath: string;
  out ASuccess: Boolean; out AMessage: string);
var Location,PathPart:string;
begin
  ASuccess:=False; AMessage:='Location service unavailable';
  if FLocations=nil then Exit;
  PathPart:=Trim(APath); if PathPart='' then PathPart:='/';
  if PathPart[1]<>'/' then PathPart:='/'+PathPart;
  Location:=LowerCase(Trim(AScheme))+'://'+Trim(AServer)+':'+IntToStr(APort)+PathPart;
  ASuccess:=FLocations.TestServer(Location,AMessage);
  SetStatus('Network server test: '+AMessage);
  if ASender=nil then ;
end;

procedure TAFileManagerController.NetworkLocationTestAccess(ASender: TArosaControl;
  const AScheme, AServer: string; APort: Integer; const APath: string;
  out ASuccess: Boolean; out AMessage: string);
var Location,PathPart:string;
begin
  ASuccess:=False; AMessage:='Location service unavailable';
  if FLocations=nil then Exit;
  PathPart:=Trim(APath); if PathPart='' then PathPart:='/';
  if PathPart[1]<>'/' then PathPart:='/'+PathPart;
  Location:=LowerCase(Trim(AScheme))+'://'+Trim(AServer)+':'+IntToStr(APort)+PathPart;
  ASuccess:=FLocations.TestAccess(Location,AMessage);
  SetStatus('Network access test: '+AMessage);
  if ASender=nil then ;
end;

function TAFileManagerController.FavoriteKey(const APath: string): string;
begin
  { AROS paths are case-insensitive; ignore a trailing '/'. }
  Result:=Trim(APath);
  while (Length(Result)>1) and (Result[Length(Result)]='/') do Delete(Result,Length(Result),1);
  Result:=LowerCase(Result);
end;

function TAFileManagerController.FavoriteIndex(const APath: string): Integer;
var K: string;
begin
  Result:=-1;
  if (FFavorites=nil) or (Trim(APath)='') then Exit;
  K:=FavoriteKey(APath);
  for Result:=0 to FFavorites.Count-1 do
    if FavoriteKey(FFavorites.ValueFromIndex[Result])=K then Exit;
  Result:=-1;
end;

function TAFileManagerController.IsDesktopLocation(
  const ALocation: string): Boolean;
begin
  Result:=SameText(Trim(ALocation),'arosa://desktop');
end;

procedure TAFileManagerController.LoadDesktopShortcuts;
begin
  if FShortcutService<>nil then FShortcutService.Load;
end;

procedure TAFileManagerController.SaveDesktopShortcuts;
begin
  if (FShortcutService<>nil) and not FShortcutService.Save then
    Diagnostic('DESKTOP shortcuts save failed path='+FShortcutService.StoragePath+
      ' reason='+FShortcutService.LastError);
end;

function TAFileManagerController.DesktopShortcutIndex(
  const ATarget: string): Integer;
begin
  if FShortcutService=nil then Result:=-1
  else Result:=FShortcutService.IndexOfTarget(ATarget);
end;

function TAFileManagerController.AddDesktopShortcut(
  const ATarget: string): Boolean;
begin
  Result:=(FShortcutService<>nil) and
    FShortcutService.AddShortcut(ATarget,ShortcutDisplayName(ATarget));
  if Result then
  begin
  RebuildVirtualLocations;
    PublishLocationChanged('arosa://desktop',almkMetadata);
  end;
end;

function TAFileManagerController.RemoveDesktopShortcut(
  const ATarget: string): Boolean;
begin
  Result:=(FShortcutService<>nil) and FShortcutService.RemoveShortcut(ATarget);
  if Result then
  begin
    RebuildVirtualLocations;
    PublishLocationChanged('arosa://desktop',almkMetadata);
  end;
end;

function TAFileManagerController.ShortcutDisplayName(
  const ATarget: string): string;
var M: TArosaWorkspaceModuleArray; I: Integer;
begin
  { an application is shown under the name the workspace gives it, not under
    the name of its program file }
  Result:='';
  if FWorkspaceModules=nil then Exit;
  M:=FWorkspaceModules.Catalogue;
  for I:=0 to High(M) do
    if SameText(Trim(M[I].Target),Trim(ATarget)) then Exit(Trim(M[I].Name));
end;

function TAFileManagerController.StartMenuContains(
  const ATarget: string): Boolean;
begin
  Result:=(FStartMenuService<>nil) and (Trim(ATarget)<>'') and
    FStartMenuService.ContainsTarget(ATarget);
end;

function TAFileManagerController.AddStartMenuEntry(
  const ATarget: string): Boolean;
begin
  Result:=False;
  if (FStartMenuService=nil) or (Trim(ATarget)='') then Exit;
  { the workspace screen keeps its own view of the same catalogue }
  FStartMenuService.Load;
  if FStartMenuService.ContainsTarget(ATarget) then Exit(True);
  Result:=FStartMenuService.AddShortcut(ATarget,ShortcutDisplayName(ATarget));
end;

function TAFileManagerController.RemoveStartMenuEntry(
  const ATarget: string): Boolean;
begin
  Result:=False;
  if (FStartMenuService=nil) or (Trim(ATarget)='') then Exit;
  FStartMenuService.Load;
  Result:=FStartMenuService.RemoveShortcut(ATarget);
end;

function TAFileManagerController.StartedFromWorkspace: Boolean;
var I: Integer;
begin
  Result:=False;
  for I:=1 to ParamCount do
    if Pos('--workspace=',LowerCase(Trim(ParamStr(I))))=1 then Exit(True);
end;

function TAFileManagerController.OpenTaskbar(AScreen: TArosaPlatformHandle;
  const AWorkspaceName: string): Boolean;
var R: TArosaRect; Bottom: Integer;
begin
  Result:=False;
  FTaskbarTried:=True;
  if (FNativeHost=nil) or (FNativeHost.Application=nil) or
     (FPlatform=nil) then Exit;
  if FTaskbar=nil then
    FTaskbar:=TAFileManagerTaskbar.CreateTaskbar(FPlatform,
      FNativeHost.Application,FFonts,Self,AScreen,FActiveWorkspaceId,
      AWorkspaceName);
  Result:=FTaskbar.Open;
  if not Result then Exit;
  { the window of the file manager ends above the bar of its workspace }
  if (FPlatform.Windows<>nil) and (not FNativeHost.Closed) and
     (FNativeHost.Window<>ArosaNilHandle) then
  begin
    R:=FPlatform.Windows.GetWindowBounds(FNativeHost.Window);
    Bottom:=ArosaCoordWhole(R.Bottom);
    if (Bottom>FTaskbar.Top) and
       (FTaskbar.Top-ArosaCoordWhole(R.Top)>=320) then
      FNativeHost.SetWindowBounds(ArosaRectXYWH(ArosaCoordWhole(R.Left),
        ArosaCoordWhole(R.Top),ArosaCoordWhole(ArosaRectWidth(R)),
        FTaskbar.Top-ArosaCoordWhole(R.Top)));
  end;
end;

procedure TAFileManagerController.CloseTaskbar;
begin
  FreeAndNil(FTaskbar);
end;

function TAFileManagerController.PollVolumes(AForce: Boolean): Boolean;
var
  Lister: IArosaVolumeListPlatform;
  Raw, Name, Arrived, Left: string;
  Now: TStringList;
  I: Integer;
begin
  Result:=False;
  if (FVolumes=nil) or (FPlatform=nil) then Exit;
  if (not AForce) and (FVolumePollTick<>0) and
     (GetTickCount64-FVolumePollTick<2000) then Exit;
  FVolumePollTick:=GetTickCount64;
  if not Supports(FPlatform.FileSystem,IArosaVolumeListPlatform,Lister) then Exit;
  if not Lister.MountedVolumes(Raw) then Exit;

  Now:=TStringList.Create;
  try
    Now.Text:=Raw;
    for I:=Now.Count-1 downto 0 do
    begin
      Name:=Trim(Now[I]);
      if (Name<>'') and (Name[Length(Name)]<>':') then Name:=Name+':';
      if (Name='') or (Name=':') or (Now.IndexOf(Name)>=0) and
         (Now.IndexOf(Name)<>I) then Now.Delete(I)
      else Now[I]:=Name;
    end;
    Now.Sort;
    if FVolumesKnown and (Now.Text=FVolumes.Text) then Exit;

    Arrived:=''; Left:='';
    if FVolumesKnown then
    begin
      for I:=0 to Now.Count-1 do
        if FVolumes.IndexOf(Now[I])<0 then
        begin
          Arrived:=Arrived+' '+Now[I];
          if FVolumeNotices.IndexOf(Now[I])<0 then FVolumeNotices.Add(Now[I]);
        end;
      for I:=0 to FVolumes.Count-1 do
        if Now.IndexOf(FVolumes[I])<0 then
        begin
          Left:=Left+' '+FVolumes[I];
          { what is gone is no longer announced }
          if FVolumeNotices.IndexOf(FVolumes[I])>=0 then
            FVolumeNotices.Delete(FVolumeNotices.IndexOf(FVolumes[I]));
        end;
    end;
    FVolumes.Assign(Now);
    Result:=FVolumesKnown;
    FVolumesKnown:=True;
  finally
    Now.Free;
  end;

  { the first answer is what was there at the start: nothing arrived }
  RebuildVirtualLocations;
  if not Result then Exit;
  PublishLocationChanged('arosa://devices',almkMetadata);
  if Arrived<>'' then
  begin
    Diagnostic('VOLUME inserted'+Arrived);
    SetStatus(LocalText('afilemanager_volume_inserted','Volume inserted')+':'+Arrived);
  end;
  if Left<>'' then
  begin
    Diagnostic('VOLUME removed'+Left);
    if Arrived='' then
      SetStatus(LocalText('afilemanager_volume_removed','Volume removed')+':'+Left);
  end;
end;

procedure TAFileManagerController.AcknowledgeVolume(const AName: string);
var I: Integer;
begin
  if FVolumeNotices=nil then Exit;
  I:=FVolumeNotices.IndexOf(Trim(AName));
  if I>=0 then FVolumeNotices.Delete(I);
end;

procedure TAFileManagerController.OpenVolume(const AName: string);
begin
  if Trim(AName)='' then Exit;
  AcknowledgeVolume(AName);
  { it may have been taken away again since it was announced }
  if (FVolumes<>nil) and (FVolumes.IndexOf(Trim(AName))<0) then
  begin
    SetStatus(LocalText('afilemanager_volume_removed','Volume removed')+': '+Trim(AName));
    Exit;
  end;
  FPendingNavigateView:=FActiveView;
  FPendingNavigatePath:=Trim(AName);
  FPendingNavigateActive:=True;
  if (FNativeHost<>nil) and (not FNativeHost.Closed) then FNativeHost.Activate;
end;

function TAFileManagerController.WorkspaceLaunchArguments: string;
var Id: string;
begin
  Id:=Trim(FActiveWorkspaceId);
  if Id='' then Id:='default';
  { the theme is the one on screen: FTheme is the live presentation of this
    workspace, whatever its stored name says }
  Result:='--workspace='+Id+#10+'--theme='+ArosaThemeIdOf(FTheme);
  { 0.8.6.6: and the screen of the workspace, by its public name }
  if FWorkspaceScreenName<>'' then
    Result:=Result+#10+'--screen='+FWorkspaceScreenName;
end;

procedure TAFileManagerController.RebuildVirtualLocations;
const
  AssignNames: array[0..12] of string = ('AROS:', 'C:', 'DEVS:', 'ENV:',
    'ENVARC:', 'FONTS:', 'L:', 'LIBS:', 'PROGDIR:', 'RAM:', 'S:', 'SYS:', 'T:');
var
  I: Integer;
  Kind: TArosaFileEntryKind;
  Caption, Target, ModuleListing: string;
  WorkspaceModules: TArosaWorkspaceModuleArray;

  procedure AddDynamic(const AParent, ACaption, ATarget: string);
  var
    ParentLower, TargetLower: string;
  begin
    { Rebuilding a virtual catalogue must never probe its shortcut target.
      GetInfo on a remote target invokes the remote provider synchronously;
      rebuilding Desktop/Recent/Favorites could therefore launch hundreds of
      ATransfer STAT processes on the UI thread.  Classify from the catalogue
      semantics only.  The target is resolved normally when the user opens it. }
    ParentLower:=LowerCase(AParent);
    TargetLower:=LowerCase(ATarget);

    if (Pos('/recent-files',ParentLower)>0) or
       (Pos('/recent-edits',ParentLower)>0) then
      Kind:=afekFile
    else if (Pos('/recent-locations',ParentLower)>0) or
            (Pos('/trash',ParentLower)>0) or
            (Pos('arosa://',TargetLower)=1) or
            ((Length(ATarget)>0) and (ATarget[Length(ATarget)]=':')) then
      Kind:=afekDirectory
    else
      { Favorites and custom shortcuts can point at either kind.  Unknown is
        intentional here: do not perform I/O merely to paint the catalogue. }
      Kind:=afekUnknown;

    FVirtualLocations.AddShortcut(AParent,ACaption,ATarget,Kind,True);
  end;

  procedure PopulateWorkspace(AWorkspace: TArosaWorkspaceDefinition);
  var J: Integer; Item: TArosaWorkspaceItem;
  begin
    if AWorkspace=nil then Exit;
    for J:=0 to AWorkspace.ItemCount-1 do
    begin
      Item:=AWorkspace.Item(J);
      { Workspace members such as Documents, Favorites, Recent Files and
        Trash are navigation entities.  Their target may be a physical folder
        or a virtual catalogue, but the visible workspace item itself is a
        directory-like entity.  Declaring that here avoids the old 0-byte
        FILE rendering without re-introducing provider STAT calls. }
      FVirtualLocations.AddShortcut(
        'arosa://workspace/'+AWorkspace.Id,
        Item.Caption,Item.Target,afekDirectory,True);
    end;

    if FWorkspaceModules<>nil then
    begin
      WorkspaceModules:=FWorkspaceModules.EnabledModules(AWorkspace.Id);
      for J:=0 to High(WorkspaceModules) do
        if WorkspaceModules[J].Available and
           (Trim(WorkspaceModules[J].Target)<>'') then
        begin
          FVirtualLocations.AddShortcut(
            'arosa://workspace/'+AWorkspace.Id,
            WorkspaceModules[J].Name,WorkspaceModules[J].Target,afekFile,True);
          ModuleListing:=ModuleListing+' '+AWorkspace.Id+'/'+WorkspaceModules[J].Id;
        end;
    end;
  end;

  procedure PopulateSharedMachineResources(AWorkspace: TArosaWorkspaceDefinition);
  var Base: string;
  begin
    if AWorkspace=nil then Exit;
    Base:='arosa://workspace/'+AWorkspace.Id;
    FVirtualLocations.AddShortcut(Base,
      LocalText('afilemanager_assigns','Assigns'),
      'arosa://assigns',afekDirectory,True);
    FVirtualLocations.AddShortcut(Base,
      LocalText('afilemanager_devices','Devices'),
      'arosa://devices',afekDirectory,True);
    FVirtualLocations.AddShortcut(Base,
      LocalText('afilemanager_network','Network'),
      'arosa://network',afekDirectory,True);
  end;

  procedure PopulateStateFile(const AParent, APath, APrefix: string);
  var L: TStringList; J: Integer; Raw, CaptionValue, TargetValue: string;
  begin
    if (FFiles=nil) or (not FFiles.ReadAllText(APath,Raw)) then Exit;
    L:=TStringList.Create;
    try
      L.Text:=Raw;
      for J:=0 to L.Count-1 do
      begin
        Raw:=Trim(L[J]);
        if Raw='' then Continue;
        if APrefix<>'' then
        begin
          if Copy(Raw,1,Length(APrefix))<>APrefix then Continue;
          TargetValue:=Copy(Raw,Length(APrefix)+1,MaxInt);
          CaptionValue:=TargetValue;
        end
        else if Pos('=',Raw)>0 then
        begin
          CaptionValue:=Trim(Copy(Raw,1,Pos('=',Raw)-1));
          TargetValue:=Trim(Copy(Raw,Pos('=',Raw)+1,MaxInt));
        end
        else begin CaptionValue:=Raw; TargetValue:=Raw; end;
        if TargetValue<>'' then AddDynamic(AParent,CaptionValue,TargetValue);
      end;
    finally L.Free; end;
  end;

  procedure PopulateWorkspaceContext(AWorkspace: TArosaWorkspaceDefinition);
  var
    Base: string;
    J: Integer;
    IndexedTrash: TArosaTrashEntryArray;
  begin
    if AWorkspace=nil then Exit;
    Base:='arosa://workspace/'+AWorkspace.Id+'/';
    if SameText(AWorkspace.Id,FActiveWorkspaceId) then
    begin
      if FFavorites<>nil then
        for J:=0 to FFavorites.Count-1 do
          AddDynamic(Base+'favorites',FFavorites.Names[J],FFavorites.ValueFromIndex[J]);
      if FRecentLocations<>nil then
        for J:=0 to FRecentLocations.Count-1 do
          AddDynamic(Base+'recent-locations',FRecentLocations[J],FRecentLocations[J]);
      if FRecentFiles<>nil then
        for J:=0 to FRecentFiles.Count-1 do
          AddDynamic(Base+'recent-files',FRecentFiles[J],FRecentFiles[J]);
    end
    else
    begin
      PopulateStateFile(Base+'favorites',
        WorkspaceStatePath(AWorkspace.Id,'favorites'),'');
      PopulateStateFile(Base+'recent-locations',
        WorkspaceStatePath(AWorkspace.Id,'history'),'L=');
      PopulateStateFile(Base+'recent-files',
        WorkspaceStatePath(AWorkspace.Id,'history'),'F=');
    end;
    PopulateStateFile(Base+'recent-edits',
      WorkspaceStatePath(AWorkspace.Id,'edits'),'E=');

    if (FShellService<>nil) and (FShellService.Trash<>nil) and
       FShellService.Trash.ListEntriesForScope(AWorkspace.Id,IndexedTrash) then
      for J:=0 to High(IndexedTrash) do
        FVirtualLocations.AddShortcut(
          Base+'trash',
          IndexedTrash[J].DisplayName,
          IndexedTrash[J].TrashPath,
          IndexedTrash[J].Kind,True);
  end;

begin
  if FVirtualLocations=nil then Exit;
  ModuleListing:='';

  FVirtualLocations.DefineDirectory('arosa://desktop',
    LocalText('afilemanager_desktop','Desktop'));
  FVirtualLocations.DefineDirectory('arosa://favorites',
    LocalText('afilemanager_favorites','Favorites'));
  FVirtualLocations.DefineDirectory('arosa://recent-locations',
    LocalText('afilemanager_recent_locations','Recent Locations'));
  FVirtualLocations.DefineDirectory('arosa://recent-files',
    LocalText('afilemanager_recent_files','Recent Files'));
  FVirtualLocations.DefineDirectory('arosa://assigns',
    LocalText('afilemanager_assigns','Assigns'));
  FVirtualLocations.DefineDirectory('arosa://network',
    LocalText('afilemanager_network','Network'));
  FVirtualLocations.DefineDirectory('arosa://devices',
    LocalText('afilemanager_devices','Devices'));
  FVirtualLocations.DefineDirectory('arosa://workspaces',
    LocalText('afilemanager_workspaces','AROSA Workspaces'));
  if FWorkspaces<>nil then
    for I:=0 to FWorkspaces.Count-1 do
      if FWorkspaces.Workspace(I)<>nil then
        begin
          FVirtualLocations.DefineDirectory(
            'arosa://workspace/'+FWorkspaces.Workspace(I).Id,
            FWorkspaces.Workspace(I).Name);
          FVirtualLocations.DefineDirectory('arosa://workspace/'+
            FWorkspaces.Workspace(I).Id+'/favorites',
            LocalText('afilemanager_favorites','Favorites'));
          FVirtualLocations.DefineDirectory('arosa://workspace/'+
            FWorkspaces.Workspace(I).Id+'/recent-files',
            LocalText('afilemanager_recent_files','Recent Files'));
          FVirtualLocations.DefineDirectory('arosa://workspace/'+
            FWorkspaces.Workspace(I).Id+'/recent-edits',
            LocalText('afilemanager_recent_edits','Recent Edits'));
          FVirtualLocations.DefineDirectory('arosa://workspace/'+
            FWorkspaces.Workspace(I).Id+'/recent-locations',
            LocalText('afilemanager_recent_locations','Recent Locations'));
          FVirtualLocations.DefineDirectory('arosa://workspace/'+
            FWorkspaces.Workspace(I).Id+'/trash',
            LocalText('afilemanager_trash','Trash'));
        end;

  FVirtualLocations.ClearDirectory('arosa://desktop');
  FVirtualLocations.ClearDirectory('arosa://favorites');
  FVirtualLocations.ClearDirectory('arosa://recent-locations');
  FVirtualLocations.ClearDirectory('arosa://recent-files');
  FVirtualLocations.ClearDirectory('arosa://assigns');
  FVirtualLocations.ClearDirectory('arosa://network');
  FVirtualLocations.ClearDirectory('arosa://devices');
  FVirtualLocations.ClearDirectory('arosa://workspaces');
  if FWorkspaces<>nil then
    for I:=0 to FWorkspaces.Count-1 do
      if FWorkspaces.Workspace(I)<>nil then
        begin
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id);
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/favorites');
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-files');
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-edits');
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-locations');
          FVirtualLocations.ClearDirectory('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/trash');
        end;

  if FWorkspaces<>nil then
    for I:=0 to FWorkspaces.Count-1 do
      if (FWorkspaces.Workspace(I)<>nil) and
         (not SameText(FWorkspaces.Workspace(I).Id,FActiveWorkspaceId)) then
        FVirtualLocations.AddShortcut('arosa://workspaces',
          FWorkspaces.Workspace(I).Name,
          'arosa://workspace/'+FWorkspaces.Workspace(I).Id,afekDirectory);

  FVirtualLocations.AddShortcut('arosa://desktop',
    LocalText('afilemanager_assigns','Assigns'),'arosa://assigns',afekDirectory);
  FVirtualLocations.AddShortcut('arosa://desktop',
    LocalText('afilemanager_network','Network'),'arosa://network',afekDirectory);
  FVirtualLocations.AddShortcut('arosa://desktop',
    LocalText('afilemanager_devices','Devices'),'arosa://devices',afekDirectory);

  if FWorkspaces<>nil then
    for I:=0 to FWorkspaces.Count-1 do
    begin
      PopulateWorkspace(FWorkspaces.Workspace(I));
      PopulateSharedMachineResources(FWorkspaces.Workspace(I));
      PopulateWorkspaceContext(FWorkspaces.Workspace(I));
    end;

  if (FWorkspaces<>nil) and (FWorkspaces.Find(FActiveWorkspaceId)<>nil) then
    for I:=0 to FWorkspaces.Find(FActiveWorkspaceId).ItemCount-1 do
    begin
      Caption:=FWorkspaces.Find(FActiveWorkspaceId).Item(I).Caption;
      Target:=FWorkspaces.Find(FActiveWorkspaceId).Item(I).Target;
      AddDynamic('arosa://desktop',Caption,Target);
    end;

  if FShortcutService<>nil then
  begin
    { Shortcuts may be created by another AROSA application process. Reload
      the shared catalogue whenever virtual locations are rebuilt so Refresh
      immediately observes those external changes. }
    FShortcutService.Load;
    for I:=0 to FShortcutService.Count-1 do
      AddDynamic('arosa://desktop',FShortcutService.NameAt(I),
        FShortcutService.TargetAt(I));
  end;

  if FFavorites<>nil then
    for I:=0 to FFavorites.Count-1 do
      AddDynamic('arosa://favorites',FFavorites.Names[I],FFavorites.ValueFromIndex[I]);

  if FRecentLocations<>nil then
    for I:=0 to FRecentLocations.Count-1 do
      AddDynamic('arosa://recent-locations',FRecentLocations[I],FRecentLocations[I]);

  if FRecentFiles<>nil then
    for I:=0 to FRecentFiles.Count-1 do
      AddDynamic('arosa://recent-files',FRecentFiles[I],FRecentFiles[I]);

  for I:=Low(AssignNames) to High(AssignNames) do
    FVirtualLocations.AddShortcut('arosa://assigns',AssignNames[I],
      AssignNames[I],afekDirectory);

  if FNetworkLocations<>nil then
    for I:=0 to FNetworkLocations.Count-1 do
    begin
      Caption:=Trim(FNetworkLocations.Names[I]);
      Target:=Trim(FNetworkLocations.ValueFromIndex[I]);
      if Pos('|',Caption)>0 then Caption:=Copy(Caption,Pos('|',Caption)+1,MaxInt);
      if (Caption<>'') and (Target<>'') then
        FVirtualLocations.AddShortcut('arosa://network',Caption,Target,afekDirectory);
    end;

  { 0.8.6.6: in the log, once per change: the modules each workspace lists }
  if ModuleListing<>FLastModuleListing then
  begin
    FLastModuleListing:=ModuleListing;
    Diagnostic('WORKSPACE modules listed:'+ModuleListing);
  end;

  { 0.8.6.5: the volumes the system has mounted now; the two that are always
    there when the platform cannot say }
  if FVolumesKnown and (FVolumes<>nil) and (FVolumes.Count>0) then
  begin
    for I:=0 to FVolumes.Count-1 do
      FVirtualLocations.AddShortcut('arosa://devices',FVolumes[I],FVolumes[I],
        afekDirectory);
  end
  else
  begin
    FVirtualLocations.AddShortcut('arosa://devices','RAM:','RAM:',afekDirectory);
    FVirtualLocations.AddShortcut('arosa://devices','SYS:','SYS:',afekDirectory);
  end;

  if FLocations<>nil then
  begin
    FLocations.Invalidate('arosa://desktop',False);
    FLocations.Invalidate('arosa://favorites',False);
    FLocations.Invalidate('arosa://recent-locations',False);
    FLocations.Invalidate('arosa://recent-files',False);
    FLocations.Invalidate('arosa://assigns',False);
    FLocations.Invalidate('arosa://network',False);
    FLocations.Invalidate('arosa://devices',False);
    FLocations.Invalidate('arosa://workspaces',False);
    if FWorkspaces<>nil then
      for I:=0 to FWorkspaces.Count-1 do
        if FWorkspaces.Workspace(I)<>nil then
        begin
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id,False);
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/favorites',False);
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-files',False);
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-edits',False);
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/recent-locations',False);
          FLocations.Invalidate('arosa://workspace/'+FWorkspaces.Workspace(I).Id+'/trash',False);
        end;
  end;
end;

function TAFileManagerController.WorkspaceUserConfigurationPath(
  const AWorkspaceId: string): string;
begin
  if SameText(Trim(AWorkspaceId),'default') then
    Result:='configurations/default.user'
  else
    Result:='configurations/AFileManager.workspace.'+
      Trim(AWorkspaceId)+'.user';
end;

function TAFileManagerController.WorkspaceStatePath(
  const AWorkspaceId, AKind: string): string;
begin
  Result:=FDescriptorBase+'AFileManager.workspace.'+
    Trim(AWorkspaceId)+'.'+Trim(AKind);
end;

function TAFileManagerController.WorkspaceTrashDirectory(
  const AWorkspaceId: string): string;
begin
  if SameText(Trim(AWorkspaceId),'default') then
    Exit(FTrashDirectory);
  if FPaths<>nil then Result:=FPaths.Join(FTrashDirectory,Trim(AWorkspaceId))
  else Result:=FTrashDirectory+'/'+Trim(AWorkspaceId);
end;

function TAFileManagerController.IsWorkspaceTrashLocation(
  const ALocation: string): Boolean;
var L: string;
begin
  L:=LowerCase(Trim(ALocation));
  Result:=(Pos('arosa://workspace/',L)=1) and
    (Length(L)>=6) and (Copy(L,Length(L)-5,6)='/trash');
end;

function TAFileManagerController.WorkspaceIdFromLocation(
  const ALocation: string): string;
const Prefix = 'arosa://workspace/';
begin
  Result:='';
  if Pos(Prefix,LowerCase(Trim(ALocation)))=1 then
    Result:=Copy(Trim(ALocation),Length(Prefix)+1,MaxInt);
end;

function TAFileManagerController.WorkspacePrototypeById(
  const AId: string): TAFileManagerWorkspacePrototype;
var I: Integer; P: TAFileManagerWorkspacePrototype;
begin
  Result:=nil;
  if FWorkspacePrototypes=nil then Exit;
  for I:=0 to FWorkspacePrototypes.Count-1 do
  begin
    P:=TAFileManagerWorkspacePrototype(FWorkspacePrototypes[I]);
    if (P<>nil) and SameText(P.WorkspaceId,AId) then Exit(P);
  end;
end;

procedure TAFileManagerController.Diagnostic(const AMessage: string);
var
  Tagged: string;
begin
  Tagged:='['+FInstanceId+']['+FActiveWorkspaceId+'] '+AMessage;

  { Diagnostics are platform messages.  AFileManager never opens, appends,
    flushes or owns a diagnostic file. }
  Arosa.Services.Diagnostics.Diagnostic(Tagged);
end;

procedure TAFileManagerController.FlushInstanceDiagnostics(AForce: Boolean);
begin
  { Compatibility hook retained for the existing idle/shutdown lifecycle.
    Pumping only hands records to the message broker; it never waits for or
    writes persistence. }
  Arosa.Services.Diagnostics.DiagnosticPump;
  if AForce then ;
end;

procedure TAFileManagerController.StartInstanceDiagnostics;
begin
  if FInstanceId<>'' then Exit;
  Inc(GAFMInstanceSerial);
  FInstanceId:='AFM-'+Format('%.4d',[GAFMInstanceSerial]);
  FInstanceLogPath:='';
  FInstanceLogStream:=nil;
  FInstanceLogPending:=nil;
  FInstanceLogLastFlush:=0;
  Diagnostic('INSTANCE-START transport=message');
end;

procedure TAFileManagerController.StopInstanceDiagnostics;
begin
  if FInstanceId<>'' then Diagnostic('INSTANCE-STOP');
  Arosa.Services.Diagnostics.DiagnosticPump;
  FreeAndNil(FInstanceLogStream);
  FreeAndNil(FInstanceLogPending);
  FInstanceLogPath:='';
  FInstanceId:='';
  FInstanceLogLastFlush:=0;
end;

function TAFileManagerController.HasOpenWorkspacePrototypes: Boolean;
var
  I: Integer;
  P: TAFileManagerWorkspacePrototype;
begin
  Result:=False;
  if FWorkspacePrototypes=nil then Exit;
  for I:=0 to FWorkspacePrototypes.Count-1 do
  begin
    P:=TAFileManagerWorkspacePrototype(FWorkspacePrototypes[I]);
    if (P<>nil) and P.IsOpen then Exit(True);
  end;
end;

procedure TAFileManagerController.WorkspacePrototypeClosed;
begin
  { The primary controller is retained as the process/session root after its
    own window closes. Once the final workspace window also closes, the event
    loop can terminate safely. }
  if FWorkspaceSessionMode then Exit;
  if HasOpenWorkspacePrototypes then Exit;
  if (FNativeHost<>nil) and FNativeHost.Closed and
     (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) then
    FNativeHost.Application.Loop.Terminate;
end;

procedure TAFileManagerController.UpdateWorkspacePendingWork;
var
  I, DirtyCount: Integer;
  Doc: TAFileManagerDocument;
  Details, WorkspaceName: string;
  W: TArosaWorkspaceDefinition;
begin
  DirtyCount:=0;
  Details:='';
  if FDocuments<>nil then
    for I:=0 to FDocuments.Count-1 do
    begin
      Doc:=TAFileManagerDocument(FDocuments[I]);
      if (Doc<>nil) and (Doc.Editor<>nil) and
         (Doc.Editor.Text<>Doc.OriginalText) then
      begin
        Inc(DirtyCount);
        if Details<>'' then Details:=Details+', ';
        Details:=Details+ExtractFileName(Doc.Path);
      end;
    end;

  WorkspaceName:=FActiveWorkspaceId;
  W:=nil;
  if FWorkspaces<>nil then W:=FWorkspaces.Find(FActiveWorkspaceId);
  if W<>nil then WorkspaceName:=W.Name;

  if DirtyCount>0 then
    ArosaWorkspaceStatus.Update(
      FActiveWorkspaceId,WorkspaceName,FWorkspaceStatusSource,
      IntToStr(DirtyCount)+' unsaved document(s)',Details,
      awpsAlarm,True)
  else
    ArosaWorkspaceStatus.Clear(FActiveWorkspaceId,FWorkspaceStatusSource);
end;

procedure TAFileManagerController.ShowCrossWorkspacePendingBubble;
var
  TitleText, HintText, DescText: string;
  Blocking: Boolean;
  Info: TArosaContextInfo;
  R, Anchor: TArosaRect;
begin
  if (FNativeHost=nil) or (FNativeHost.Bubbles=nil) or
     (FWindowFrame=nil) then Exit;
  if not ArosaWorkspaceStatus.OtherWorkspaceSummary(
       FActiveWorkspaceId,TitleText,HintText,DescText,Blocking) then Exit;

  Info:=Default(TArosaContextInfo);
  Info.Title:=TitleText;
  Info.Hint:=HintText;
  Info.Description:=DescText;
  R:=FWindowFrame.AbsoluteBounds;
  Anchor:=ArosaRectRaw(R.Right-ArosaCoord(36),R.Top+ArosaCoord(8),
    R.Right-ArosaCoord(8),R.Top+ArosaCoord(36));
  FNativeHost.Bubbles.ShowMessage(Info,Anchor,Blocking);
end;

procedure TAFileManagerController.NativeActivated;
begin
  UpdateWorkspacePendingWork;
  ShowCrossWorkspacePendingBubble;
end;

procedure TAFileManagerController.NativeDeactivated;
begin
  UpdateWorkspacePendingWork;
end;

procedure TAFileManagerController.ConfigureWorkspaceSession(
  const AWorkspaceId: string; ACloseRequest: TArosaHostCloseRequest;
  ANavigationOwner: TAFileManagerController);
begin
  FWorkspaceSessionMode:=True;
  FWorkspaceSessionClose:=ACloseRequest;
  FWorkspaceNavigationOwner:=ANavigationOwner;
  if Trim(AWorkspaceId)<>'' then FActiveWorkspaceId:=Trim(AWorkspaceId);
  if (FShellService<>nil) and (FShellService.Trash<>nil) then
    FShellService.Trash.ScopeId:=FActiveWorkspaceId;
  UpdateWorkspacePendingWork;
end;

procedure TAFileManagerController.OpenWorkspaceLocation(
  const AWorkspaceId: string);
var Location: string;
begin
  if Trim(AWorkspaceId)<>'' then FActiveWorkspaceId:=Trim(AWorkspaceId);
  if (FShellService<>nil) and (FShellService.Trash<>nil) then
    FShellService.Trash.ScopeId:=FActiveWorkspaceId;
  RebuildVirtualLocations;
  Location:='arosa://workspace/'+FActiveWorkspaceId;
  NavigateView(0,Location);
  SetActiveView(0);
end;

function TAFileManagerController.ActivateWorkspaceSelfResource(
  const APath: string): Boolean;
var
  Leaf: string;
begin
  Result:=False;
  if not FWorkspaceSessionMode then Exit;

  Leaf:=ExtractFileName(Trim(APath));
  if SameText(Leaf,'AFileManager') or SameText(Leaf,'AFileManager.exe') then
  begin
    { A workspace already owns exactly one AFileManager session. Opening the
      AFileManager executable from that workspace must focus the existing
      session, never launch a second process/window on the default screen. }
    if FNativeHost<>nil then FNativeHost.Activate;
    SetStatus(LocalText('afilemanager_workspace_session_active',
      'AFileManager is already open in this workspace'));
    Result:=True;
  end;
end;

procedure TAFileManagerController.WorkspaceCloseScreenClick(
  ASender: TArosaControl);
begin
  if FWorkspaceSessionMode then RequestApplicationClose;
  if ASender=nil then ;
end;

function TAFileManagerController.ActivateWorkspaceLocation(
  const ALocation: string): Boolean;
var
  IdValue: string;
  W: TArosaWorkspaceDefinition;
begin
  Result:=False;
  if FWorkspaces=nil then Exit;
  IdValue:=WorkspaceIdFromLocation(ALocation);
  if IdValue='' then Exit;
  { Only the workspace entity itself activates a screen. Child catalogues
    remain ordinary navigable locations. }
  if Pos('/',IdValue)>0 then Exit;
  W:=FWorkspaces.Find(IdValue);
  if W=nil then Exit;

  { A workspace session is not an independent workspace owner.  Route moves
    through the process-level owner so all AFileManager sessions share the
    same prototype table.  OpenWorkspacePrototype already raises an existing
    prototype when it is open; it creates a screen only when no session for
    that workspace exists. }
  if FWorkspaceSessionMode and (FWorkspaceNavigationOwner<>nil) then
  begin
    if SameText(IdValue,FActiveWorkspaceId) then
    begin
      if FNativeHost<>nil then FNativeHost.Activate;
      Result:=True;
      Exit;
    end;

    { The process-level navigation owner is itself the open session for its
      active workspace (normally the primary/default workspace).  It is not
      represented in FWorkspacePrototypes.  Treating it as absent created a
      second AFileManager session on the primary screen; on AROS that duplicate
      activation also allowed the literal exec: pseudo-target to leak toward
      AmigaDOS and raise an "Insert volume exec" requester. }
    if SameText(IdValue,FWorkspaceNavigationOwner.FActiveWorkspaceId) then
    begin
      if FWorkspaceNavigationOwner.FNativeHost<>nil then
        FWorkspaceNavigationOwner.FNativeHost.Activate;
      FWorkspaceNavigationOwner.SetStatus(
        FWorkspaceNavigationOwner.LocalText(
          'afilemanager_workspace_session_active',
          'AFileManager is already open in this workspace'));
      Result:=True;
      Exit;
    end;

    W:=FWorkspaceNavigationOwner.FWorkspaces.Find(IdValue);
    if W<>nil then
      FWorkspaceNavigationOwner.OpenWorkspacePrototype(W);
  end
  else
  begin
    { The primary controller is already the live session for its own
      workspace. Never construct a prototype for the same workspace. }
    if SameText(IdValue,FActiveWorkspaceId) then
    begin
      if FNativeHost<>nil then FNativeHost.Activate;
      Result:=True;
      Exit;
    end;
    OpenWorkspacePrototype(W);
  end;
  Result:=True;
end;

procedure TAFileManagerController.OpenWorkspacePrototype(
  AWorkspace: TArosaWorkspaceDefinition);
var
  P: TAFileManagerWorkspacePrototype;
  SessionTheme: TArosaTheme;
begin
  if AWorkspace=nil then Exit;
  if (FNativeHost=nil) or (FNativeHost.Application=nil) then Exit;
  if (FPlatform=nil) or (FPlatform.Screens=nil) then
  begin
    SetStatus(LocalText('afilemanager_workspace_screens_unavailable',
      'This platform does not provide multiple-screen workspace support.'));
    Exit;
  end;

  P:=WorkspacePrototypeById(AWorkspace.Id);
  if P=nil then
  begin
    SessionTheme:=FTheme;
    if SameText(AWorkspace.ThemeId,'Light') and (FLightTheme<>nil) then
      SessionTheme:=FLightTheme
    else if SameText(AWorkspace.ThemeId,'Dark') and (FDarkTheme<>nil) then
      SessionTheme:=FDarkTheme;
    P:=TAFileManagerWorkspacePrototype.CreateWorkspace(
      FPlatform,FNativeHost.Application,SessionTheme,FFonts,AWorkspace,Self);
    FWorkspacePrototypes.Add(P);
  end;

  if P.Open then
    SetStatus(SysUtils.Format(
      LocalText('afilemanager_workspace_opened',
        '%s opened on the %s Intuition screen'),
      [AWorkspace.Name,AWorkspace.PreferredScreen]))
  else
    SetStatus(SysUtils.Format(
      LocalText('afilemanager_workspace_open_failed',
        'Could not open the %s Intuition screen'),
      [AWorkspace.PreferredScreen]));
end;

procedure TAFileManagerController.CloseWorkspacePrototype(const AId: string);
var I: Integer; P: TAFileManagerWorkspacePrototype;
begin
  if FWorkspacePrototypes=nil then Exit;
  for I:=FWorkspacePrototypes.Count-1 downto 0 do
  begin
    P:=TAFileManagerWorkspacePrototype(FWorkspacePrototypes[I]);
    if (P<>nil) and SameText(P.WorkspaceId,AId) then
    begin
      FWorkspacePrototypes.Delete(I);
      P.Free;
    end;
  end;
end;

procedure TAFileManagerController.LoadWorkspacesFromUserProfile;
var
  Text, Line, Section, IdValue, Value, NameValue, ScreenValue: string;
  Lines, Fields: TStringList;
  I, P: Integer;
  W: TArosaWorkspaceDefinition;
  HasWorkspaceSection: Boolean;
begin
  if (FWorkspaces=nil) or (FFiles=nil) or (FDescriptor=nil) then Exit;

  FWorkspaceProfilePath:=Trim(FDescriptor.UserConfigurationPath);
  if FWorkspaceProfilePath='' then
    FWorkspaceProfilePath:='configurations/default.user';
  if (Pos(':',FWorkspaceProfilePath)=0) and
     ((FWorkspaceProfilePath='') or (FWorkspaceProfilePath[1]<>'/')) then
    FWorkspaceProfilePath:=FDescriptorBase+FWorkspaceProfilePath;

  if not FFiles.ReadAllText(FWorkspaceProfilePath,Text) then Exit;
  Lines:=TStringList.Create;
  try
    Lines.Text:=Text;
    HasWorkspaceSection:=False;
    Section:='';
    for I:=0 to Lines.Count-1 do
    begin
      Line:=Trim(Lines[I]);
      if (Length(Line)>=2) and (Line[1]='[') and
         (Line[Length(Line)]=']') then
      begin
        Section:=Trim(Copy(Line,2,Length(Line)-2));
        if SameText(Section,'Workspaces') then HasWorkspaceSection:=True;
      end;
    end;
    if not HasWorkspaceSection then Exit;

    FWorkspaces.Clear;
    Section:='';
    for I:=0 to Lines.Count-1 do
    begin
      Line:=Trim(Lines[I]);
      if (Line='') or (Line[1]=';') then Continue;
      if (Length(Line)>=2) and (Line[1]='[') and
         (Line[Length(Line)]=']') then
      begin
        Section:=Trim(Copy(Line,2,Length(Line)-2));
        Continue;
      end;
      if not SameText(Section,'Workspaces') then Continue;
      P:=Pos('=',Line);
      if P<=1 then Continue;
      IdValue:=Trim(Copy(Line,1,P-1));
      Value:=Trim(Copy(Line,P+1,MaxInt));
      Fields:=TStringList.Create;
      try
        Fields.StrictDelimiter:=True;
        Fields.Delimiter:='|';
        Fields.DelimitedText:=Value;
        if Fields.Count>0 then NameValue:=Trim(Fields[0]) else NameValue:='';
        if Fields.Count>1 then ScreenValue:=Trim(Fields[1]) else ScreenValue:=NameValue;
        W:=nil;
        if (IdValue<>'') and (NameValue<>'') then
          W:=FWorkspaces.AddWorkspace(IdValue,NameValue,ScreenValue);
        if W<>nil then
        begin
          if Fields.Count>2 then W.ThemeId:=Trim(Fields[2]);
          if Fields.Count>3 then W.ScreenWidth:=StrToIntDef(Trim(Fields[3]),0);
          if Fields.Count>4 then W.ScreenHeight:=StrToIntDef(Trim(Fields[4]),0);
          if Fields.Count>5 then W.ScreenDepth:=StrToIntDef(Trim(Fields[5]),0);
          if Fields.Count>6 then W.BackgroundImage:=Trim(Fields[6]);
          if Fields.Count>7 then
            W.ShareClipboard:=SameText(Trim(Fields[7]),'true') or
              (Trim(Fields[7])='1');
          if Fields.Count>8 then
            W.ShareDesk:=SameText(Trim(Fields[8]),'true') or (Trim(Fields[8])='1');
          if Fields.Count>9 then W.BackgroundMode:=Trim(Fields[9]);
          if Fields.Count>10 then W.BackgroundColour1:=TArosaColour(StrToInt64Def(Trim(Fields[10]),Int64(LongWord(W.BackgroundColour1))));
          if Fields.Count>11 then W.BackgroundColour2:=TArosaColour(StrToInt64Def(Trim(Fields[11]),Int64(LongWord(W.BackgroundColour2))));
          if Fields.Count>12 then W.BackgroundColour3:=TArosaColour(StrToInt64Def(Trim(Fields[12]),Int64(LongWord(W.BackgroundColour3))));
          if Fields.Count>13 then W.BackgroundColour4:=TArosaColour(StrToInt64Def(Trim(Fields[13]),Int64(LongWord(W.BackgroundColour4))));
          if Fields.Count>14 then W.BackgroundGradientDirection:=Trim(Fields[14]);
          if Fields.Count>15 then W.BackgroundLayerOrder:=Trim(Fields[15]);
          if Fields.Count>16 then W.BackgroundOpacity:=StrToIntDef(Trim(Fields[16]),100);
          if W.BackgroundOpacity<0 then W.BackgroundOpacity:=0 else if W.BackgroundOpacity>100 then W.BackgroundOpacity:=100;
        end;
      finally
        Fields.Free;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

function TAFileManagerController.SaveWorkspacesToUserProfile: Boolean;
var
  Text: string;
  Lines: TStringList;
  I, StartIndex, EndIndex: Integer;
  W: TArosaWorkspaceDefinition;
begin
  Result:=False;
  if (FWorkspaces=nil) or (FFiles=nil) then Exit;
  if FWorkspaceProfilePath='' then Exit;

  Lines:=TStringList.Create;
  try
    if FFiles.ReadAllText(FWorkspaceProfilePath,Text) then Lines.Text:=Text;

    StartIndex:=-1;
    EndIndex:=Lines.Count;
    for I:=0 to Lines.Count-1 do
      if SameText(Trim(Lines[I]),'[Workspaces]') then
      begin
        StartIndex:=I;
        Break;
      end;

    if StartIndex>=0 then
    begin
      EndIndex:=Lines.Count;
      for I:=StartIndex+1 to Lines.Count-1 do
        if (Length(Trim(Lines[I]))>=2) and (Trim(Lines[I])[1]='[') and
           (Trim(Lines[I])[Length(Trim(Lines[I]))]=']') then
        begin
          EndIndex:=I;
          Break;
        end;
      while EndIndex>StartIndex+1 do
      begin
        Lines.Delete(StartIndex+1);
        Dec(EndIndex);
      end;
    end
    else
    begin
      if (Lines.Count>0) and (Trim(Lines[Lines.Count-1])<>'') then Lines.Add('');
      StartIndex:=Lines.Add('[Workspaces]');
    end;

    for I:=0 to FWorkspaces.Count-1 do
    begin
      W:=FWorkspaces.Workspace(I);
      if W<>nil then
      begin
        Inc(StartIndex);
        Lines.Insert(StartIndex,W.Id+'='+W.Name+'|'+W.PreferredScreen+'|'+
          W.ThemeId+'|'+IntToStr(W.ScreenWidth)+'|'+
          IntToStr(W.ScreenHeight)+'|'+IntToStr(W.ScreenDepth)+'|'+
          W.BackgroundImage+'|'+
          BoolToStr(W.ShareClipboard,True)+'|'+BoolToStr(W.ShareDesk,True)+'|'+
          W.BackgroundMode+'|'+IntToStr(Int64(LongWord(W.BackgroundColour1)))+'|'+
          IntToStr(Int64(LongWord(W.BackgroundColour2)))+'|'+IntToStr(Int64(LongWord(W.BackgroundColour3)))+'|'+
          IntToStr(Int64(LongWord(W.BackgroundColour4)))+'|'+W.BackgroundGradientDirection+'|'+
          W.BackgroundLayerOrder+'|'+IntToStr(W.BackgroundOpacity));
      end;
    end;

    Result:=FFiles.SafeSaveText(FWorkspaceProfilePath,Lines.Text);
    if not Result then
      Diagnostic('WORKSPACE save failed path='+FWorkspaceProfilePath);
  finally
    Lines.Free;
  end;
end;

procedure TAFileManagerController.CreateWorkspaceClick(ASender: TArosaControl);
begin
  FPendingInputKind:='workspace';
  FPendingInputSource:='';
  FPendingInputView:=FActiveView;
  if FNameDialog<>nil then
    FNameDialog.ShowName(
      LocalText('afilemanager_workspace_create','Create workspace'),
      LocalText('afilemanager_workspace_name','Workspace name'),
      LocalText('afilemanager_workspace_new','New Workspace'))
  else
    SetStatus(LocalText('afilemanager_workspace_dialog_unavailable',
      'Workspace dialog unavailable'));
  if ASender=nil then ;
end;

procedure TAFileManagerController.RequestEditWorkspaceProperties(
  const AWorkspaceId: string);
var
  W: TArosaWorkspaceDefinition;
  S: TAFMWorkspaceProperties;
  Modes: TArosaScreenModeArray;
begin
  if FWorkspaces=nil then Exit;
  W:=FWorkspaces.Find(Trim(AWorkspaceId));
  if W=nil then Exit;

  FPendingEditWorkspaceId:=W.Id;
  FPendingInputView:=FActiveView;

  if FWorkspacePropertiesDialog<>nil then
  begin
    SetLength(Modes,0);
    if (FPlatform<>nil) and (FPlatform.Screens<>nil) then
      Modes:=FPlatform.Screens.EnumerateScreenModes;
    FWorkspacePropertiesDialog.SetScreenModes(Modes);
    S.Name:=W.Name;
    S.ThemeId:=W.ThemeId;
    S.ScreenWidth:=W.ScreenWidth;
    S.ScreenHeight:=W.ScreenHeight;
    S.ScreenDepth:=W.ScreenDepth;
    S.BackgroundImage:=W.BackgroundImage;
    S.BackgroundMode:=W.BackgroundMode;
    S.BackgroundColour1:=W.BackgroundColour1; S.BackgroundColour2:=W.BackgroundColour2;
    S.BackgroundColour3:=W.BackgroundColour3; S.BackgroundColour4:=W.BackgroundColour4;
    S.BackgroundGradientDirection:=W.BackgroundGradientDirection;
    S.BackgroundLayerOrder:=W.BackgroundLayerOrder; S.BackgroundOpacity:=W.BackgroundOpacity;
    S.ShareClipboard:=W.ShareClipboard;
    S.ShareDesk:=W.ShareDesk;
    FWorkspacePropertiesDialog.ShowSettings(S);
  end
  else
  begin
    FPendingEditWorkspaceId:='';
    SetStatus(LocalText('afilemanager_workspace_dialog_unavailable',
      'Workspace dialog unavailable'));
  end;
end;

function TAFileManagerController.StandardDialogList(
  const ADirectory: string; out AEntries: TArosaFileInfoArray): Boolean;
begin
  SetLength(AEntries,0);
  Result:=(FLocations<>nil) and FLocations.Enumerate(ADirectory,AEntries);
end;

procedure TAFileManagerController.FileDialogDecorateRow(
  ASender: TArosaControl; ARow: TArosaListRow; const AInfo: TArosaFileInfo);
begin
  { The standard requester deliberately delegates file presentation back to
    the same AFileManager row renderer.  That keeps semantic icons, .info
    handling, image thumbnails, hidden-resource appearance and configured
    spacing identical to the normal file surface. }
  PopulateIconRow(ARow,AInfo,False);
  if ASender=nil then ;
end;

function TAFileManagerController.FileDialogResolveIcon(
  const ASemantic: string; out AImage: TArosaPlatformHandle;
  out ASource: TArosaRect): Boolean;
var S: string;
begin
  S:=Trim(ASemantic);
  if Pos('theme:',LowerCase(S))<>1 then S:='theme:'+S;
  Result:=LoadThemeIcon(S,AImage,ASource);
end;

procedure TAFileManagerController.ConfigureStandardOpenDialogLocations;
const
  AssignNames: array[0..12] of string = ('AROS:', 'C:', 'DEVS:', 'ENV:',
    'ENVARC:', 'FONTS:', 'L:', 'LIBS:', 'PROGDIR:', 'RAM:', 'S:', 'SYS:', 'T:');
var
  G: TArosaTreeNode;
  P, Caption, Target: string;
  I: Integer;
begin
  if FBackgroundFileDialog=nil then Exit;
  FBackgroundFileDialog.ClearLocations;

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_places','Places'),'location-group');
  P:=Trim(FDescriptor.Value('Navigation','Home','SYS:'));
  if P='' then P:='SYS:';
  FBackgroundFileDialog.AddLocation(G,
    LocalText('afilemanager_home','Home'),P,'home');
  P:=Trim(FDescriptor.Value('Locations.Desktop','Desktop',
    FDescriptor.Value('Locations','UserDesktop','')));
  if P<>'' then FBackgroundFileDialog.AddLocation(G,
    LocalText('afilemanager_desktop','Desktop'),P,'desktop');
  P:=Trim(FDescriptor.Value('Locations.Desktop','Documents',
    FDescriptor.Value('Locations','UserDocuments','')));
  if P<>'' then FBackgroundFileDialog.AddLocation(G,
    LocalText('afilemanager_documents','Documents'),P,'documents');
  P:=Trim(FDescriptor.Value('Locations.Desktop','Downloads',
    FDescriptor.Value('Locations','UserDownloads','SYS:Work/Downloads')));
  if P<>'' then FBackgroundFileDialog.AddLocation(G,
    LocalText('afilemanager_downloads','Downloads'),P,'downloads');

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_favorites','Favorites'),'favorites');
  if FFavorites<>nil then
    for I:=0 to FFavorites.Count-1 do
      FBackgroundFileDialog.AddLocation(G,FFavorites.Names[I],
        FFavorites.ValueFromIndex[I],'favorite');

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_recent_locations','Recent Locations'),'history');
  if FRecentLocations<>nil then
    for I:=0 to FRecentLocations.Count-1 do
      FBackgroundFileDialog.AddLocation(G,FRecentLocations[I],
        FRecentLocations[I],'recent');

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_assigns','Assigns'),'assigns');
  for I:=Low(AssignNames) to High(AssignNames) do
    FBackgroundFileDialog.AddLocation(G,AssignNames[I],AssignNames[I],'assigns');

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_network','Network'),'network');
  if FNetworkLocations<>nil then
    for I:=0 to FNetworkLocations.Count-1 do
    begin
      Caption:=Trim(FNetworkLocations.Names[I]);
      Target:=Trim(FNetworkLocations.ValueFromIndex[I]);
      if Pos('|',Caption)>0 then Caption:=Copy(Caption,Pos('|',Caption)+1,MaxInt);
      if (Caption<>'') and (Target<>'') then
        FBackgroundFileDialog.AddLocation(G,Caption,Target,'network');
    end;

  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_devices','Devices'),'devices');
  FBackgroundFileDialog.AddLocation(G,'SYS:','SYS:','device');
  FBackgroundFileDialog.AddLocation(G,'RAM:','RAM:','device');
  FBackgroundFileDialog.AddLocation(G,'DEVS:','DEVS:','device');

  { Workspace catalogues are useful in common dialogs once Location Service is
    the lister: a workspace may expose favourites/recent/shared resources and
    those resolve to their actual provider locations. }
  G:=FBackgroundFileDialog.AddLocationGroup(
    LocalText('afilemanager_workspaces','AROSA Workspaces'),'workspaces');
  if FWorkspaces<>nil then
    for I:=0 to FWorkspaces.Count-1 do
      if FWorkspaces.Workspace(I)<>nil then
        FBackgroundFileDialog.AddLocation(G,FWorkspaces.Workspace(I).Name,
          'arosa://workspace/'+FWorkspaces.Workspace(I).Id,'workspaces');
end;

procedure TAFileManagerController.ShowWorkspaceModules(
  const AWorkspaceId: string);
var W: TArosaWorkspaceDefinition;
begin
  if (FWorkspaceModulesDialog=nil) or (FWorkspaceModules=nil) or
     (FWorkspaces=nil) then Exit;
  W:=FWorkspaces.Find(Trim(AWorkspaceId));
  if W=nil then Exit;
  { Another open workspace window may have changed membership. Refresh the
    durable registry before presenting the manager, then restore built-ins. }
  if (FWorkspaceRegistryPersistence<>nil) and
     (FPaths<>nil) and FPaths.Exists(FWorkspaceRegistryPath) then
  begin
    FWorkspaceRegistryPersistence.LoadRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath,True);
    FWorkspaceModules.SeedStandardModules;
  end;
  FWorkspaceModulesDialog.ShowModules(W.Id,W.Name,FWorkspaceModules);
end;

procedure TAFileManagerController.WorkspaceModuleChanged(
  ASender: TArosaControl; const AWorkspaceId, AModuleId: string;
  AEnabled: Boolean);
var K: Integer; Anywhere: Boolean;
begin
  if FWorkspaceModules=nil then Exit;
  FWorkspaceModules.SetEnabled(AWorkspaceId,AModuleId,AEnabled);
  if FWorkspaceRegistryPersistence<>nil then
    FWorkspaceRegistryPersistence.SaveRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath);
  { 0.8.6.6: a module that joins a workspace shows in its start menu unless
    it already shows somewhere; one that leaves is taken from all three }
  if AEnabled then
  begin
    Anywhere:=False;
    for K:=0 to 2 do
      if ModulePlacement(AWorkspaceId,AModuleId,K) then Anywhere:=True;
    if (not Anywhere) and FWorkspaceModules.IsEnabled(AWorkspaceId,AModuleId) then
      ApplyModulePlacement(AWorkspaceId,AModuleId,0,True);
  end
  else
    for K:=0 to 2 do ApplyModulePlacement(AWorkspaceId,AModuleId,K,False);
  Diagnostic('WORKSPACE module workspace='+AWorkspaceId+' module='+AModuleId+
    ' enabled='+BoolToStr(FWorkspaceModules.IsEnabled(AWorkspaceId,AModuleId),
      'TRUE','FALSE'));
  Inc(GWorkspaceMembershipGeneration);
  SyncWorkspaceMembership;
  SetStatus(LocalText('afilemanager_workspace_modules',
    'Manage workspace modules...'));
  if ASender=nil then ;
end;

function TAFileManagerController.ModulePlacement(const AWorkspaceId,
  AModuleId: string; AKind: Integer): Boolean;
var
  M: TArosaWorkspaceModule;
  Shortcuts: TArosaShortcutService;
  Pins: TArosaWorkspaceLauncherService;
  W: string;
begin
  Result:=False;
  W:=LowerCase(Trim(AWorkspaceId));
  if (W='') or (FWorkspaceModules=nil) or
     not FWorkspaceModules.Find(AModuleId,M) or (Trim(M.Target)='') then Exit;
  if AKind=1 then
  begin
    Pins:=TArosaWorkspaceLauncherService.CreateService(FFiles,FPaths,
      TArosaWorkspaceLauncherService.WorkspaceStoragePath(FDescriptorBase,W),W);
    try
      Pins.Load;
      Result:=Pins.ContainsTarget(M.Target);
    finally
      Pins.Free;
    end;
    Exit;
  end;
  if AKind=0 then
    Shortcuts:=TArosaShortcutService.CreateService(FFiles,FPaths,
      TArosaShortcutService.StartMenuStoragePath(FDescriptorBase,W),W)
  else
    Shortcuts:=TArosaShortcutService.CreateService(FFiles,FPaths,
      TArosaShortcutService.WorkspaceStoragePath(FDescriptorBase,W),W);
  try
    Shortcuts.Load;
    Result:=Shortcuts.ContainsTarget(M.Target);
  finally
    Shortcuts.Free;
  end;
end;

function TAFileManagerController.ApplyModulePlacement(const AWorkspaceId,
  AModuleId: string; AKind: Integer; AEnabled: Boolean): Boolean;
var
  M: TArosaWorkspaceModule;
  Shortcuts: TArosaShortcutService;
  Pins: TArosaWorkspaceLauncherService;
  W: string;
begin
  Result:=False;
  W:=LowerCase(Trim(AWorkspaceId));
  if (W='') or (FWorkspaceModules=nil) or
     not FWorkspaceModules.Find(AModuleId,M) or (Trim(M.Target)='') then Exit;
  if AEnabled and not M.Available then Exit;
  if AKind=1 then
  begin
    Pins:=TArosaWorkspaceLauncherService.CreateService(FFiles,FPaths,
      TArosaWorkspaceLauncherService.WorkspaceStoragePath(FDescriptorBase,W),W);
    try
      Pins.Load;
      if Pins.ContainsTarget(M.Target)=AEnabled then Result:=True
      else if AEnabled then Result:=Pins.AddApplicationPin(M.Name,M.Target)
      else Result:=Pins.RemovePin(M.Target);
      if not Result then
        Diagnostic('WORKSPACE placement failed kind=taskbar workspace='+W+
          ' module='+M.Id+' error='+Pins.LastError);
    finally
      Pins.Free;
    end;
    Exit;
  end;
  if AKind=0 then
    Shortcuts:=TArosaShortcutService.CreateService(FFiles,FPaths,
      TArosaShortcutService.StartMenuStoragePath(FDescriptorBase,W),W)
  else
    Shortcuts:=TArosaShortcutService.CreateService(FFiles,FPaths,
      TArosaShortcutService.WorkspaceStoragePath(FDescriptorBase,W),W);
  try
    Shortcuts.Load;
    if Shortcuts.ContainsTarget(M.Target)=AEnabled then Result:=True
    else if AEnabled then Result:=Shortcuts.AddShortcut(M.Target,M.Name)
    else Result:=Shortcuts.RemoveShortcut(M.Target);
    if not Result then
      Diagnostic('WORKSPACE placement failed kind='+IntToStr(AKind)+
        ' workspace='+W+' module='+M.Id+' error='+Shortcuts.LastError);
  finally
    Shortcuts.Free;
  end;
end;

procedure TAFileManagerController.ModulePlacementChanged(ASender: TArosaControl;
  const AWorkspaceId, AModuleId: string; AKind: Integer; AEnabled: Boolean);
const KindName: array[0..2] of string = ('start menu','taskbar','desktop');
begin
  if (AKind<0) or (AKind>2) then Exit;
  if ApplyModulePlacement(AWorkspaceId,AModuleId,AKind,AEnabled) then
    Diagnostic('WORKSPACE placement workspace='+AWorkspaceId+' module='+
      AModuleId+' '+KindName[AKind]+'='+BoolToStr(AEnabled,'TRUE','FALSE'))
  else
    SetStatus(LocalText('afilemanager_startmenu_failed',
      'The start menu could not be changed'));
  Inc(GWorkspaceMembershipGeneration);
  SyncWorkspaceMembership;
  if ASender=nil then ;
end;

procedure TAFileManagerController.SyncWorkspaceMembership;
var V: Integer; Cur: string;
begin
  FSeenMembershipGeneration:=GWorkspaceMembershipGeneration;
  { the registry and the catalogues are files every file manager writes }
  if (FWorkspaceRegistryPersistence<>nil) and (FWorkspaceModules<>nil) and
     (FPaths<>nil) and FPaths.Exists(FWorkspaceRegistryPath) then
  begin
    FWorkspaceRegistryPersistence.LoadRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath,True);
    FWorkspaceModules.SeedStandardModules;
  end;
  if FStartMenuService<>nil then FStartMenuService.Load;
  if FLauncherService<>nil then FLauncherService.Load;
  RebuildVirtualLocations;             { reads the desktop catalogue again }
  if FTaskbar<>nil then FTaskbar.Resync;
  for V:=0 to 1 do
  begin
    if ViewList(V)=nil then Continue;
    Cur:=LowerCase(Trim(ViewCurrent(V)));
    if (Pos('arosa://workspace/',Cur)=1) or (Cur='arosa://desktop') or
       (Cur='arosa://workspaces') then
    begin
      if FLocations<>nil then FLocations.Invalidate(ViewCurrent(V),False);
      RefreshView(V);
    end;
  end;
end;

procedure TAFileManagerController.WorkspaceBackgroundBrowse(
  ASender: TArosaControl);
var
  P, Dir, Name: string;
begin
  if FBackgroundFileDialog=nil then Exit;
  P:='';
  if FWorkspacePropertiesDialog<>nil then
    P:=FWorkspacePropertiesDialog.BackgroundImage;
  if P<>'' then
  begin
    Dir:=ArosaPathParent(P);
    Name:=ExtractFileName(StringReplace(P,':',PathDelim,[rfReplaceAll]));
    if Dir='' then Dir:='SYS:';
  end
  else
  begin
    Dir:='';
    { A common requester should resume where the user actually browsed last,
      not force SYS: on every invocation. }
    if (FRecentLocations<>nil) and (FRecentLocations.Count>0) and
       (FLocations<>nil) and FLocations.IsDirectory(FRecentLocations[0]) then
      Dir:=FRecentLocations[0];
    if Dir='' then Dir:=Trim(ViewCurrent(FActiveView));
    if (Dir='') or ((FLocations<>nil) and not FLocations.IsDirectory(Dir)) then
    begin
      if (FPlatform<>nil) and SameText(FPlatform.Name,'AROS') then Dir:='SYS:'
      else Dir:=GetCurrentDir;
    end;
    Name:='';
  end;
  FBackgroundFileDialog.ShowOpen(Dir,Name);
  if ASender=nil then ;
end;

procedure TAFileManagerController.WorkspaceBackgroundSelected(
  ASender: TArosaControl; const APath: string);
begin
  if (FWorkspacePropertiesDialog<>nil) and (Trim(APath)<>'') then
    FWorkspacePropertiesDialog.SetBackgroundImage(APath);
  if ASender=nil then ;
end;

procedure TAFileManagerController.WorkspacePropertiesApplied(
  ASender: TArosaControl; const ASettings: TAFMWorkspaceProperties);
var
  W: TArosaWorkspaceDefinition;
  OldName, OldThemeId, OldBackgroundImage, OldBackgroundMode,
    OldBackgroundGradientDirection, OldBackgroundLayerOrder: string;
  OldScreenWidth, OldScreenHeight, OldScreenDepth, OldBackgroundOpacity: Integer;
  OldBackgroundColour1, OldBackgroundColour2, OldBackgroundColour3, OldBackgroundColour4: TArosaColour;
  OldShareClipboard, OldShareDesk, NameChanged: Boolean;
begin
  W:=nil;
  if (FWorkspaces<>nil) and (FPendingEditWorkspaceId<>'') then
    W:=FWorkspaces.Find(FPendingEditWorkspaceId);

  if W=nil then
  begin
    SetStatus(LocalText('afilemanager_workspace_edit_failed',
      'Workspace properties could not be updated'));
    FPendingEditWorkspaceId:='';
    Exit;
  end;

  if Trim(ASettings.Name)='' then
  begin
    SetStatus(LocalText('afilemanager_workspace_name_empty',
      'Workspace name cannot be empty'));
    Exit;
  end;

  OldName:=W.Name;
  OldThemeId:=W.ThemeId;
  OldScreenWidth:=W.ScreenWidth;
  OldScreenHeight:=W.ScreenHeight;
  OldScreenDepth:=W.ScreenDepth;
  OldBackgroundImage:=W.BackgroundImage;
  OldBackgroundMode:=W.BackgroundMode; OldBackgroundColour1:=W.BackgroundColour1;
  OldBackgroundColour2:=W.BackgroundColour2; OldBackgroundColour3:=W.BackgroundColour3;
  OldBackgroundColour4:=W.BackgroundColour4; OldBackgroundGradientDirection:=W.BackgroundGradientDirection;
  OldBackgroundLayerOrder:=W.BackgroundLayerOrder; OldBackgroundOpacity:=W.BackgroundOpacity;
  OldShareClipboard:=W.ShareClipboard;
  OldShareDesk:=W.ShareDesk;
  NameChanged:=not SameText(OldName,Trim(ASettings.Name));

  if not FWorkspaces.RenameWorkspace(W.Id,Trim(ASettings.Name)) then
  begin
    SetStatus(LocalText('afilemanager_workspace_name_exists',
      'Another workspace already uses that name'));
    Exit;
  end;

  W.ThemeId:=Trim(ASettings.ThemeId);
  if W.ThemeId='' then W.ThemeId:='Dark';
  W.ScreenWidth:=ASettings.ScreenWidth;
  W.ScreenHeight:=ASettings.ScreenHeight;
  W.ScreenDepth:=ASettings.ScreenDepth;
  W.BackgroundImage:=Trim(ASettings.BackgroundImage);
  W.BackgroundMode:=LowerCase(Trim(ASettings.BackgroundMode)); if W.BackgroundMode<>'gradient' then W.BackgroundMode:='color';
  W.BackgroundColour1:=ASettings.BackgroundColour1; W.BackgroundColour2:=ASettings.BackgroundColour2;
  W.BackgroundColour3:=ASettings.BackgroundColour3; W.BackgroundColour4:=ASettings.BackgroundColour4;
  W.BackgroundGradientDirection:=LowerCase(Trim(ASettings.BackgroundGradientDirection));
  if W.BackgroundGradientDirection<>'vertical' then W.BackgroundGradientDirection:='horizontal';
  W.BackgroundLayerOrder:=LowerCase(Trim(ASettings.BackgroundLayerOrder));
  if W.BackgroundLayerOrder<>'after' then W.BackgroundLayerOrder:='before';
  W.BackgroundOpacity:=ASettings.BackgroundOpacity;
  if W.BackgroundOpacity<0 then W.BackgroundOpacity:=0 else if W.BackgroundOpacity>100 then W.BackgroundOpacity:=100;
  W.ShareClipboard:=ASettings.ShareClipboard;
  W.ShareDesk:=ASettings.ShareDesk;

  if SaveWorkspacesToUserProfile then
  begin
    RebuildVirtualLocations;
    if NameChanged then
      PublishLocationChanged('arosa://workspaces',almkRename)
    else
      PublishLocationChanged('arosa://workspaces',almkMetadata);
  PopulateAssignments;
    RefreshView(FPendingInputView);
    SetStatus(SysUtils.Format(
      LocalText('afilemanager_workspace_properties_saved',
        'Workspace properties saved: %s'),[W.Name]));
  end
  else
  begin
    { Persistence is the commit boundary. Restore the whole definition when
      the profile save fails so runtime state cannot diverge from the profile. }
    FWorkspaces.RenameWorkspace(W.Id,OldName);
    W.ThemeId:=OldThemeId;
    W.ScreenWidth:=OldScreenWidth;
    W.ScreenHeight:=OldScreenHeight;
    W.ScreenDepth:=OldScreenDepth;
    W.BackgroundImage:=OldBackgroundImage; W.BackgroundMode:=OldBackgroundMode;
    W.BackgroundColour1:=OldBackgroundColour1; W.BackgroundColour2:=OldBackgroundColour2;
    W.BackgroundColour3:=OldBackgroundColour3; W.BackgroundColour4:=OldBackgroundColour4;
    W.BackgroundGradientDirection:=OldBackgroundGradientDirection; W.BackgroundLayerOrder:=OldBackgroundLayerOrder;
    W.BackgroundOpacity:=OldBackgroundOpacity;
    W.ShareClipboard:=OldShareClipboard;
    W.ShareDesk:=OldShareDesk;
    SetStatus(LocalText('afilemanager_workspace_save_failed',
      'Workspace could not be saved to the user profile'));
  end;

  FPendingEditWorkspaceId:='';
  SetActiveView(FPendingInputView);
  if ASender=nil then ;
end;

procedure TAFileManagerController.RequestDeleteWorkspace(
  const AWorkspaceId: string);
var
  W: TArosaWorkspaceDefinition;
begin
  if (FWorkspaces=nil) or (Trim(AWorkspaceId)='') then Exit;
  W:=FWorkspaces.Find(Trim(AWorkspaceId));
  if W=nil then Exit;

  FPendingDeleteWorkspaceId:=W.Id;
  if FDeleteDialog<>nil then
    FDeleteDialog.ShowConfirmation(
      LocalText('afilemanager_workspace_delete','Delete workspace'),
      SysUtils.Format(
        LocalText('afilemanager_workspace_delete_confirm',
          'Delete workspace "%s"? Its referenced files and folders will not be deleted.'),
        [W.Name]),
      LocalText('afilemanager_workspace_delete','Delete workspace'),
      LocalText('afilemanager_cancel','Cancel'))
  else
    SetStatus(LocalText('afilemanager_workspace_dialog_unavailable',
      'Workspace dialog unavailable'));
end;

procedure TAFileManagerController.DeleteWorkspaceClick(ASender: TArosaControl);
var
  I: Integer;
  P, IdValue: string;
begin
  I:=ViewList(FActiveView).SelectedIndex;
  if I<0 then
  begin
    SetStatus(LocalText('afilemanager_workspace_select_delete',
      'Select a workspace to delete'));
    Exit;
  end;
  P:=SelectedPath(FActiveView,I);
  IdValue:=WorkspaceIdFromLocation(P);
  RequestDeleteWorkspace(IdValue);
  if ASender=nil then ;
end;

procedure TAFileManagerController.RequestTrashRestore;
var L: TArosaFilteredListView; P, OriginalPath: string;
begin
  if not IsWorkspaceTrashLocation(ViewCurrent(FActiveView)) then Exit;
  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedIndex<0) then Exit;
  P:=SelectedPath(FActiveView,L.SelectedIndex);
  if (FShellService=nil) or (FShellService.Trash=nil) or
     (not FShellService.Trash.OriginalPathFor(P,OriginalPath)) then
  begin
    SetStatus(LocalText('afilemanager_trash_restore_metadata_missing',
      'This legacy Trash item has no restore location metadata'));
    Exit;
  end;
  if FPaths.Exists(OriginalPath) then
  begin
    SetStatus(SysUtils.Format(
      LocalText('afilemanager_trash_restore_exists',
        'Cannot restore: the original location already exists (%s)'),
      [OriginalPath]));
    Exit;
  end;
  FPendingDeleteItems.Clear;
  FPendingDeleteItems.Add(P);
  FPendingDeleteView:=FActiveView;
  FPendingTrashRestore:=True;
  if FDeleteDialog<>nil then
    FDeleteDialog.ShowConfirmation(
      LocalText('afilemanager_trash_restore_title','Restore from Trash'),
      SysUtils.Format(
        LocalText('afilemanager_trash_restore_confirm','Restore to %s?'),
        [OriginalPath]),
      LocalText('afilemanager_trash_restore','Restore'),
      LocalText('afilemanager_cancel','Cancel'));
end;

procedure TAFileManagerController.ExecuteTrashRestore;
var TrashPath, OriginalPath: string; Ok: Boolean;
begin
  Ok:=False; OriginalPath:='';
  if FPendingDeleteItems.Count>0 then
  begin
    TrashPath:=FPendingDeleteItems[0];
    if (FShellService<>nil) and (FShellService.Trash<>nil) then
      Ok:=FShellService.Trash.RestoreByTrashPath(TrashPath,OriginalPath);
  end;
  FPendingDeleteItems.Clear;
  FPendingTrashRestore:=False;
  RebuildVirtualLocations;
  PublishLocationChanged(
    'arosa://workspace/'+FActiveWorkspaceId+'/trash',almkRestore);
  RefreshView(FPendingDeleteView);
  if Ok then
    SetStatus(SysUtils.Format(
      LocalText('afilemanager_trash_restored','Restored to %s'),
      [OriginalPath]))
  else
    SetStatus(LocalText('afilemanager_trash_restore_failed',
      'The Trash item could not be restored'));
end;

procedure TAFileManagerController.RequestPermanentTrashDelete;
var
  I: Integer;
  L: TArosaFilteredListView;
begin
  if not IsWorkspaceTrashLocation(ViewCurrent(FActiveView)) then Exit;
  FPendingDeleteItems.Clear;
  FPendingDeleteView:=FActiveView;
  L:=ViewList(FActiveView);
  if L=nil then Exit;
  CollectSelectedPaths(FActiveView,FPendingDeleteItems);
  if (FPendingDeleteItems.Count=0) and (L.SelectedIndex>=0) then
    FPendingDeleteItems.Add(SelectedPath(FActiveView,L.SelectedIndex));
  if FPendingDeleteItems.Count=0 then Exit;

  FPendingPermanentTrashDelete:=True;
  if FDeleteDialog<>nil then
    FDeleteDialog.ShowConfirmation(
      LocalText('afilemanager_trash_delete_permanently_title',
        'Delete permanently'),
      SysUtils.Format(
        LocalText('afilemanager_trash_delete_permanently_confirm',
          'Permanently delete %d selected item(s) from this workspace Trash?'),
        [FPendingDeleteItems.Count]),
      LocalText('afilemanager_trash_delete_permanently',
        'Delete permanently'),
      LocalText('afilemanager_cancel','Cancel'));
end;

procedure TAFileManagerController.ExecutePermanentTrashDelete;
var
  I, Done: Integer;
  P: string;
begin
  Done:=0;
  for I:=0 to FPendingDeleteItems.Count-1 do
  begin
    P:=FPendingDeleteItems[I];
    if DeleteResourceRecursive(P) then
    begin
      if (FShellService<>nil) and (FShellService.Trash<>nil) then
        FShellService.Trash.Forget(P);
      Inc(Done);
    end;
  end;
  FPendingDeleteItems.Clear;
  FPendingPermanentTrashDelete:=False;
  FPendingTrashRestore:=False;
  RebuildVirtualLocations;
  PublishLocationChanged(
    'arosa://workspace/'+FActiveWorkspaceId+'/trash',almkDelete);
  RefreshView(FPendingDeleteView);
  SetStatus(SysUtils.Format(
    LocalText('afilemanager_trash_deleted_permanently',
      'Permanently deleted %d item(s) from Trash'),
    [Done]));
end;

procedure TAFileManagerController.EmptyTrash;
var Entries: TArosaTrashEntryArray; I, Done: Integer;
begin
  Done:=0;
  if (FShellService=nil) or (FShellService.Trash=nil) then Exit;
  if not FShellService.Trash.ListEntriesForScope(FActiveWorkspaceId,Entries) then
  begin
    SetStatus(LocalText('afilemanager_trash_open_failed','Cannot enumerate the trash'));
    Exit;
  end;
  if Length(Entries)=0 then
  begin
    SetStatus(LocalText('afilemanager_trash_empty_status','Trash is already empty'));
    Exit;
  end;
  for I:=0 to High(Entries) do
    if DeleteResourceRecursive(Entries[I].TrashPath) then
    begin
      FShellService.Trash.Forget(Entries[I].TrashPath);
      Inc(Done);
    end;
  RebuildVirtualLocations;
  PublishLocationChanged('arosa://workspace/'+FActiveWorkspaceId+'/trash',almkTrash);
  SetStatus(SysUtils.Format(
    LocalText('afilemanager_trash_cleared','Trash cleared: %d item(s) removed'),
    [Done]));
end;

procedure TAFileManagerController.LoadFavorites;
var Text: string; L, Sec: TStringList; I: Integer; N, V: string;
begin
  if FFavorites=nil then Exit;
  FFavorites.Clear;
  L:=TStringList.Create;
  try
    L.NameValueSeparator:='=';
    if StateRead('favorites',FFavoritesPath,False,Text) then
    begin
      L.Text:=Text;
      for I:=0 to L.Count-1 do
      begin
        N:=Trim(L.Names[I]); V:=Trim(L.ValueFromIndex[I]);
        { Remove the old prototype favorite. AROSA Workspaces is now a real
          root entity and must not also appear as an undeletable favorite. }
        if SameText(N,'AROSA workspace') and
           SameText(V,'SYS:Work/Downloads/AROSA') then Continue;
        if (N<>'') and (V<>'') and (N[1]<>';') then FFavorites.Add(N+'='+V);
      end;
      if L.IndexOfName('AROSA workspace')>=0 then SaveFavorites;
      Exit;
    end;
  finally L.Free; end;
  { First run: seed from the descriptor (or the built-in pair). }
  if FDescriptor<>nil then
  begin
    Sec:=FDescriptor.Section('Locations.Favorites');
    try
      for I:=0 to Sec.Count-1 do
      begin
        N:=Trim(Sec.Names[I]); V:=Trim(Sec.ValueFromIndex[I]);
        if SameText(N,'Provider') or SameText(N,'MaxEntries') or (V='') then Continue;
        FFavorites.Add(N+'='+V);
      end;
    finally Sec.Free; end;
  end;
  if FFavorites.Count=0 then
    FFavorites.Add('AFileManager=PROGDIR:');
end;

procedure TAFileManagerController.SaveFavorites;
begin
  if (FFavorites=nil) or (FFiles=nil) then Exit;
  if not StateWrite('favorites',FFavoritesPath,False,FFavorites.Text) then
    Diagnostic('FAVORITES save failed path='+FFavoritesPath);
end;

function TAFileManagerController.AddFavorite(const APath: string): Boolean;
var Name, P: string; I, N: Integer;
begin
  Result:=False;
  P:=Trim(APath);
  if (P='') or (FavoriteIndex(P)>=0) then Exit;
  Name:=FPaths.SplitFileName(P);
  if Name='' then Name:=P;   { a volume/assign root such as RAM: }
  { keep captions unique: "Docs", "Docs (2)" ... }
  N:=1;
  while FFavorites.IndexOfName(Name)>=0 do
  begin
    Inc(N);
    I:=Pos(' (',Name); if I>0 then Name:=Copy(Name,1,I-1);
    Name:=Name+' ('+IntToStr(N)+')';
  end;
  FFavorites.Add(Name+'='+P);
  SaveFavorites;
  PopulateAssignments;
  RebuildVirtualLocations;
  PublishLocationChanged('arosa://workspace/'+FActiveWorkspaceId+
    '/favorites',almkMetadata);
  PublishLocationChanged('arosa://favorites',almkMetadata);
  PublishLocationChanged('arosa://desktop',almkMetadata);
  Result:=True;
end;

function TAFileManagerController.RemoveFavorite(const APath: string): Boolean;
var I: Integer;
begin
  I:=FavoriteIndex(APath);
  Result:=I>=0;
  if not Result then Exit;
  FFavorites.Delete(I);
  SaveFavorites;
  PopulateAssignments;
end;

{ Replace the Favorites.Toggle placeholder (or append at the end, after a
  separator, when the descriptor has none) with the entry that fits
  ATarget: Favorites.Add when it is not a favourite, Favorites.Remove when
  it is; nothing when there is no directory target. }
procedure TAFileManagerController.ExpandFavoriteEntry(AItems: TStringList;
  const ATarget: string);
var I: Integer; Entry: string;
begin
  if AItems=nil then Exit;
  Entry:='';
  if ATarget<>'' then
  begin
    if FavoriteIndex(ATarget)>=0 then
      Entry:='Favorites.Remove='+LocalText('afilemanager_favorites_remove','Remove from favorites')
    else
      Entry:='Favorites.Add='+LocalText('afilemanager_favorites_add','Add to favorites');
  end;
  I:=AItems.IndexOfName('Favorites.Toggle');
  if I>=0 then
  begin
    if Entry<>'' then AItems[I]:=Entry else AItems.Delete(I);
  end
  else if Entry<>'' then
  begin
    AItems.Add('Separator.Favorites=-');
    AItems.Add(Entry);
  end;
end;

{ The location a list context menu acts on: the single selected folder, or
  the folder being shown when nothing is selected. }
function TAFileManagerController.ListFavoriteTarget(AView: Integer): string;
var L: TArosaFilteredListView; P: string; R: TArosaListRow;
begin
  Result:='';
  L:=ViewList(AView);
  if L=nil then Exit;
  if L.SelectedCount=0 then Exit(ViewCurrent(AView));
  if L.SelectedCount<>1 then Exit;
  P:=SelectedPath(AView,L.SelectedIndex);
  R:=nil;
  if (L.SelectedIndex>=0) and (L.SelectedIndex<L.VisibleRowCount) then
    R:=L.VisibleRowsView[L.SelectedIndex];
  { Menu construction must be presentation-only.  Never call a provider or
    filesystem probe while the pointer is waiting for its context menu. }
  if (P<>'') and (ExtractFileName(P)<>'..') and (R<>nil) and
     ((R.UserFlags and AFM_ROW_FOLDER)<>0) then Result:=P;
end;

{ Properties for any path (list item or Places location): resource
  metadata plus, for every location, its volume capacity. Shown in the
  selected side's Metadata tab. }
procedure TAFileManagerController.ShowProperties(AView: Integer; const APath: string);
var M: TArosaResourceMetadata; Target: TArosaMetadataView; V: TArosaVolumeInfo;
    Info: TArosaFileInfo; KindText: string;
begin
  if Trim(APath)='' then begin SetStatus('Select a resource to view properties'); Exit; end;
  if AView=0 then Target:=FMetadataView else Target:=FRightMetadataView;
  M:=nil;

  { Resource metadata providers are still local-filesystem based.  For a
    provider URI, obtain the basic metadata through Location Service instead
    of allowing Resource/File services to hand the URI to AmigaDOS. }
  if IsProviderLocation(APath) then
  begin
    M:=TArosaResourceMetadata.Create;
    M.AddAttribute('resource.location','arosa_metadata_location','general',APath,20);
    if (FLocations<>nil) and FLocations.GetInfo(APath,Info) then
    begin
      M.AddAttribute('resource.name','arosa_metadata_name','general',Info.Name,10);
      if Info.Kind=afekDirectory then KindText:='Directory' else KindText:='File';
      M.AddAttribute('resource.kind','Type','general',KindText,30);
      if Info.Kind<>afekDirectory then
        M.AddAttribute('resource.size','arosa_metadata_size','general',IntToStr(Info.Size),40,'bytes');
      if Info.ModifiedUtc>0 then
        M.AddAttribute('resource.modified','arosa_metadata_modified','general',DateTimeToStr(Info.ModifiedUtc),50);
    end
    else
      M.AddAttribute('resource.status','Status','general','Remote metadata unavailable',30);
  end
  else
  begin
    if not FResources.ProbeMetadata(APath,M) then
    begin
      SetStatus('Properties unavailable: '+APath);
      Exit;
    end;
    if (FFiles<>nil) and FPaths.IsDirectory(APath) and FFiles.GetVolumeInfo(APath,V) and V.Available then
    begin
      if V.RootPath<>'' then
        M.AddAttribute('volume.root','afilemanager_metadata_volume','volume',V.RootPath,900);
      M.AddAttribute('volume.total','afilemanager_metadata_volume_total','volume',SizeText(V.TotalBytes),901);
      M.AddAttribute('volume.free','afilemanager_metadata_volume_free','volume',SizeText(V.FreeBytes),902);
      if (V.TotalBytes>0) and (V.TotalBytes>=V.FreeBytes) then
        M.AddAttribute('volume.used','afilemanager_metadata_volume_used','volume',
          SizeText(V.TotalBytes-V.FreeBytes)+'  ('+
          IntToStr(Round(100.0*(V.TotalBytes-V.FreeBytes)/V.TotalBytes))+'%)',903);
    end;
  end;
  if Target<>nil then Target.SetMetadata(M) else M.Free;
  FMetadataVisible:=True;
  if (FWindowFrame<>nil) and (FWindowFrame.PreviewPlacement=0) then
    FWindowFrame.SetPreviewPlacement(FPreviewPreferredPlacement);
end;
{ 0.5.110.13 - context-menu composition.
  File.Copy and Resource.Copy (likewise Cut/Paste/Delete/Rename) are two
  distinct command IDENTITIES: File.* is the file-system command surface used
  by keyboard/toolbar/macros, Resource.* the resource-model surface. Both stay
  registered in the dispatcher. They are however ONE user action, so a menu
  must present it once. The operations descriptor listed both families and
  the complete descriptor inherits it, producing duplicate Copy/Paste/Delete
  rows. Presentation keeps the Resource.* entry (canonical for resources) and
  drops its File.* alias; a File.* entry with no Resource.* counterpart is
  kept, so a descriptor that only lists File.* still gets its commands. }
procedure TAFileManagerController.ComposeResourceContextMenu(AItems: TStringList);
const
  Aliases: array[0..4] of string = ('Copy','Cut','Paste','Delete','Rename');
var I, J: Integer;
begin
  if AItems=nil then Exit;
  for I:=Low(Aliases) to High(Aliases) do
    if AItems.IndexOfName('Resource.'+Aliases[I])>=0 then
    begin
      J:=AItems.IndexOfName('File.'+Aliases[I]);
      if J>=0 then AItems.Delete(J);
    end;
end;

procedure TAFileManagerController.BuildPlacesContextMenu;
begin
  if (FAssignments=nil) or (FDescriptor=nil) then Exit;
  if not FDescriptor.BoolValue('Capabilities','ContextMenu',False) then Exit;
  FAssignments.OnContextMenuOpening:=@PlacesContextMenuOpening;
  FAssignments.OnContextCommand:=@PlacesContextCommand;
  FAssignments.SetOnContextCommandIcon(@ContextCommandIcon);
  FAssignments.OnContextCommandEnabled:=@PlacesContextCommandEnabled;
  { The items are composed when the menu opens, for the clicked location. }
  PlacesContextMenuOpening(nil);
end;

procedure TAFileManagerController.PlacesContextMenuOpening(ASender: TArosaControl);
var Items, Section: TStringList; I: Integer; N: TArosaTreeNode; Target: string;
begin
  if ASender<>nil then
  begin
    if (FWindowFrame<>nil) and FWindowFrame.MenuOpen then FWindowFrame.ToggleMenu;
    if FLeftList<>nil then FLeftList.DismissContextMenu;
    if FRightList<>nil then FRightList.DismissContextMenu;
  end;
  if FAssignments=nil then Exit;
  Items:=TStringList.Create;
  try
    Items.NameValueSeparator:='=';
    Section:=FDescriptor.MenuSection('PlacesMenu');
    try
      if Section.Count>0 then Items.Assign(Section);
    finally Section.Free; end;
    if Items.Count=0 then
    begin
      Items.Add('Places.Open=@afilemanager_places_open');
      Items.Add('Places.OpenLeft=@afilemanager_places_open_left');
      Items.Add('Places.OpenRight=@afilemanager_places_open_right');
      Items.Add('Separator.Favorites=-');
      Items.Add('Favorites.Toggle=-');
      Items.Add('Separator.Info=-');
      Items.Add('Places.Properties=@afilemanager_places_properties');
      Items.Add('Places.Edit=Edit');
      Items.Add('Separator.Refresh=-');
      Items.Add('Places.Refresh=@afilemanager_places_refresh');
    end;
    for I:=0 to Items.Count-1 do
      Items.ValueFromIndex[I]:=LocalValue(Items.ValueFromIndex[I],Items.Names[I]);
    Target:='';
    N:=FAssignments.SelectedNode;

    if (N<>nil) and SameText(Trim(N.Hint),'arosa://workspaces') then
    begin
      Items.Clear;
      Items.Add('Places.Open=@afilemanager_places_open');
      Items.Add('Separator.Workspaces=-');
      Items.Add('Workspace.Create=@afilemanager_workspace_create');
      Items.Add('Workspace.Edit=@afilemanager_workspace_edit_properties');
      Items.Add('Workspace.Modules=@afilemanager_workspace_modules');
      Items.Add('Separator.Info=-');
      Items.Add('Places.Properties=@afilemanager_places_properties');
      FAssignments.SetContextMenuItems(Items);
      Exit;
    end
    else if (N<>nil) and
            (FWorkspaces<>nil) and
            (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil) and
            (Pos('/',WorkspaceIdFromLocation(Trim(N.Hint)))=0) then
    begin
      Items.Clear;
      Items.Add('Places.Open=@afilemanager_workspace_open');
      Items.Add('Separator.Workspaces=-');
      Items.Add('Workspace.Create=@afilemanager_workspace_create');
      Items.Add('Workspace.Edit=@afilemanager_workspace_edit_properties');
      Items.Add('Workspace.Modules=@afilemanager_workspace_modules');
      Items.Add('Workspace.PinAFileManager=Pin / unpin AFileManager on taskbar');
      Items.Add('Workspace.Delete=@afilemanager_workspace_delete');
      Items.Add('Separator.Info=-');
      Items.Add('Places.Properties=@afilemanager_places_properties');
      FAssignments.SetContextMenuItems(Items);
      Exit;
    end;

    if (N<>nil) and SameText(Trim(N.Text),'Network') and (Trim(N.Hint)='') then
    begin
      Items.Insert(0,'Places.AddNetwork=Add network location...');
      Items.Insert(1,'Separator.Network=-');
    end
    else if (N<>nil) and (NetworkLocationIndex(Trim(N.Hint))>=0) then
    begin
      if Items.IndexOfName('Places.Edit')<0 then
        Items.Add('Places.Edit=Edit network location...');
      Items.Add('Separator.Network=-');
      Items.Add('Places.DeleteNetwork=Delete network location');
    end;
    if (N<>nil) and (Trim(N.Hint)<>'') then
    begin
      { N.Hint is already the location represented by the retained Places row.
        Do not re-probe it while opening the menu: provider-backed IsDirectory
        can wait on network/worker state and make the menu appear dead. }
      Target:=N.Hint;
    end;
    ExpandFavoriteEntry(Items,Target);
    FAssignments.SetContextMenuItems(Items);
  finally Items.Free; end;
end;

function TAFileManagerController.PlacesContextCommandEnabled(ASender: TArosaControl;
  const ACommand: string): Boolean;
var N: TArosaTreeNode;
begin
  if SameText(ACommand,'Places.Refresh') then Exit(True);
  if SameText(ACommand,'Places.AddNetwork') then Exit(True);
  N:=nil; if FAssignments<>nil then N:=FAssignments.SelectedNode;
  if SameText(ACommand,'Workspace.Create') then
    Exit((N<>nil) and
      (SameText(Trim(N.Hint),'arosa://workspaces') or
       ((FWorkspaces<>nil) and
        (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil))));
  if SameText(ACommand,'Workspace.Modules') then
  begin
    if N=nil then Exit(False);
    if SameText(Trim(N.Hint),'arosa://workspaces') then
      Exit((FWorkspaces<>nil) and
        (FWorkspaces.Find(FActiveWorkspaceId)<>nil));
    Exit((FWorkspaces<>nil) and
      (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil) and
      (Pos('/',WorkspaceIdFromLocation(Trim(N.Hint)))=0));
  end;
  if SameText(ACommand,'Workspace.PinAFileManager') then
  begin
    if N=nil then Exit(False);
    if SameText(Trim(N.Hint),'arosa://workspaces') then
      Exit(FLauncherService<>nil);
    Exit((FWorkspaces<>nil) and
      (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil) and
      (Pos('/',WorkspaceIdFromLocation(Trim(N.Hint)))=0));
  end;
  if SameText(ACommand,'Workspace.Delete') then
    Exit((N<>nil) and (FWorkspaces<>nil) and
      (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil) and
      (Pos('/',WorkspaceIdFromLocation(Trim(N.Hint)))=0));
  if SameText(ACommand,'Workspace.Edit') then
  begin
    if N=nil then Exit(False);
    { The WorkSpaces root is the owning/current workspace. It must expose the
      same Edit workspace properties command as an explicit workspace node. }
    if SameText(Trim(N.Hint),'arosa://workspaces') then
      Exit((FWorkspaces<>nil) and
        (FWorkspaces.Find(FActiveWorkspaceId)<>nil));
    Exit((FWorkspaces<>nil) and
      (FWorkspaces.Find(WorkspaceIdFromLocation(Trim(N.Hint)))<>nil) and
      (Pos('/',WorkspaceIdFromLocation(Trim(N.Hint)))=0));
  end;
  if SameText(ACommand,'Places.Edit') then
    Exit((N<>nil) and (NetworkLocationIndex(Trim(N.Hint))>=0));
  if SameText(ACommand,'Places.DeleteNetwork') then
    Exit((N<>nil) and (NetworkLocationIndex(Trim(N.Hint))>=0));
  Result:=(N<>nil) and (Trim(N.Hint)<>'');
  if Result and (NetworkLocationIndex(Trim(N.Hint))<0) then
    Result:=(FLocations<>nil) and FLocations.IsDirectory(N.Hint);
  if Result and SameText(ACommand,'Places.OpenRight') then Result:=FRightList<>nil;
  { Properties also works for a location that is not a directory
    (an unmounted device reports "unavailable" rather than being hidden). }
  if SameText(ACommand,'Places.Properties') then
    Result:=(N<>nil) and (Trim(N.Hint)<>'');
  if ASender=nil then ;
end;

procedure TAFileManagerController.PlacesContextCommand(ASender: TArosaControl;
  const ACommand: string);
var N: TArosaTreeNode; P: string;
begin
  Diagnostic('COMMAND dispatch id='+ACommand+' source=places');
  if SameText(ACommand,'Places.Refresh') then
  begin
    PopulateAssignments;
    SetStatus(LocalText('afilemanager_places_refreshed','Places refreshed'));
    Exit;
  end;
  if SameText(ACommand,'Places.AddNetwork') then
  begin
    ShowAddNetworkLocation;
    Exit;
  end;
  N:=nil; if FAssignments<>nil then N:=FAssignments.SelectedNode;
  if N=nil then Exit;
  { Favourite edits rebuild the Places tree (freeing N): use a copy. }
  P:=Trim(N.Hint); N:=nil;
  if SameText(ACommand,'Places.DeleteNetwork') then
  begin
    if NetworkLocationIndex(P)>=0 then
    begin
      FNetworkLocations.Delete(NetworkLocationIndex(P));
      SaveNetworkLocations; PopulateAssignments; SetStatus('Network location deleted');
    end;
    Exit;
  end;
  if P='' then Exit;
  if SameText(ACommand,'Workspace.Create') then
  begin
    CreateWorkspaceClick(ASender);
    Exit;
  end;
  if SameText(ACommand,'Workspace.Modules') then
  begin
    if SameText(P,'arosa://workspaces') then
      ShowWorkspaceModules(FActiveWorkspaceId)
    else
      ShowWorkspaceModules(WorkspaceIdFromLocation(P));
    Exit;
  end;
  if SameText(ACommand,'Workspace.PinAFileManager') then
  begin
    if FLauncherService<>nil then
    begin
      FLauncherService.Load;
      if FLauncherService.ContainsTarget('exec:AFILEMANAGER:AFileManager') then
      begin
        if FLauncherService.RemovePin('exec:AFILEMANAGER:AFileManager') then
          SetStatus('AFileManager removed from '+FActiveWorkspaceId+' taskbar')
        else SetStatus('Could not remove taskbar pin: '+FLauncherService.LastError);
      end
      else if FLauncherService.AddApplicationPin('AFileManager',
          'AFILEMANAGER:AFileManager') then
        SetStatus('AFileManager pinned to '+FActiveWorkspaceId+' taskbar')
      else SetStatus('Could not pin AFileManager: '+FLauncherService.LastError);
    end;
    Exit;
  end;
  if SameText(ACommand,'Workspace.Delete') then
  begin
    RequestDeleteWorkspace(WorkspaceIdFromLocation(P));
    Exit;
  end;
  if SameText(ACommand,'Workspace.Edit') then
  begin
    { The WorkSpaces root represents the workspace owning this AFileManager
      window. Editing that node must edit the active workspace rather than
      the synthetic arosa://workspaces catalogue location. }
    if SameText(P,'arosa://workspaces') then
      RequestEditWorkspaceProperties(FActiveWorkspaceId)
    else
      RequestEditWorkspaceProperties(WorkspaceIdFromLocation(P));
    Exit;
  end;
  if SameText(ACommand,'Places.Open') and ActivateWorkspaceLocation(P) then Exit;
  if SameText(ACommand,'Places.Properties') then ShowPlaceProperties(P)
  else if SameText(ACommand,'Places.Edit') then begin if FPlacesDetailTabs<>nil then FPlacesDetailTabs.ActiveIndex:=1; EditSelectedPlace(ASender); end
  else if SameText(ACommand,'Desktop.Add') then
  begin
    if AddDesktopShortcut(SelectedPath(FActiveView,
      ViewList(FActiveView).SelectedIndex)) then
      SetStatus(LocalText('afilemanager_desktop_added','Shortcut added to Desktop'));
    Inc(GWorkspaceMembershipGeneration);
  end
  else if SameText(ACommand,'StartMenu.Add') then
  begin
    if AddStartMenuEntry(SelectedPath(FActiveView,
      ViewList(FActiveView).SelectedIndex)) then
    begin
      SetStatus(LocalText('afilemanager_startmenu_added','Added to the start menu'));
      Inc(GWorkspaceMembershipGeneration);
    end
    else if FStartMenuService<>nil then
      SetStatus(LocalText('afilemanager_startmenu_failed',
        'The start menu could not be changed')+': '+FStartMenuService.LastError);
  end
  else if SameText(ACommand,'StartMenu.Remove') then
  begin
    if RemoveStartMenuEntry(SelectedPath(FActiveView,
      ViewList(FActiveView).SelectedIndex)) then
    begin
      SetStatus(LocalText('afilemanager_startmenu_removed','Removed from the start menu'));
      Inc(GWorkspaceMembershipGeneration);
    end
    else if FStartMenuService<>nil then
      SetStatus(LocalText('afilemanager_startmenu_failed',
        'The start menu could not be changed')+': '+FStartMenuService.LastError);
  end
  else if SameText(ACommand,'Desktop.Remove') then
  begin
    if RemoveDesktopShortcut(SelectedPath(FActiveView,
      ViewList(FActiveView).SelectedIndex)) then
      SetStatus(LocalText('afilemanager_desktop_removed','Shortcut removed from Desktop'));
    Inc(GWorkspaceMembershipGeneration);
  end
  else if SameText(ACommand,'Trash.Empty') then
  begin
    FPendingEmptyTrash:=True;
    if FDeleteDialog<>nil then
      FDeleteDialog.ShowConfirmation(
        LocalText('afilemanager_trash_empty_title','Empty Trash'),
        LocalText('afilemanager_trash_empty_confirm',
          'Permanently remove all items from the AROSA trash?'),
        LocalText('afilemanager_trash_empty','Empty Trash'),
        LocalText('afilemanager_cancel','Cancel'));
  end
  else if SameText(ACommand,'Favorites.Add') then
  begin
    if AddFavorite(P) then SetStatus('Added to favorites: '+P);
  end
  else if SameText(ACommand,'Favorites.Remove') then
  begin
    if RemoveFavorite(P) then SetStatus('Removed from favorites: '+P);
  end
  else if SameText(ACommand,'Places.Open') then NavigateView(FActiveView,P)
  else if SameText(ACommand,'Places.OpenLeft') then begin SetActiveView(0); NavigateView(0,P); end
  else if SameText(ACommand,'Places.OpenRight') and (FRightList<>nil) then
    begin SetActiveView(1); NavigateView(1,P); end;
  if ASender=nil then ;
end;

function TAFileManagerController.TryResourceContextCommand(ASender: TArosaControl;
  const ACommand: string): Boolean;
var I: Integer;
begin
  Result:=True;
  if ASender=FRightList then SetActiveView(1) else SetActiveView(0);
  ArosaTrace('CONTEXT','command='+ACommand+' view='+IntToStr(FActiveView)+
    ' selected='+IntToStr(ViewList(FActiveView).SelectedCount));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
  Diagnostic('COMMAND dispatch id='+ACommand+' view='+IntToStr(FActiveView)+
    ' selected='+IntToStr(ViewList(FActiveView).SelectedCount));
  if SameText(ACommand,'Console.OpenHere') then
  begin
    OpenConsoleHereClick(ASender);
    Exit;
  end;
  { 0.10.6.2: the Move / Copy / Cancel menu of a drop that asks }
  if TryDropMenuCommand(ACommand) then Exit;
  if SameText(ACommand,'Navigation.Refresh') or SameText(ACommand,'Resource.Refresh') then
  begin
    if FLocations<>nil then FLocations.Invalidate(ViewCurrent(FActiveView));
    if (FContent<>nil) and IsProviderLocation(ViewCurrent(FActiveView)) then
      FContent.InvalidateTree(ViewCurrent(FActiveView));
    RefreshView(FActiveView);
  end
  else if SameText(ACommand,'Selection.All') then SelectAllClick(ASender)
  else if SameText(ACommand,'Selection.None') then ClearSelectionClick(ASender)
  else if SameText(ACommand,'Workspace.PinSelected') then
  begin
    I:=ViewList(FActiveView).SelectedIndex;
    if (I>=0) and (FLauncherService<>nil) then
    begin
      FListFavoriteTarget:=SelectedPath(FActiveView,I);
      FLauncherService.Load;
      if FLauncherService.AddPin(FListFavoriteTarget,
           ShortcutDisplayName(FListFavoriteTarget)) then
      begin
        SetStatus('Pinned to '+FActiveWorkspaceId+' taskbar');
        Inc(GWorkspaceMembershipGeneration);
      end
      else if FLauncherService.ContainsTarget(FListFavoriteTarget) then
        SetStatus('Already pinned to '+FActiveWorkspaceId+' taskbar')
      else
        SetStatus('Could not pin application: '+FLauncherService.LastError);
    end;
  end
  else if SameText(ACommand,'Workspace.UnpinSelected') then
  begin
    I:=ViewList(FActiveView).SelectedIndex;
    if (I>=0) and (FLauncherService<>nil) then
    begin
      FListFavoriteTarget:=SelectedPath(FActiveView,I);
      FLauncherService.Load;
      if FLauncherService.RemovePin(FListFavoriteTarget) then
      begin
        SetStatus('Removed from '+FActiveWorkspaceId+' taskbar');
        Inc(GWorkspaceMembershipGeneration);
      end
      else
        SetStatus('Could not remove taskbar pin: '+FLauncherService.LastError);
    end;
  end
  else if SameText(ACommand,'Resource.Open') then
  begin
    I:=ViewList(FActiveView).SelectedIndex;
    if I>=0 then ActivateItem(FActiveView,I);
  end
  else if SameText(ACommand,'Resource.Preview') then
  begin
    if FWindowFrame.PreviewPlacement=0 then FWindowFrame.CyclePreviewPlacement;
    UpdatePreview(FActiveView);
    SetStatus(LocalText('afilemanager_status_previewing','Previewing selected resource'));
  end
  else if SameText(ACommand,'Workspace.Create') then CreateWorkspaceClick(ASender)
  else if SameText(ACommand,'Workspace.Delete') then DeleteWorkspaceClick(ASender)
  else if SameText(ACommand,'Workspace.CloseScreen') then WorkspaceCloseScreenClick(ASender)
  else if SameText(ACommand,'Resource.CreateFolder') then CreateFolderClick(ASender)
  else if SameText(ACommand,'Resource.CreateFile') then CreateFileClick(ASender)
  else if SameText(ACommand,'Resource.Rename') then RenameClick(ASender)
  else if SameText(ACommand,'Resource.Copy') or SameText(ACommand,'File.Copy') then CopyClick(ASender)
  else if SameText(ACommand,'Resource.Cut') or SameText(ACommand,'File.Cut') then CutClick(ASender)
  else if SameText(ACommand,'Resource.Paste') or SameText(ACommand,'File.Paste') then PasteClick(ASender)
  else if SameText(ACommand,'Resource.MoveTo') then MoveToSelected(ASender)
  else if SameText(ACommand,'Trash.Restore') then
    RequestTrashRestore
  else if SameText(ACommand,'Trash.DeletePermanently') then
    RequestPermanentTrashDelete
  else if SameText(ACommand,'Trash.Empty') then
  begin
    FPendingEmptyTrash:=True;
    if FDeleteDialog<>nil then
      FDeleteDialog.ShowConfirmation(
        LocalText('afilemanager_trash_empty_title','Empty Trash'),
        LocalText('afilemanager_trash_empty_confirm',
          'Permanently remove all items from this workspace Trash?'),
        LocalText('afilemanager_trash_empty','Empty Trash'),
        LocalText('afilemanager_cancel','Cancel'));
  end
  else if SameText(ACommand,'Resource.Delete') or SameText(ACommand,'File.Delete') then DeleteClick(ASender)
  else if SameText(ACommand,'Favorites.Add') then
  begin
    if AddFavorite(FListFavoriteTarget) then SetStatus('Added to favorites: '+FListFavoriteTarget)
    else SetStatus('Already in favorites: '+FListFavoriteTarget);
  end
  else if SameText(ACommand,'Favorites.Remove') then
  begin
    if RemoveFavorite(FListFavoriteTarget) then SetStatus('Removed from favorites: '+FListFavoriteTarget);
  end
  else if SameText(ACommand,'History.Undo') then UndoClick(ASender)
  else if SameText(ACommand,'History.Redo') then RedoClick(ASender)
  else if SameText(ACommand,'Resource.Properties') or SameText(ACommand,'Resource.Metadata') then PropertiesClick(ASender)
  else if SameText(ACommand,'Resource.EditPermissions') then EditPermissionsClick(ASender)
  else if SameText(ACommand,'View.ToggleHidden') then ToggleHiddenFilesClick(ASender)
  else if SameText(ACommand,'Archive.ExtractHere') then ArchiveExtractHere(ASender)
  else if SameText(ACommand,'Archive.ExtractTo') then ArchiveExtractTo(ASender)
  else if SameText(ACommand,'Archive.CompressHere') then ArchiveCompressHere(ASender)
  else if SameText(ACommand,'Archive.CompressTo') then ArchiveCompressTo(ASender)
  else if SameText(ACommand,'Resource.Edit') then
  begin
    I:=ViewList(FActiveView).SelectedIndex;
    if I>=0 then
    begin
      BeginInternalEdit(SelectedPath(FActiveView,I));
    end;
  end
  else
    Result:=False;   { not a context command }
end;

procedure TAFileManagerController.MetadataContextMenuOpening(
  ASender: TArosaControl);
begin
  { Metadata belongs to the resource selected in its pane.  Keep preview
    context behaviour untouched and only establish the pane association here. }
  if ASender=FRightMetadataView then
    SetActiveView(1)
  else
    SetActiveView(0);

  if FLeftList<>nil then FLeftList.DismissContextMenu;
  if FRightList<>nil then FRightList.DismissContextMenu;
  if (FMetadataView<>nil) and (ASender<>FMetadataView) then
    FMetadataView.DismissContextMenu;
  if (FRightMetadataView<>nil) and (ASender<>FRightMetadataView) then
    FRightMetadataView.DismissContextMenu;
end;

procedure TAFileManagerController.MetadataContextCommand(
  ASender: TArosaControl; const ACommand: string);
begin
  if ASender=FRightMetadataView then SetActiveView(1)
  else SetActiveView(0);

  if SameText(ACommand,'Resource.EditPermissions') then
    EditPermissionsClick(ASender)
  else
    Diagnostic('COMMAND unknown metadata context command id='+ACommand);
end;

function TAFileManagerController.MetadataContextCommandEnabled(
  ASender: TArosaControl; const ACommand: string): Boolean;
var
  ViewIndex, I: Integer;
  L: TArosaFilteredListView;
  P: string;
begin
  Result:=False;
  if not SameText(ACommand,'Resource.EditPermissions') then Exit;

  if ASender=FRightMetadataView then ViewIndex:=1
  else ViewIndex:=0;

  L:=ViewList(ViewIndex);
  if (L=nil) or (L.SelectedCount<>1) then Exit;
  I:=L.SelectedIndex;
  if I<0 then Exit;

  P:=SelectedPath(ViewIndex,I);
  Result:=(P<>'') and (not IsProviderLocation(P));
end;

procedure TAFileManagerController.ResourceContextCommand(ASender: TArosaControl;
  const ACommand: string);
begin
  if not TryResourceContextCommand(ASender,ACommand) then
    Diagnostic('COMMAND unknown context command id='+ACommand);
end;

{ 0.6.1.2: keys are bound by data - the descriptor [Shortcuts] section that
  the context menu already displays.  The list asks first; a key whose
  command is unknown here falls back to the list's built-in handling. }
function TAFileManagerController.ListShortcut(ASender: TArosaControl;
  const AKey: string): Boolean;
var S: TStringList; I: Integer; Cmd: string;
begin
  Result:=False;
  Cmd:='';
  if FShortcutBindings<>nil then
  begin
    for I:=0 to FShortcutBindings.Count-1 do
      if SameText(Trim(FShortcutBindings.Names[I]),AKey) then
      begin
        Cmd:=Trim(FShortcutBindings.ValueFromIndex[I]);
        Break;
      end;
  end
  else if FDescriptor<>nil then
  begin
    S:=FDescriptor.Section('Shortcuts');
    try
      for I:=0 to S.Count-1 do
        if SameText(Trim(S.Names[I]),AKey) then
        begin
          Cmd:=Trim(S.ValueFromIndex[I]);
          Break;
        end;
    finally
      S.Free;
    end;
  end;
  if (Cmd='') or (Cmd='-') then Exit;
  Diagnostic('COMMAND shortcut key='+AKey+' id='+Cmd);
  { Keyboard shortcuts must obey the same capability gate as the context
    menu.  In particular Delete on a read-only remote provider is consumed
    and reported locally instead of entering a mutation path that the provider
    cannot perform. }
  if not ResourceContextCommandEnabled(ASender,Cmd) then
  begin
    if ASender=FRightList then SetActiveView(1) else if ASender=FLeftList then SetActiveView(0);
    SetStatus('Command is not available for this location: '+Cmd);
    Exit(True);
  end;
  if TryResourceContextCommand(ASender,Cmd) then Exit(True);
  if ASender=FRightList then SetActiveView(1) else if ASender=FLeftList then SetActiveView(0);
  Result:=RunCommandId(Cmd);
end;

function TAFileManagerController.ResourceContextCommandEnabled(
  ASender: TArosaControl; const ACommand: string): Boolean;
var
  L: TArosaFilteredListView;
  ViewIndex: Integer;
  SelectedPathValue, CurrentLocation: string;
  Caps: TArosaResourceAccessCapabilities;
begin
  if ASender=FRightList then begin L:=FRightList; ViewIndex:=1; end
  else begin L:=FLeftList; ViewIndex:=0; end;
  { 0.10.6.2: the Move / Copy / Cancel menu of a drop that asks }
  if SameText(ACommand,'Drop.Move') or SameText(ACommand,'Drop.Copy') or
     SameText(ACommand,'Drop.Cancel') then Exit(True);
  CurrentLocation:=ViewCurrent(ViewIndex);
  if IsProviderLocation(CurrentLocation) and (FLocations<>nil) then
    Caps:=FLocations.Capabilities(CurrentLocation)
  else
    Caps:=[aracEnumerate,aracRead,aracWrite,aracCreateDirectory,aracDelete,
      aracRename,aracMove,aracMetadata,aracCapacity];

  SelectedPathValue:='';
  if (L<>nil) and (L.SelectedCount>0) and (L.SelectedIndex>=0) then
    SelectedPathValue:=SelectedPath(ViewIndex,L.SelectedIndex);

  if SameText(ACommand,'Workspace.CloseScreen') then
    Exit(FWorkspaceSessionMode);
  if SameText(ACommand,'Workspace.Create') then
    Exit(SameText(CurrentLocation,'arosa://workspaces'));
  if SameText(ACommand,'Workspace.Delete') then
    Exit(SameText(CurrentLocation,'arosa://workspaces') and
      (WorkspaceIdFromLocation(SelectedPathValue)<>'') and
      (FWorkspaces<>nil) and
      (FWorkspaces.Find(WorkspaceIdFromLocation(SelectedPathValue))<>nil));
  if SameText(ACommand,'Desktop.Add') then
    Exit((L<>nil) and (L.SelectedCount=1) and (SelectedPathValue<>''));
  if SameText(ACommand,'Desktop.Remove') then
    Exit((L<>nil) and (L.SelectedCount=1) and
      (DesktopShortcutIndex(SelectedPathValue)>=0));
  if SameText(ACommand,'StartMenu.Add') then
    Exit((L<>nil) and (L.SelectedCount=1) and (SelectedPathValue<>'') and
      (FStartMenuService<>nil));
  if SameText(ACommand,'StartMenu.Remove') then
    Exit((L<>nil) and (L.SelectedCount=1) and
      StartMenuContains(SelectedPathValue));
  if SameText(ACommand,'Trash.Empty') then
    Exit(SameText(SelectedPathValue,FTrashDirectory));
  if SameText(ACommand,'Selection.All') then Exit((L<>nil) and (L.ItemCount>0));
  if SameText(ACommand,'Selection.None') then Exit((L<>nil) and (L.SelectedCount>0));
  if SameText(ACommand,'Resource.Paste') or SameText(ACommand,'File.Paste') then
    Exit((FResourceClipboard<>nil) and FResourceClipboard.HasResources and
      (aracWrite in Caps));
  if SameText(ACommand,'Resource.CreateFolder') then
    Exit(aracCreateDirectory in Caps);
  if SameText(ACommand,'Resource.CreateFile') then
    Exit(aracWrite in Caps);
  if SameText(ACommand,'View.ToggleHidden') then Exit(True);
  if SameText(ACommand,'Archive.CompressHere') or SameText(ACommand,'Archive.CompressTo') then
    Exit((L<>nil) and (L.SelectedCount>0) and not IsProviderLocation(CurrentLocation));
  if SameText(ACommand,'Archive.ExtractHere') or SameText(ACommand,'Archive.ExtractTo') then
  begin
    if IsProviderLocation(SelectedPathValue) and (FLocations<>nil) then
      Caps:=FLocations.Capabilities(SelectedPathValue);
    Exit((L<>nil) and (L.SelectedCount=1) and IsArchivePath(SelectedPathValue) and
      ((not IsProviderLocation(SelectedPathValue)) or (aracRead in Caps)));
  end;

  if IsProviderLocation(SelectedPathValue) and (FLocations<>nil) then
    Caps:=FLocations.Capabilities(SelectedPathValue);
  if SameText(ACommand,'Resource.Open') or SameText(ACommand,'Resource.Preview') or
     SameText(ACommand,'Resource.Copy') or SameText(ACommand,'File.Copy') then
    Exit((L<>nil) and (L.SelectedCount>0) and (aracRead in Caps));
  if SameText(ACommand,'Resource.Edit') then
    Exit((L<>nil) and (L.SelectedCount>0) and (aracRead in Caps) and (aracWrite in Caps));
  if SameText(ACommand,'Resource.Rename') then
    Exit((L<>nil) and (L.SelectedCount=1) and (aracRename in Caps));
  if SameText(ACommand,'Resource.EditPermissions') then
    Exit((L<>nil) and (L.SelectedCount=1) and
      (not IsProviderLocation(SelectedPathValue)));
  if SameText(ACommand,'Resource.Cut') or SameText(ACommand,'File.Cut') then
    Exit((L<>nil) and (L.SelectedCount>0) and ((aracMove in Caps) or (aracDelete in Caps)));
  if SameText(ACommand,'Resource.MoveTo') then
    Exit((L<>nil) and (L.SelectedCount>0) and ((aracMove in Caps) or (aracDelete in Caps)));
  if SameText(ACommand,'Resource.Delete') or SameText(ACommand,'File.Delete') then
    Exit((L<>nil) and (L.SelectedCount>0) and (aracDelete in Caps));
  if SameText(ACommand,'History.Undo') then Exit(FResourceOperations.CanUndo);
  if SameText(ACommand,'History.Redo') then Exit(FResourceOperations.CanRedo);
  Result:=True;
end;


function TAFileManagerController.ResourceContextCommandShortcut(
  ASender: TArosaControl; const ACommand: string): string;
var S: TStringList; I: Integer;
begin
  Result:='';
  if FShortcutBindings<>nil then
  begin
    for I:=0 to FShortcutBindings.Count-1 do
      if SameText(Trim(FShortcutBindings.ValueFromIndex[I]),ACommand) then
        Exit(Trim(FShortcutBindings.Names[I]));
    Exit;
  end;
  if FDescriptor=nil then Exit;
  S:=FDescriptor.Section('Shortcuts');
  try
    for I:=0 to S.Count-1 do
      if SameText(Trim(S.ValueFromIndex[I]),ACommand) then
        Exit(Trim(S.Names[I]));
  finally S.Free; end;
end;

function TAFileManagerController.ResourceOperationError(const AOperation,
  ASource, ADestination, AMessage: string): TArosaOperationErrorDecision;
var Hint: string;
begin
  Hint:='';
  { A lock held by another program is the commonest cause; name it when the
    backend can tell (exclusive locks only - a shared lock is not visible). }
  if (FFiles<>nil) and (ASource<>'') and (not IsProviderLocation(ASource)) then
  begin
    Hint:=FFiles.ExplainReadFailure(ASource);
    if Pos('in use',Hint)=0 then Hint:='' else Hint:=' - '+Hint;
  end;
  if FCollectOperationErrors and (FOperationErrors<>nil) then
    FOperationErrors.Add(FPaths.SplitFileName(ASource)+': '+AMessage+Hint)
  else
    SetStatus(AOperation+': '+AMessage+' '+ASource+Hint);
  Diagnostic('RESOURCE-OPERATION error operation='+AOperation+' source='+ASource+
    ' destination='+ADestination+' message='+AMessage+Hint);
  Result:=aoedSkip;
end;

function TAFileManagerController.ResourceConflict(const ASource,
  ADestination: string; ASourceIsDirectory,
  ADestinationIsDirectory: Boolean): TArosaResourceConflictDecision;
begin
  { 0.5.110.58: conflicts are planned and decided BEFORE an operation runs
    (BeginResourceOperation).  Reaching this callback means a destination
    appeared after planning (e.g. created externally).  Nothing can block
    here, so the item is skipped - counted and reported, never silent. }
  Inc(FUnplannedConflicts);
  Diagnostic('RESOURCE-OPERATION unplanned conflict source='+ASource+
    ' destination='+ADestination+' decision=skip');
  Result:=arcdSkip;
end;

{ ---- 0.5.110.58 overwrite safety ------------------------------------------ }

procedure TAFileManagerController.ClearConflictPreviews;
begin
  FreeAndNil(FConflictExistingPreview);
  FreeAndNil(FConflictIncomingPreview);
end;

function TAFileManagerController.ConflictResourceDetail(const APath: string;
  out AInfo: TArosaFileInfo): string;
var
  SizePart, DatePart: string;
begin
  FillChar(AInfo,SizeOf(AInfo),0);
  Result:=LocalText('afilemanager_conflict_metadata_unavailable',
    'Size/date unavailable');

  { Metadata is resolved before the requester enters modal state.  This keeps
    provider I/O outside TArosaOperationRequester itself. }
  if FLocationResourceAccess<>nil then
  begin
    if not FLocationResourceAccess.GetInfo(APath,AInfo) then Exit;
  end
  else if not FPaths.GetInfo(APath,AInfo) then Exit;

  if AInfo.Kind=afekDirectory then
    SizePart:=LocalText('afilemanager_conflict_folder','Folder')
  else
    SizePart:=IntToStr(AInfo.Size)+' '+
      LocalText('afilemanager_conflict_bytes','bytes');

  if AInfo.ModifiedUtc>0 then
    DatePart:=FormatDateTime('yyyy-mm-dd hh:nn:ss',AInfo.ModifiedUtc)
  else
    DatePart:=LocalText('afilemanager_conflict_date_unknown','Date unknown');

  Result:=LocalText('afilemanager_conflict_size','Size')+': '+SizePart+#10+
    LocalText('afilemanager_conflict_modified','Modified')+': '+DatePart;
end;

function TAFileManagerController.LoadConflictPreview(const APath: string;
  const AInfo: TArosaFileInfo): TArosaImageResource;
var
  Physical, Err: string;
  C: TArosaContentDescriptor;
begin
  Result:=nil;
  if (FImageLoader=nil) or (AInfo.Kind=afekDirectory) then Exit;
  if not IsThumbnailPictureResource(AInfo) then Exit;

  Physical:=APath;
  if IsProviderLocation(APath) then
  begin
    { Never fetch remote image bytes merely to decorate a modal conflict
      requester. Reuse the bounded content cache only when another consumer
      has already materialized the original. }
    if (FContent=nil) or not FContent.IsOriginalCached(APath) then Exit;
    if not FContent.AcquireOriginal(APath,C,Err) then Exit;
    Physical:=C.PhysicalPath;
  end;

  if not FImageLoader.TryLoadFile(Physical,Result,Err) then
    Result:=nil;
end;

function TAFileManagerController.DescribeResource(const APath: string): string;
var Info: TArosaFileInfo;
begin
  Result:='';
  if FLocationResourceAccess<>nil then
  begin
    if not FLocationResourceAccess.GetInfo(APath,Info) then Exit;
  end
  else if not FPaths.GetInfo(APath,Info) then Exit;
  if Info.Kind=afekDirectory then Result:=LocalText('afilemanager_conflict_folder','folder')
  else Result:=IntToStr(Info.Size)+' '+LocalText('afilemanager_conflict_bytes','bytes');
  Result:=Result+', '+FormatDateTime('yyyy-mm-dd hh:nn',Info.ModifiedUtc);
end;

procedure TAFileManagerController.BeginResourceOperation(const AKind: string;
  AItems: TStrings; const ADestination: string; AOperation: TArosaTransferOperation;
  ATargetView: Integer);
var I, N: Integer;
begin
  if FPendingOpKind<>'' then
  begin
    SetStatus(LocalText('afilemanager_status_operation_pending',
      'Another operation is waiting for a decision.'));
    Exit;
  end;
  FPendingOpKind:=AKind;
  FPendingDest:=ADestination;
  FPendingTransferOp:=AOperation;
  FPendingTargetView:=ATargetView;
  FPendingItems.Clear;
  if SameText(AKind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'operation.begin kind='+AKind+
      ' destination='+ADestination+
      ' operation='+ArosaTransferOperationName(AOperation)+
      ' target-pane='+IntToStr(ATargetView+1));
  if SameText(AKind,'paste') then
  begin
    { Snapshot now: a completed cut clears the clipboard, but the source
      folders are still needed for the refresh. }
    for I:=0 to FResourceClipboard.Count-1 do FPendingItems.Add(FResourceClipboard.Resource(I));
    if FResourceClipboard.Mode=arcmCut then FPendingTransferOp:=atoMove
    else FPendingTransferOp:=atoCopy;
  end
  else if AItems<>nil then
    FPendingItems.AddStrings(AItems);

  FResourceOperations.ClearConflictDecisions;
  FConflictIndex:=0;
  FConflictSources.Clear;
  FConflictDests.Clear;
  SetLength(FConflictChoices,0);
  FreeAndNil(FConflictPlan);

  {$IFDEF AFM_EXTERNAL_TRANSFER}
  { Never plan provider conflicts in the input callback: planning calls
    Exists/GetInfo, which is a STAT on the remote server and can hold the
    whole desktop.  The transfer worker plans instead and reports what it
    found; FinishExternalProviderTransfer then asks the questions here.
    (Before 0.8.6.1 the worker skipped every existing destination without
    asking and reported the skip as a failure.) }
  if PendingOperationNeedsWorker then
  begin
    Diagnostic('RESOURCE-OPERATION plan kind='+AKind+' items='+
      IntToStr(FPendingItems.Count)+' destination='+ADestination+
      ' planner=transfer-worker');
    if SameText(AKind,'transfer') and
       DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'operation.plan planner=transfer-worker items='+
        IntToStr(FPendingItems.Count)+' destination='+ADestination);
    StartBackgroundResourceOperation(AFM_PHASE_PLAN);
    Exit;
  end;
  {$ENDIF}

  if SameText(AKind,'paste') then
    N:=FResourceOperations.PlanPasteConflicts(ADestination,FConflictSources,FConflictDests)
  else
    N:=FResourceOperations.PlanTransferConflicts(FPendingItems,ADestination,AOperation,
      FConflictSources,FConflictDests);
  SetLength(FConflictChoices,FConflictDests.Count);
  for I:=0 to High(FConflictChoices) do FConflictChoices[I]:=afccSkip;
  Diagnostic('RESOURCE-OPERATION plan kind='+AKind+' items='+IntToStr(FPendingItems.Count)+
    ' destination='+ADestination+' conflicts='+IntToStr(N));
  if SameText(AKind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'operation.plan planner=in-process items='+IntToStr(FPendingItems.Count)+
      ' destination='+ADestination+
      ' conflicts='+IntToStr(N)+
      ' requester='+BoolToStr(FOperationRequester<>nil,True));
  if (N=0) or (FOperationRequester=nil) then
    RunPendingResourceOperation
  else
    AskNextConflict;
end;

procedure TAFileManagerController.AskNextConflict;
var
  Src, Dst, Msg, ExistingDetail, IncomingDetail: string;
  ExistingInfo, IncomingInfo: TArosaFileInfo;
  ExistingImage, IncomingImage: TArosaPlatformHandle;
  ExistingSource, IncomingSource: TArosaRect;
begin
  Src:=FConflictSources[FConflictIndex];
  Dst:=FConflictDests[FConflictIndex];
  if SameText(FPendingOpKind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'overwrite.prompt index='+IntToStr(FConflictIndex)+
      ' count='+IntToStr(FConflictDests.Count)+
      ' source='+Src+' destination='+Dst);

  Msg:=SysUtils.Format(
    LocalText('afilemanager_conflict_message','"%s" already exists in %s.'),
    [FPaths.SplitFileName(Dst),FPendingDest]);
  if FConflictDests.Count>1 then
    Msg:=Msg+' ('+IntToStr(FConflictIndex+1)+'/'+
      IntToStr(FConflictDests.Count)+')';

  { Resolve only the current pair before entering modal state. Do not issue
    provider calls from the requester's paint/input path.  When the transfer
    worker planned the conflicts it already read both sides; use what it saw
    so this process never talks to the remote server. }
  if (FConflictPlan<>nil) and (FConflictIndex<FConflictPlan.ConflictCount) then
  begin
    ExistingDetail:=ConflictSideDetail(
      FConflictPlan.Conflicts[FConflictIndex].Existing,Dst,ExistingInfo);
    IncomingDetail:=ConflictSideDetail(
      FConflictPlan.Conflicts[FConflictIndex].Incoming,Src,IncomingInfo);
  end
  else
  begin
    ExistingDetail:=ConflictResourceDetail(Dst,ExistingInfo);
    IncomingDetail:=ConflictResourceDetail(Src,IncomingInfo);
  end;

  ClearConflictPreviews;
  FConflictExistingPreview:=LoadConflictPreview(Dst,ExistingInfo);
  FConflictIncomingPreview:=LoadConflictPreview(Src,IncomingInfo);

  ExistingImage:=ArosaNilHandle;
  IncomingImage:=ArosaNilHandle;
  ExistingSource:=ArosaRectRaw(0,0,0,0);
  IncomingSource:=ArosaRectRaw(0,0,0,0);

  if (FConflictExistingPreview<>nil) and
     (FConflictExistingPreview.Bitmap<>ArosaNilHandle) then
  begin
    ExistingImage:=FConflictExistingPreview.Bitmap;
    ExistingSource:=ArosaRectXYWH(0,0,
      FConflictExistingPreview.Width,FConflictExistingPreview.Height);
  end;

  if (FConflictIncomingPreview<>nil) and
     (FConflictIncomingPreview.Bitmap<>ArosaNilHandle) then
  begin
    IncomingImage:=FConflictIncomingPreview.Bitmap;
    IncomingSource:=ArosaRectXYWH(0,0,
      FConflictIncomingPreview.Width,FConflictIncomingPreview.Height);
  end;

  FOperationRequester.ShowComparisonRequest(
    LocalText('afilemanager_conflict_title','Replace existing item?'),
    Msg,
    LocalText('afilemanager_conflict_existing','Existing')+': '+
      FPaths.SplitFileName(Dst),
    ExistingDetail,
    LocalText('afilemanager_conflict_incoming','Incoming')+': '+
      FPaths.SplitFileName(Src),
    IncomingDetail,
    ExistingImage,ExistingSource,
    IncomingImage,IncomingSource,
    [aocReplace,aocSkip,aocCancel]);

  SetStatus(LocalText('afilemanager_status_conflict_hint',
    'Choose Replace or Skip; tick "apply to all" for the remaining conflicts.'));
end;

procedure TAFileManagerController.ResourceConflictDecided(ASender: TArosaControl;
  AChoice: TArosaOperationChoice; AApplyToAll: Boolean);
var I, Last: Integer; D: TArosaResourceConflictDecision;
begin
  if FPendingOpKind='' then Exit;
  ClearConflictPreviews;
  if AChoice=aocCancel then
  begin
    if SameText(FPendingOpKind,'transfer') and
       DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'overwrite.decision choice=cancel index='+IntToStr(FConflictIndex));
    { Nothing has run yet: cancelling leaves every resource untouched. }
    ResetPendingResourceOperation;
    SetStatus(LocalText('afilemanager_status_operation_cancelled',
      'Operation cancelled - nothing was changed.'));
    Exit;
  end;
  if AChoice=aocReplace then D:=arcdReplace else D:=arcdSkip;
  if SameText(FPendingOpKind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
  begin
    if D=arcdReplace then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'overwrite.decision choice=replace apply-all='+
        BoolToStr(AApplyToAll,True)+' index='+IntToStr(FConflictIndex))
    else
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'overwrite.decision choice=skip apply-all='+
        BoolToStr(AApplyToAll,True)+' index='+IntToStr(FConflictIndex));
  end;
  if AApplyToAll then Last:=FConflictDests.Count-1 else Last:=FConflictIndex;
  if Length(FConflictChoices)<FConflictDests.Count then
    SetLength(FConflictChoices,FConflictDests.Count);
  for I:=FConflictIndex to Last do
  begin
    FResourceOperations.PresetConflictDecision(FConflictDests[I],D);
    if D=arcdReplace then FConflictChoices[I]:=afccReplace
    else FConflictChoices[I]:=afccSkip;
  end;
  FConflictIndex:=Last+1;
  if FConflictIndex<FConflictDests.Count then AskNextConflict
  else RunPendingResourceOperation;
end;

procedure TAFileManagerController.BeginOperationErrors;
begin
  FOperationErrors.Clear;
  FCollectOperationErrors:=True;
end;

{ ' - N failed: a: reason; b: reason; and K more', or '' }
function TAFileManagerController.EndOperationErrors: string;
var I: Integer;
begin
  FCollectOperationErrors:=False;
  Result:='';
  if FOperationErrors.Count=0 then Exit;
  Result:=' - '+IntToStr(FOperationErrors.Count)+' '+
    LocalText('afilemanager_status_failed','failed')+': ';
  for I:=0 to FOperationErrors.Count-1 do
  begin
    if I=3 then
    begin
      Result:=Result+'; '+SysUtils.Format(LocalText('afilemanager_status_and_more','and %d more'),
        [FOperationErrors.Count-3]);
      Break;
    end;
    if I>0 then Result:=Result+'; ';
    Result:=Result+FOperationErrors[I];
  end;
end;

{ Why a create/rename failed, checked in the order a user would. }
function TAFileManagerController.NameOperationFailure(const AKind, ASource,
  ATarget: string): string;
var Parent, Name: string;
begin
  if FLocationResourceAccess<>nil then
  begin
    Name:=FLocationResourceAccess.LeafName(ATarget);
    Parent:=FLocationResourceAccess.Parent(ATarget);
  end
  else
  begin
    Name:=FPaths.SplitFileName(ATarget);
    Parent:=Copy(ATarget,1,Length(ATarget)-Length(Name));
  end;
  if Trim(Name)='' then Exit(LocalText('afilemanager_fail_no_name','no name was given'));
  if SameText(AKind,'rename') and
     (((FLocationResourceAccess<>nil) and not FLocationResourceAccess.Exists(ASource)) or
      ((FLocationResourceAccess=nil) and not FPaths.Exists(ASource))) then
    Exit(LocalText('afilemanager_fail_source_gone','the item no longer exists'));
  if SameText(AKind,'rename') and SameText(ASource,ATarget) then
    Exit(LocalText('afilemanager_fail_same_name','the name is unchanged'));
  if ((FLocationResourceAccess<>nil) and FLocationResourceAccess.Exists(ATarget)) or
     ((FLocationResourceAccess=nil) and FPaths.Exists(ATarget)) then
    Exit(LocalText('afilemanager_fail_exists','an item with that name already exists'));
  if (Parent<>'') and
     (((FLocationResourceAccess<>nil) and not FLocationResourceAccess.Exists(Parent)) or
      ((FLocationResourceAccess=nil) and not FPaths.Exists(Parent))) then
    Exit(LocalText('afilemanager_fail_no_parent','the folder does not exist')+': '+Parent);
  if (Pos(':',Name)>0) or (Pos('/',Name)>0) then
    Exit(LocalText('afilemanager_fail_bad_char','names cannot contain ":" or "/"'));
  if SameText(AKind,'rename') then
  begin
    Result:=FFiles.ExplainReadFailure(ASource);
    if Pos('in use',Result)>0 then Exit;
  end;
  Result:=LocalText('afilemanager_fail_refused',
    'the filesystem refused it (volume write-protected, full, or name not allowed)');
end;

{ Cheap before/after fingerprint of a folder's direct entries. }
function TAFileManagerController.DirectorySignature(const APath: string): string;
var E: TArosaFileInfoArray; I: Integer;
begin
  Result:='';
  if not FPaths.Enumerate(APath,E) then Exit('?');
  for I:=0 to High(E) do
    Result:=Result+E[I].Name+'|'+IntToStr(E[I].Size)+'|'+
      FloatToStr(E[I].ModifiedUtc)+#10;
end;

procedure TAFileManagerController.PublishLocationChanged(
  const ALocation: string; AKind: TArosaLocationMutationKind);
var N: string;
begin
  if Trim(ALocation)='' then Exit;
  if FLocations<>nil then
  begin
    N:=FLocations.Normalize(ALocation);
    FLocations.Invalidate(N,False);
  end
  else
    N:=ALocation;
  if FLocationChanges<>nil then FLocationChanges.Publish(N,AKind)
  else LocationChanged(Self,N,AKind);
end;

procedure TAFileManagerController.LocationChanged(ASender: TObject;
  const ALocation: string; AKind: TArosaLocationMutationKind);
var
  V: Integer;
  N, Cur: string;
begin
  if Trim(ALocation)='' then Exit;
  if FLocations<>nil then N:=FLocations.Normalize(ALocation) else N:=ALocation;

  for V:=0 to 1 do
  begin
    if (V=1) and (FRightList=nil) then Continue;
    Cur:=ViewCurrent(V);
    if FLocations<>nil then Cur:=FLocations.Normalize(Cur);
    if SameText(Cur,N) then RefreshView(V);
  end;

  if ASender=nil then ;
  if AKind=almkUnknown then ;
end;

procedure TAFileManagerController.RefreshAffectedViews(ASources: TStrings;
  const ADestination: string);
var
  I: Integer;
  P: string;
begin
  { Mutation publication replaces controller-specific pane guesses. Every
    subscribed view displaying an affected location is refreshed. }
  if Trim(ADestination)<>'' then
    PublishLocationChanged(ADestination,almkCopy);

  if ASources<>nil then
    for I:=0 to ASources.Count-1 do
    begin
      if FLocations<>nil then P:=FLocations.Parent(ASources[I])
      else P:=ParentPath(ASources[I]);
      if P<>'' then PublishLocationChanged(P,almkMove);
    end;
end;

function TAFileManagerController.PendingOperationNeedsWorker: Boolean;
var I: Integer;
begin
  { Any provider-backed operation can block on STAT/LIST/AGet/APut. Never ask
    IsDirectory here: that probe itself can block the Intuition task. }
  Result:=IsProviderLocation(FPendingDest);
  if Result then Exit;
  for I:=0 to FPendingItems.Count-1 do
    if IsProviderLocation(FPendingItems[I]) then Exit(True);
end;

function TAFileManagerController.SpawnWorker(AJob: TArosaWorkerJob): Boolean;
{$IFDEF AROS}
var
  Telemetry: TArosaArosProcessorTelemetryProvider;
  Placement: TArosaArosExecutionPlacementProvider;
  Snapshot: TArosaProcessorSnapshot;
  Request: TArosaExecutionPlacementRequest;
  Decision: TArosaExecutionPlacementDecision;
  CPUCount: Integer;
  TargetCPU: LongInt;
{$ENDIF}
begin
  Result:=False;
  if FTaskRunner=nil then Exit;
  {$IFDEF AROS}
  CPUCount:=1; TargetCPU:=-1;
  Telemetry:=TArosaArosProcessorTelemetryProvider.Create;
  try
    if Telemetry.Capture(Snapshot) and (Snapshot.LogicalProcessors>0) then
      CPUCount:=Snapshot.LogicalProcessors;
  finally
    Telemetry.Free;
  end;
  Placement:=TArosaArosExecutionPlacementProvider.Create;
  try
    Placement.UpdateTopology(CPUCount);
    Request:=ArosaDefaultPlacementRequest(aecIO);
    Request.Locality:=aelWorker;
    Request.PreferParallel:=True;
    Request.PreferSeparateCPU:=True;
    if Placement.Resolve(Request,Decision) then TargetCPU:=Decision.PreferredCPU;
  finally
    Placement.Free;
  end;
  Result:=FTaskRunner.Spawn(@AFMWorkerEntry,Pointer(AJob),512,TargetCPU);
  {$ELSE}
  Result:=FTaskRunner.Spawn(@AFMWorkerEntry,Pointer(AJob),512);
  {$ENDIF}
end;

function TAFileManagerController.ConflictSideDetail(
  const ASide: TAFMConflictSide; const APath: string;
  out AInfo: TArosaFileInfo): string;
var SizePart, DatePart: string;
begin
  FillChar(AInfo,SizeOf(AInfo),0);
  AInfo.Name:=FPaths.SplitFileName(APath);
  AInfo.FullPath:=APath;
  if not ASide.Known then
    Exit(LocalText('afilemanager_conflict_metadata_unavailable',
      'Size/date unavailable'));
  if ASide.IsDirectory then
  begin
    AInfo.Kind:=afekDirectory;
    SizePart:=LocalText('afilemanager_conflict_folder','Folder');
  end
  else
  begin
    AInfo.Kind:=afekFile;
    AInfo.Size:=ASide.Size;
    SizePart:=IntToStr(ASide.Size)+' '+
      LocalText('afilemanager_conflict_bytes','bytes');
  end;
  if ASide.Modified<>'' then DatePart:=ASide.Modified
  else DatePart:=LocalText('afilemanager_conflict_date_unknown','Date unknown');
  Result:=LocalText('afilemanager_conflict_size','Size')+': '+SizePart+#10+
    LocalText('afilemanager_conflict_modified','Modified')+': '+DatePart;
end;

procedure TAFileManagerController.ResetPendingResourceOperation;
begin
  FResourceOperations.ClearConflictDecisions;
  FPendingOpKind:='';
  FPendingDest:='';
  FPendingItems.Clear;
  FConflictSources.Clear;
  FConflictDests.Clear;
  SetLength(FConflictChoices,0);
  FreeAndNil(FConflictPlan);
  FConflictIndex:=0;
end;

procedure TAFileManagerController.ReleaseExternalTransferFiles;
begin
  if FExternalTransferJobPath<>'' then
  begin
    SysUtils.DeleteFile(FExternalTransferJobPath);
    SysUtils.DeleteFile(FExternalTransferJobPath+'.tmp');
  end;
  if FExternalTransferResultPath<>'' then
  begin
    SysUtils.DeleteFile(FExternalTransferResultPath);
    SysUtils.DeleteFile(FExternalTransferResultPath+'.tmp');
  end;
  if FExternalTransferProgressPath<>'' then
  begin
    SysUtils.DeleteFile(FExternalTransferProgressPath);
    SysUtils.DeleteFile(FExternalTransferProgressPath+'.tmp');
    SysUtils.DeleteFile(FExternalTransferProgressPath+'.bytes');
    SysUtils.DeleteFile(FExternalTransferProgressPath+'.bytes.tmp');
  end;
  if FExternalTransferCancelPath<>'' then
    SysUtils.DeleteFile(FExternalTransferCancelPath);
  if FExternalTransferPausePath<>'' then
    SysUtils.DeleteFile(FExternalTransferPausePath);
  FExternalTransferJobPath:='';
  FExternalTransferResultPath:='';
  FExternalTransferProgressPath:='';
  FExternalTransferCancelPath:='';
  FExternalTransferPausePath:='';
  FExternalTransferPausePath:='';
  FExternalTransferStartedTick:=0;
  FExternalTransferDisplayedCompleted:=0;
  FExternalTransferActive:=False;
  FExternalTransferCancelAsked:=False;
  FExternalTransferPaused:=False;
  FExternalTransferPaused:=False;
end;

function TAFileManagerController.StartExternalProviderTransfer(
  const APhase: string): Boolean;
var Request: TAFMTransferRequest; I: Integer; Stamp, WorkerArgs, Arg: string;
    TraceATransfer: Boolean;
begin
  Result:=False;
  if (FShellService=nil) or (FPendingItems.Count=0) then Exit;

  { One stamp per phase: the plan worker and the run worker never share a
    file, so a late write from the first cannot be read as the second. }
  Stamp:=IntToStr(GetTickCount64)+'-'+IntToHex(PtrUInt(Self),8)+'-'+APhase;
  FExternalTransferJobPath:=AFMTransferFile(Stamp,'job');
  FExternalTransferResultPath:=AFMTransferFile(Stamp,'result');
  FExternalTransferProgressPath:=AFMTransferFile(Stamp,'progress');
  FExternalTransferCancelPath:=AFMTransferFile(Stamp,'cancel');
  FExternalTransferPausePath:=AFMTransferFile(Stamp,'pause');
  SysUtils.DeleteFile(FExternalTransferResultPath);
  SysUtils.DeleteFile(FExternalTransferProgressPath);
  SysUtils.DeleteFile(FExternalTransferProgressPath+'.bytes');
  SysUtils.DeleteFile(FExternalTransferProgressPath+'.bytes.tmp');
  SysUtils.DeleteFile(FExternalTransferCancelPath);
  SysUtils.DeleteFile(FExternalTransferPausePath);

  Request:=TAFMTransferRequest.Create;
  try
    Request.Phase:=APhase;
    Request.Move:=FPendingTransferOp=atoMove;
    Request.Destination:=FPendingDest;
    Request.ResultPath:=FExternalTransferResultPath;
    Request.ProgressPath:=FExternalTransferProgressPath;
    Request.CancelPath:=FExternalTransferCancelPath;
    Request.PausePath:=FExternalTransferPausePath;
    Request.Items.AddStrings(FPendingItems);
    if APhase=AFM_PHASE_RUN then
      for I:=0 to FConflictDests.Count-1 do
        if (I<Length(FConflictChoices)) and (FConflictChoices[I]=afccReplace) then
          Request.AddDecision(FConflictDests[I],afccReplace)
        else
          Request.AddDecision(FConflictDests[I],afccSkip);
    try
      Request.SaveToFile(FExternalTransferJobPath);
    except
      on E: Exception do
      begin
        Diagnostic('RESOURCE-OPERATION external job not written path='+
          FExternalTransferJobPath+' error='+E.Message);
        ReleaseExternalTransferFiles;
        Exit;
      end;
    end;
  finally
    Request.Free;
  end;

  { The installed AFileManager executable is its own worker: a new AmigaDOS
    process enters worker mode before any UI exists (see the main block). }
  WorkerArgs:='--transfer-worker'+#10+FExternalTransferJobPath;
  { The worker is a new process and therefore has its own diagnostics session.
    Forward only the ATransfer selector when the parent was explicitly launched
    with it, so --trace=arosa.application.afilemanager.atransfer covers the
    complete operation without turning on unrelated worker trace. }
  TraceATransfer:=False;
  for I:=1 to ParamCount do
  begin
    Arg:=LowerCase(Trim(ParamStr(I)));
    if (Arg='--trace='+LowerCase(AFM_ATRANSFER_TRACE_COMPONENT)) or
       ((Pos('--trace=',Arg)=1) and
        (Pos(LowerCase(AFM_ATRANSFER_TRACE_COMPONENT),Arg)>0)) then
    begin
      TraceATransfer:=True;
      Break;
    end;
  end;
  if TraceATransfer then
    WorkerArgs:=WorkerArgs+#10+'--trace='+AFM_ATRANSFER_TRACE_COMPONENT;
  if not FShellService.LaunchIndependentArgs('AFILEMANAGER:AFileManager',WorkerArgs) then
  begin
    ReleaseExternalTransferFiles;
    Exit;
  end;

  FExternalTransferPhase:=APhase;
  FExternalTransferActive:=True;
  FExternalTransferStartedTick:=GetTickCount64;
  FExternalTransferChangeTick:=FExternalTransferStartedTick;
  FExternalTransferPollTick:=0;
  FExternalTransferSawWorker:=False;
  FExternalTransferSerial:=0;
  FExternalTransferByteSerial:=0;
  FExternalTransferDisplayedCompleted:=0;
  FExternalTransferCancelAsked:=False;
  FExternalTransferPaused:=False;
  Result:=True;
end;

{ True when AReport holds the worker's answer, or the reason there will
  never be one. }
function TAFileManagerController.PollExternalProviderTransfer(
  AReport: TAFMTransferReport): Boolean;
const
  PollIntervalMs  = 250;
  { No sign of life at all: the process did not start. }
  StartTimeoutMs  = 30000;
  { Alive but silent.  One AGet/APut may legitimately block for its own
    bounded network timeout; several in a row without one finishing may not. }
  SilentTimeoutMs = 300000;
var
  P: TAFMTransferProgress;
  B: TAFMTransferByteProgress;
  T: QWord;
  Percent: Integer;
begin
  Result:=False;
  if not FExternalTransferActive then Exit;
  T:=GetTickCount64;
  { The idle handler runs far more often than the files change. }
  if (FExternalTransferPollTick<>0) and
     (T-FExternalTransferPollTick<PollIntervalMs) then Exit;
  FExternalTransferPollTick:=T;

  if AReport.LoadFromFile(FExternalTransferResultPath) and
     (AReport.Finished or (AReport.State=AFM_STATE_PLAN)) then
    Exit(True);

  P:=AFMReadProgress(FExternalTransferProgressPath);
  if P.Valid then
  begin
    FExternalTransferSawWorker:=True;
    if P.Serial<>FExternalTransferSerial then
    begin
      FExternalTransferSerial:=P.Serial;
      FExternalTransferChangeTick:=T;
      if FExternalTransferCancelAsked then
        { keep the "cancelling" message }
      else if P.State=AFM_PROGRESS_PLANNING then
      begin
        SetStatus(LocalText('afilemanager_status_transfer_checking',
          'Checking the destination for existing items...'));
        if FTransferProgressDialog<>nil then
          FTransferProgressDialog.UpdateProgress(
            LocalText('afilemanager_status_transfer_checking',
              'Checking the destination for existing items...'),
            P.Current,P.Completed,P.Total);
      end
      else if P.State=AFM_PROGRESS_PAUSED then
      begin
        SetStatus(LocalText('afilemanager_status_transfer_paused',
          'Transfer paused'));
        if FTransferProgressDialog<>nil then
        begin
          FTransferProgressDialog.SetPaused(True);
          FTransferProgressDialog.UpdateProgress(
            LocalText('afilemanager_status_transfer_paused','Transfer paused'),
            P.Current,P.Completed,P.Total);
        end;
      end
      else if P.State=AFM_PROGRESS_RUNNING then
      begin
        if P.Total>0 then
          SetStatus(SysUtils.Format(LocalText('afilemanager_status_transfer_progress_exact',
            'Transferring: %d/%d item(s) done - %s'),
            [P.Completed,P.Total,P.Current]))
        else if P.Units>0 then
          SetStatus(SysUtils.Format(LocalText('afilemanager_status_transfer_progress',
            'Transferring: %d item(s) done - %s'),[P.Units,P.Current]));
        if FTransferProgressDialog<>nil then
        begin
          FTransferProgressDialog.SetPaused(False);
          FTransferProgressDialog.UpdateProgress(
            LocalText('afilemanager_status_transfer_running','Transferring...'),
            P.Current,P.Completed,P.Total);
        end;
        { Do not wait for the worker's final report before showing completed
          files. Each exact top-level completion invalidates the destination
          enumeration cache and refreshes any pane currently displaying it. }
        if P.Completed>FExternalTransferDisplayedCompleted then
        begin
          FExternalTransferDisplayedCompleted:=P.Completed;
          PublishLocationChanged(FPendingDest,almkCopy);
        end;
      end;
    end;
  end;

  { AGet/APut update this file from inside the helper process while the worker
    is synchronously waiting for RunCommandTimeout.  Reading it here gives the
    UI real byte progress instead of an item bar that appears frozen for the
    duration of a large file. }
  B:=AFMReadByteProgress(FExternalTransferProgressPath+'.bytes');
  if B.Valid and (B.Serial<>FExternalTransferByteSerial) then
  begin
    FExternalTransferByteSerial:=B.Serial;
    FExternalTransferSawWorker:=True;
    FExternalTransferChangeTick:=T;
    if (not FExternalTransferCancelAsked) and
       (B.Total>0) and (not FExternalTransferPaused) then
    begin
      Percent:=Trunc((B.Bytes/B.Total)*100);
      if Percent<0 then Percent:=0 else if Percent>100 then Percent:=100;
      SetStatus(SysUtils.Format(LocalText('afilemanager_status_transfer_byte_progress',
        'Transferring: %d%% - %s'),[Percent,B.Target]));
      if FTransferProgressDialog<>nil then
      begin
        FTransferProgressDialog.SetPaused(False);
        FTransferProgressDialog.UpdateByteProgress(
          LocalText('afilemanager_status_transfer_running','Transferring...'),
          B.Target,B.Bytes,B.Total);
      end;
    end;
  end;

  if (not FExternalTransferSawWorker) and
     (T-FExternalTransferStartedTick>=StartTimeoutMs) then
  begin
    AReport.Clear;
    AReport.State:=AFM_STATE_ERROR;
    AReport.Message:=LocalText('afilemanager_transfer_not_started',
      'the transfer process did not start (AFILEMANAGER:AFileManager must be the installed program)');
    Exit(True);
  end;
  if FExternalTransferSawWorker and
     (T-FExternalTransferChangeTick>=SilentTimeoutMs) then
  begin
    AReport.Clear;
    AReport.State:=AFM_STATE_ERROR;
    AReport.Message:=LocalText('afilemanager_transfer_silent',
      'the transfer process stopped reporting for 5 minutes');
    Exit(True);
  end;
end;

procedure TAFileManagerController.FinishExternalProviderTransfer(
  AReport: TAFMTransferReport);
var Msg, Verb: string; I: Integer; WasPaste, Changed: Boolean;
begin
  if FTransferCancelButton<>nil then
  begin
    FTransferCancelButton.Visible:=False;
    FTransferCancelButton.Enabled:=True;
  end;
  if FTransferProgressDialog<>nil then
    FTransferProgressDialog.Dismiss;
  Diagnostic('RESOURCE-OPERATION external '+FExternalTransferPhase+
    ' result state='+AReport.State+
    ' completed='+IntToStr(AReport.Completed)+
    ' skipped='+IntToStr(AReport.Skipped)+
    ' failed='+IntToStr(AReport.Failed)+
    ' conflicts='+IntToStr(AReport.ConflictCount)+
    ' message='+AReport.Message);
  for I:=1 to AReport.Errors.Count-1 do
    Diagnostic('RESOURCE-OPERATION external error '+AReport.Errors[I]);
  ReleaseExternalTransferFiles;

  { ---- the plan came back: ask, then run ---- }
  if AReport.State=AFM_STATE_PLAN then
  begin
    if SameText(FPendingOpKind,'transfer') and
       DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'operation.plan-result planner=transfer-worker conflicts='+
        IntToStr(AReport.ConflictCount)+
        ' state='+AReport.State+
        ' message='+AReport.Message);
    FConflictSources.Clear;
    FConflictDests.Clear;
    for I:=0 to AReport.ConflictCount-1 do
    begin
      FConflictSources.Add(AReport.Conflicts[I].Source);
      FConflictDests.Add(AReport.Conflicts[I].Destination);
    end;
    SetLength(FConflictChoices,FConflictDests.Count);
    for I:=0 to High(FConflictChoices) do FConflictChoices[I]:=afccSkip;
    FConflictIndex:=0;
    FreeAndNil(FConflictPlan);
    FConflictPlan:=TAFMTransferReport.Create;
    FConflictPlan.State:=AReport.State;
    for I:=0 to AReport.ConflictCount-1 do
      FConflictPlan.AddConflict(AReport.Conflicts[I]);
    if FClosingApplication then
    begin
      ResetPendingResourceOperation;
      RequestApplicationClose;
      Exit;
    end;
    if (FConflictDests.Count=0) or (FOperationRequester=nil) then
      { nobody to ask: existing items stay as they are }
      RunPendingResourceOperation
    else
      AskNextConflict;
    Exit;
  end;

  { ---- the transfer is over ---- }
  WasPaste:=SameText(FPendingOpKind,'paste');
  if (FPendingTransferOp=atoMove) and not AReport.MovedAsCopy then
    Verb:=LocalText('afilemanager_status_moved','Moved')
  else
    Verb:=LocalText('afilemanager_status_copied','Copied');
  Changed:=AReport.Completed>0;

  if AReport.State=AFM_STATE_ERROR then
  begin
    Msg:=LocalText('afilemanager_status_transfer_failed','Transfer failed')+': '+
      AReport.Message;
    { a worker that died half-way may still have written something }
    Changed:=True;
  end
  else
  begin
    if AReport.State=AFM_STATE_CANCELLED then
      Msg:=LocalText('afilemanager_status_transfer_cancelled','Transfer cancelled')+' - '
    else
      Msg:='';
    Msg:=Msg+Verb+': '+IntToStr(AReport.Completed)+' '+
      LocalText('afilemanager_status_items','item(s)');
    if AReport.Skipped>0 then
      Msg:=Msg+', '+IntToStr(AReport.Skipped)+' '+
        LocalText('afilemanager_status_skipped','left as they were');
    if AReport.Failed>0 then
      Msg:=Msg+', '+IntToStr(AReport.Failed)+' '+
        LocalText('afilemanager_status_failed','failed');
    if AReport.Errors.Count>0 then
    begin
      Msg:=Msg+' - '+AReport.Errors[0];
      if AReport.Errors.Count>1 then
        Msg:=Msg+' ('+SysUtils.Format(LocalText('afilemanager_status_and_more',
          'and %d more'),[AReport.Errors.Count-1])+')';
    end;
    if AReport.MovedAsCopy and (FPendingTransferOp=atoMove) then
      Msg:=Msg+' - '+LocalText('afilemanager_status_moved_as_copy',
        'the originals stay: this remote location cannot remove items');
  end;
  SetStatus(Msg);
  if SameText(FPendingOpKind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'operation.result state='+AReport.State+
      ' completed='+IntToStr(AReport.Completed)+
      ' skipped='+IntToStr(AReport.Skipped)+
      ' failed='+IntToStr(AReport.Failed)+
      ' conflicts='+IntToStr(AReport.ConflictCount)+
      ' moved-as-copy='+BoolToStr(AReport.MovedAsCopy,True));

  { A completed cut is spent, exactly as after a local paste - but only
    when the clipboard still holds what this transfer started with.  If the
    user copied something else meanwhile, that is kept. }
  if WasPaste and (FPendingTransferOp=atoMove) and (not AReport.MovedAsCopy) and
     (AReport.State=AFM_STATE_OK) and (FResourceClipboard<>nil) and
     (FResourceClipboard.Mode=arcmCut) and
     (FResourceClipboard.Count=FPendingItems.Count) then
  begin
    I:=0;
    while (I<FPendingItems.Count) and
      SameText(FResourceClipboard.Resource(I),FPendingItems[I]) do Inc(I);
    if I=FPendingItems.Count then FResourceClipboard.Clear;
  end;

  if Changed then RefreshAffectedViews(FPendingItems,FPendingDest);
  if FPendingTargetView>=0 then SetActiveView(FPendingTargetView);
  ResetPendingResourceOperation;
  if FClosingApplication then RequestApplicationClose;
end;

procedure TAFileManagerController.StartBackgroundResourceOperation(
  const APhase: string);
begin
  {$IFDEF AFM_EXTERNAL_TRANSFER}
  if FExternalTransferActive or (FTransferJob<>nil) then
  begin
    SetStatus(LocalText('afilemanager_status_transfer_busy',
      'A background transfer is already running.'));
    Exit;
  end;
  if not StartExternalProviderTransfer(APhase) then
  begin
    { Nothing is running, so nothing may stay "pending": the next paste must
      be accepted, not refused as "another operation is waiting". }
    ResetPendingResourceOperation;
    SetStatus(LocalText('afilemanager_status_transfer_no_process',
      'Could not start the transfer process (AFILEMANAGER:AFileManager).'));
    Exit;
  end;
  if FTransferCancelButton<>nil then
  begin
    { Cancel is cooperative: the worker stops at the next file boundary.
      No process is ever terminated from here. }
    FTransferCancelButton.Visible:=True;
    FTransferCancelButton.Enabled:=True;
  end;
  if FTransferProgressDialog<>nil then
  begin
    FTransferProgressDialog.ShowProgress(
      LocalText('afilemanager_transfer_title','File transfer'),
      LocalText('afilemanager_status_transfer_started',
        'Transfer started in the background'),True,True);
  end;
  if APhase=AFM_PHASE_PLAN then
    SetStatus(LocalText('afilemanager_status_transfer_checking',
      'Checking the destination for existing items...'))
  else
    SetStatus(LocalText('afilemanager_status_transfer_started',
      'Transfer started in the background'));
  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) and (not FTransferIdleAttached) then
  begin
    FNativeHost.Application.Loop.AddIdleHandler(@TransferIdle);
    FTransferIdleAttached:=True;
  end;
  Diagnostic('RESOURCE-OPERATION external start phase='+APhase+
    ' destination='+FPendingDest+' items='+IntToStr(FPendingItems.Count)+
    ' decisions='+IntToStr(FConflictDests.Count));
  Exit;
  {$ENDIF}

  { Non-AROS fallback retains the cooperative job implementation. }
  if (FTransferJob<>nil) or (FWorkerService=nil) then
  begin
    SetStatus('A background transfer is already running.');
    Exit;
  end;
  FTransferJob:=TAFMTransferJob.CreateTransfer(FResourceOperations,FPendingItems,
    FPendingDest,FPendingTransferOp);
  FTransferLastProgress:=-1;
  FResourceOperations.OnError:=@FTransferJob.TransferError;
  FResourceOperations.OnConflict:=nil;
  FResourceOperations.OnTransferContinue:=nil;
  FResourceOperations.OnTransferProgress:=nil;
  if FTransferCancelButton<>nil then FTransferCancelButton.Visible:=True;
  SetStatus('Background transfer started: 0 resource(s) processed');
  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) and (not FTransferIdleAttached) then
  begin
    FNativeHost.Application.Loop.AddIdleHandler(@TransferIdle);
    FTransferIdleAttached:=True;
  end;
  if APhase='' then ;
end;

procedure TAFileManagerController.PauseTransferClick(ASender: TArosaControl);
var Marker: TStringList;
begin
  if not FExternalTransferActive or FExternalTransferCancelAsked or
     FExternalTransferPaused then Exit;
  Marker:=TStringList.Create;
  try
    Marker.Add('pause');
    try
      Marker.SaveToFile(FExternalTransferPausePath);
      FExternalTransferPaused:=True;
    except
      on E: Exception do
        Diagnostic('RESOURCE-OPERATION external pause not written: '+E.Message);
    end;
  finally
    Marker.Free;
  end;
  if FExternalTransferPaused then
  begin
    SetStatus(LocalText('afilemanager_status_transfer_pausing',
      'Pausing transfer...'));
    if FTransferProgressDialog<>nil then
      FTransferProgressDialog.SetPaused(True);
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.ResumeTransferClick(ASender: TArosaControl);
begin
  if not FExternalTransferActive or not FExternalTransferPaused or
     FExternalTransferCancelAsked then Exit;
  SysUtils.DeleteFile(FExternalTransferPausePath);
  FExternalTransferPaused:=False;
  SetStatus(LocalText('afilemanager_status_transfer_resuming',
    'Resuming transfer...'));
  if FTransferProgressDialog<>nil then
    FTransferProgressDialog.SetPaused(False);
  if ASender=nil then ;
end;

procedure TAFileManagerController.CancelTransferClick(ASender: TArosaControl);
var Marker: TStringList;
begin
  if FExternalTransferActive then
  begin
    if FExternalTransferCancelAsked then Exit;
    if FExternalTransferPaused then
    begin
      SysUtils.DeleteFile(FExternalTransferPausePath);
      FExternalTransferPaused:=False;
    end;
    { Ask, never kill: the worker checks for this file between items, so a
      file being written is always finished or cleanly abandoned by AGet. }
    Marker:=TStringList.Create;
    try
      Marker.Add('cancel');
      try
        Marker.SaveToFile(FExternalTransferCancelPath);
        FExternalTransferCancelAsked:=True;
      except
        on E: Exception do
          Diagnostic('RESOURCE-OPERATION external cancel not written: '+E.Message);
      end;
    finally
      Marker.Free;
    end;
    if FExternalTransferCancelAsked then
    begin
      if FTransferCancelButton<>nil then FTransferCancelButton.Enabled:=False;
      if FTransferProgressDialog<>nil then
      begin
        FTransferProgressDialog.SetPaused(False);
        FTransferProgressDialog.SetCancelling(True);
      end;
      SetStatus(LocalText('afilemanager_status_transfer_cancelling',
        'Cancelling after the current item...'));
      Diagnostic('RESOURCE-OPERATION external cancel requested');
    end
    else
      SetStatus(LocalText('afilemanager_status_transfer_cancel_failed',
        'The cancel request could not be written to T:.'));
    Exit;
  end;
  if FTransferJob=nil then Exit;
  FTransferJob.RequestCancel;
  if FTransferCancelButton<>nil then FTransferCancelButton.Enabled:=False;
  SetStatus('Cancelling transfer after the current resource...');
  Diagnostic('RESOURCE-OPERATION background cancel requested');
  if ASender=nil then ;
end;

procedure TAFileManagerController.TransferIdle(var AMoreWorkPending: Boolean);
var N: Integer; Finished: Boolean; Job: TAFMTransferJob;
    Report: TAFMTransferReport;
begin
  if FExternalTransferActive then
  begin
    { nothing to look at yet: do not even allocate }
    if (FExternalTransferPollTick<>0) and
       (GetTickCount64-FExternalTransferPollTick<200) then
    begin
      AMoreWorkPending:=False;
      Exit;
    end;
    Report:=TAFMTransferReport.Create;
    try
      if PollExternalProviderTransfer(Report) then
      begin
        FinishExternalProviderTransfer(Report);
        AMoreWorkPending:=False;
        Exit;
      end;
    finally
      Report.Free;
    end;
    { Waiting is not work.  Claiming "more work pending" here would make
      the event loop spin instead of sleeping in its native wait, and a
      spinning AFileManager takes processor time from the very worker it
      is waiting for.  The loop wakes this handler again on its own, every
      wait timeout (50 ms), which is far more often than the files change. }
    AMoreWorkPending:=False;
    Exit;
  end;
  if FTransferJob<>nil then
  begin
    Job:=FTransferJob;
    Finished:=Job.Step;
    if Finished then
    begin
      TransferCompleted(Job);
      AMoreWorkPending:=FTransferJob<>nil;
      Exit;
    end;
    N:=Job.ProgressUnits;
    if N<>FTransferLastProgress then
    begin
      FTransferLastProgress:=N;
      SetStatus('Background transfer: '+IntToStr(N)+' resource(s) processed');
    end;
    AMoreWorkPending:=True;
  end
  else if FTransferIdleAttached then
  begin
    if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
       (FNativeHost.Application.Loop<>nil) then
      FNativeHost.Application.Loop.RemoveIdleHandler(@TransferIdle);
    FTransferIdleAttached:=False;
  end;
end;

procedure TAFileManagerController.TransferCompleted(AJob: TArosaWorkerJob);
var J: TAFMTransferJob; Msg: string; I: Integer;
begin
  if AJob<>FTransferJob then Exit;
  J:=FTransferJob;
  { Restore controller callbacks only now, on the UI task. }
  FResourceOperations.OnError:=@ResourceOperationError;
  FResourceOperations.OnConflict:=@ResourceConflict;
  FResourceOperations.OnTransferContinue:=nil;
  FResourceOperations.OnTransferProgress:=nil;
  if FTransferCancelButton<>nil then
  begin
    FTransferCancelButton.Visible:=False;
    FTransferCancelButton.Enabled:=True;
  end;
  if J.Cancelled then
    Msg:='Transfer cancelled after '+IntToStr(J.ProgressUnits)+' resource(s)'
  else if J.Failed then
    Msg:='Transfer failed: '+J.ErrorText
  else if J.Successful then
    Msg:=ArosaTransferOperationName(FPendingTransferOp)+': '+
      IntToStr(J.CompletedTopLevel)+' top-level resource(s), '+
      IntToStr(J.ProgressUnits)+' total resource(s) processed'
  else
    Msg:='Transfer completed with no resources transferred';
  if J.Errors.Count>0 then
  begin
    Msg:=Msg+' - '+IntToStr(J.Errors.Count)+' error(s): '+J.Errors[0];
    for I:=1 to J.Errors.Count-1 do
      Diagnostic('RESOURCE-OPERATION background error '+J.Errors[I]);
  end;
  Diagnostic('RESOURCE-OPERATION background done cancelled='+BoolToStr(J.Cancelled,True)+
    ' successful='+BoolToStr(J.Successful,True)+' units='+IntToStr(J.ProgressUnits));
  { A completed background cut/paste may clear the resource clipboard, but
    only when it still contains the exact snapshot that started this job. If
    the user copied something else while the transfer ran, preserve it. }
  if (not J.Cancelled) and J.Successful and (FPendingTransferOp=atoMove) and
     SameText(FPendingOpKind,'paste') and (FResourceClipboard<>nil) and
     (FResourceClipboard.Mode=arcmCut) and
     (FResourceClipboard.Count=FPendingItems.Count) then
  begin
    I:=0;
    while (I<FPendingItems.Count) and
      SameText(FResourceClipboard.Resource(I),FPendingItems[I]) do Inc(I);
    if I=FPendingItems.Count then FResourceClipboard.Clear;
  end;
  SetStatus(Msg);
  RefreshAffectedViews(FPendingItems,FPendingDest);
  if FPendingTargetView>=0 then SetActiveView(FPendingTargetView);
  FResourceOperations.ClearConflictDecisions;
  FPendingOpKind:='';
  FPendingDest:='';
  FPendingItems.Clear;
  FConflictSources.Clear;
  FConflictDests.Clear;
  FTransferJob:=nil;
  J.Free;
  if FClosingApplication then RequestApplicationClose;
end;

procedure TAFileManagerController.RunPendingResourceOperation;
var Done, Planned: Integer; Kind, Msg, Errors: string; Ok: Boolean;
begin
  Kind:=FPendingOpKind;
  if Kind='' then Exit;
  if PendingOperationNeedsWorker then
  begin
    StartBackgroundResourceOperation(AFM_PHASE_RUN);
    Exit;
  end;
  Planned:=FConflictDests.Count;
  FUnplannedConflicts:=0;
  Done:=0;
  BeginOperationErrors;
  if SameText(Kind,'paste') then
    Ok:=FResourceOperations.Paste(FPendingDest,Done)
  else
    Ok:=FResourceOperations.Transfer(FPendingItems,FPendingDest,FPendingTransferOp,Done);
  FResourceOperations.ClearConflictDecisions;
  FPendingOpKind:='';
  Errors:=EndOperationErrors;
  if SameText(Kind,'paste') then Msg:=LocalText('afilemanager_status_pasted','Pasted')
  else Msg:=ArosaTransferOperationName(FPendingTransferOp);
  if Ok then Msg:=Msg+': '+IntToStr(Done)+' '+LocalText('afilemanager_status_resources','resource(s)')
  else Msg:=Msg+': '+LocalText('afilemanager_status_nothing_transferred','nothing was transferred');
  if Planned>0 then
    Msg:=Msg+', '+IntToStr(Planned)+' '+
      LocalText('afilemanager_status_conflicts_decided','conflict(s) decided');
  if FUnplannedConflicts>0 then
    Msg:=Msg+', '+IntToStr(FUnplannedConflicts)+' '+
      LocalText('afilemanager_status_unplanned_skipped','appeared meanwhile and were skipped');
  SetStatus(Msg+Errors);
  if SameText(Kind,'transfer') and
     DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'operation.result planner=in-process ok='+BoolToStr(Ok,True)+
      ' completed='+IntToStr(Done)+
      ' planned-conflicts='+IntToStr(Planned)+
      ' unplanned='+IntToStr(FUnplannedConflicts));
  Diagnostic('RESOURCE-OPERATION done kind='+Kind+' ok='+BoolToStr(Ok,True)+
    ' completed='+IntToStr(Done)+' planned-conflicts='+IntToStr(Planned)+
    ' unplanned='+IntToStr(FUnplannedConflicts));
  RefreshAffectedViews(FPendingItems,FPendingDest);
  if FPendingTargetView>=0 then SetActiveView(FPendingTargetView);
end;

function TAFileManagerController.EnvironmentSection(const AEnvironment,
  ASurface, AFallback: string): TStringList;
var SectionName: string;
begin
  Result:=nil;
  if FDescriptor=nil then Exit;
  SectionName:='Environment.'+AEnvironment+'.'+ASurface;
  Result:=FDescriptor.Section(SectionName);
  if (Result<>nil) and (Result.Count=0) then
  begin
    Result.Free;
    Result:=FDescriptor.Section(AFallback);
  end;
end;

procedure TAFileManagerController.RebuildCommandSurface(ATabs: TArosaTabControl;
  ADescriptor: TStringList; const ADefaultPage: string);

  { 0.15.34.2: True when AControl is one of the surface's controls }
  function Inside(AControl: TArosaVisual): Boolean;
  var V: TArosaVisual;
  begin
    Result:=False;
    V:=AControl;
    while V<>nil do
    begin
      if V=ATabs then Exit(True);
      V:=V.ParentVisual;
    end;
  end;

  procedure Forget(var AButton: TArosaButton);
  begin
    if (AButton<>nil) and Inside(AButton) then AButton:=nil;
  end;

begin
  if ATabs=nil then Exit;
  { 0.15.34.2: the pages go, and the buttons and the label on them with
    them.  The controller keeps references to some of them (the View
    toggles, the console tools, the panel size label); a descriptor that
    does not have them again (the Console environment has no View page)
    left those references to freed controls, and UpdateViewToolbarState
    then wrote to them - "Open Console Here" crashed AFileManager in
    TArosaVisual.LocalToRoot.  They are forgotten before the pages go;
    BuildCommandTabs sets the ones the new descriptor has. }
  Forget(FHiddenToolbarButton);
  Forget(FThumbnailToolbarButton);
  Forget(FPreviewToolbarButton);
  Forget(FMetadataToolbarButton);
  Forget(FPlacesDetailToolbarButton);
  Forget(FSplitToolbarButton);
  Forget(FListModeRadio);
  Forget(FDetailsModeRadio);
  Forget(FIconsModeRadio);
  Forget(FWindowsModeRadio);
  Forget(FConsoleWrapButton);
  Forget(FConsoleColumnsButton);
  Forget(FConsoleColumnLessButton);
  Forget(FConsoleColumnMoreButton);
  Forget(FConsoleFontSmallerButton);
  Forget(FConsoleFontLargerButton);
  if (FPreviewPercentLabel<>nil) and Inside(FPreviewPercentLabel) then FPreviewPercentLabel:=nil;
  while ATabs.PageCount>0 do ATabs.RemovePage(0);
  if (ADescriptor<>nil) and (ADescriptor.Count>0) then
    BuildCommandTabs(ATabs,ADescriptor,ADefaultPage);
end;

procedure TAFileManagerController.ActivateEnvironment(const AEnvironment: string);
var ToolbarDescriptor, OperationsDescriptor: TStringList;
    Env: string;
begin
  Env:=AEnvironment;
  if Env='' then Env:='Files';
  if SameText(FActiveEnvironment,Env) then Exit;
  FActiveEnvironment:=Env;

  ToolbarDescriptor:=EnvironmentSection(Env,'Toolbar','Toolbar');
  OperationsDescriptor:=EnvironmentSection(Env,'Operations','Operations');
  try
    { Visibility is NOT an environment decision. The burger/descriptor state
      still owns whether these surfaces are shown. Only their content changes. }
    RebuildCommandSurface(FToolbarTabs,ToolbarDescriptor,'NAVIGATION');
    RebuildCommandSurface(FOperationTabs,OperationsDescriptor,'OPERATIONS');
  finally
    ToolbarDescriptor.Free;
    OperationsDescriptor.Free;
  end;
  Diagnostic('ENVIRONMENT active='+Env);
end;

procedure TAFileManagerController.DocumentTabChanged(ASender: TObject;
  AIndex: Integer);
var I: Integer; D: TAFileManagerConsoleDocument;
begin
  if AIndex=0 then
  begin
    ActivateEnvironment('Files');
    Exit;
  end;
  if FConsoles<>nil then
    for I:=0 to FConsoles.Count-1 do
    begin
      D:=TAFileManagerConsoleDocument(FConsoles[I]);
      if D.TabIndex=AIndex then
      begin
        FConsole:=D.Console;
        FShellSession:=D.Session;
        ActivateEnvironment('Console');
        UpdateConsoleToolState;
        Exit;
      end;
    end;
  ActivateEnvironment('Editor');
  if ASender=nil then ;
end;

procedure TAFileManagerController.HideDocumentTabMenu;
begin
  FDocumentTabMenuPage:=nil;
  if FDocumentTabMenu<>nil then
  begin
    FDocumentTabMenu.Visible:=False;
    FDocumentTabMenu.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.DocumentTabContextRequested(ASender: TObject;
  AIndex: Integer; const APosition: TArosaPoint);
var P: TArosaPoint;
begin
  FDocumentTabMenuPage:=nil;
  if (FDocumentTabs=nil) or (FDocumentTabMenu=nil) then Exit;

  { Index zero is the permanent Files page (a splitter, not a document page).
    Only real TArosaTabPage objects are closable here. }
  if (AIndex>0) and (AIndex<FDocumentTabs.ChildVisualCount) and
     (FDocumentTabs.ChildVisuals[AIndex] is TArosaTabPage) then
    FDocumentTabMenuPage:=TArosaTabPage(FDocumentTabs.ChildVisuals[AIndex]);

  if FDocumentTabCloseButton<>nil then
    FDocumentTabCloseButton.Enabled:=FDocumentTabMenuPage<>nil;

  P:=FDocumentTabs.LocalToRoot(APosition);
  FDocumentTabMenu.ShowAt(ArosaCoordWhole(P.X),
    ArosaCoordWhole(P.Y)+ArosaCoordWhole(FDocumentTabs.HeaderHeight),150,34);
  if ASender=nil then ;
end;

procedure TAFileManagerController.DocumentTabCloseClick(ASender: TArosaControl);
var I: Integer; Page: TArosaTabPage; D: TAFileManagerConsoleDocument;
    Doc: TAFileManagerDocument;
begin
  Page:=FDocumentTabMenuPage;
  HideDocumentTabMenu;
  if Page=nil then
  begin
    SetStatus('Files tab is permanent');
    Exit;
  end;

  { Resolve the owner by live page identity at click time. No cached tab index
    is trusted for destructive operations. }
  if FConsoles<>nil then
    for I:=0 to FConsoles.Count-1 do
    begin
      D:=TAFileManagerConsoleDocument(FConsoles[I]);
      if (D<>nil) and (D.Page=Page) then
      begin
        CloseConsoleDocument(D);
        Exit;
      end;
    end;

  if FDocuments<>nil then
    for I:=0 to FDocuments.Count-1 do
    begin
      Doc:=TAFileManagerDocument(FDocuments[I]);
      if (Doc<>nil) and (Doc.Page=Page) then
      begin
        RequestCloseDocument(Doc);
        Exit;
      end;
    end;

  SetStatus('Selected tab is no longer available');
  if ASender=nil then ;
end;

procedure TAFileManagerController.StyleCommandTabs(ATabs: TArosaTabControl);
begin
  if ATabs=nil then Exit;
  ATabs.Font := FCompactFont;
  ATabs.HeaderHeight := ArosaCoord(20);
  ATabs.ActiveBackground := FTheme.ColourFor(AROSA_ROLE_TAB_ACTIVE);
  ATabs.InactiveBackground := FTheme.ColourFor(AROSA_ROLE_TAB_INACTIVE);
  ATabs.ActiveText := FTheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT);
  ATabs.InactiveText := FTheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT);
  ATabs.BorderColour := FTheme.ColourFor(AROSA_ROLE_BORDER);
  ATabs.CornerRadius := FTheme.Metrics.BorderRadius;
end;

procedure TAFileManagerController.BuildCommandTabs(ATabs: TArosaTabControl;
  ADescriptor: TStringList; const ADefaultPage: string;
  ARegisterConsoleStateButtons: Boolean);
var
  I, EqPos, DotPos, PIndex, RIndex, ButtonWidth: Integer;
  Key, Caption, PageName, CommandName, GroupName, RowKey: string;
  IconSpec, IconPath, IconError: string;
  IconResource: TArosaImageResource;
  Page: TArosaTabPage;
  OuterRow, InnerRow: TArosaRowPanel;
  Box: TArosaGroupBox;
  Pages, OuterRows, Rows: TStringList;
  H: TArosaClickEvent;
  B: TArosaButton;
  L: TArosaLabel;
begin
  Pages:=TStringList.Create;
  OuterRows:=TStringList.Create;
  Rows:=TStringList.Create;
  try
    Pages.CaseSensitive:=False;
    OuterRows.CaseSensitive:=False;
    Rows.CaseSensitive:=False;
    for I:=0 to ADescriptor.Count-1 do
    begin
      Key:=Trim(ADescriptor[I]);
      if (Key='') or (Key[1]=';') or (Key[1]='#') then Continue;
      EqPos:=Pos('=',Key);
      if EqPos<=1 then Continue;
      Caption:=Trim(Copy(Key,EqPos+1,MaxInt));
      Key:=Trim(Copy(Key,1,EqPos-1));
      Caption:=LocalValue(Caption,Key);
      DotPos:=Pos('.',Key);
      if DotPos>0 then
      begin
        PageName:=UpperCase(Copy(Key,1,DotPos-1));
        CommandName:=Key;
        { Console.Commands is the button surface that opens/prepares the live
          command console; it is not itself the interactive console.  Calling
          both tabs "Console" made the operations panel ambiguous. }
        if SameText(CommandName,'Console.Commands') then PageName:='COMMANDS';
      end
      else
      begin
        PageName:=UpperCase(ADefaultPage);
        CommandName:=Key;
      end;
      H:=HandlerForCommand(CommandName);
      if not Assigned(H) then Continue;

      PIndex:=Pages.IndexOf(PageName);
      if PIndex<0 then
      begin
        Page:=NewPage(ATabs,LocalText('afilemanager_tab_'+LowerCase(PageName),PageName));
        OuterRow:=TArosaRowPanel.Create;
        OuterRow.Spacing:=ArosaCoord(3);
        OuterRow.SetConstraintHeight(asmFixed,ArosaCoord(54));
        Page.AddVisual(OuterRow);
        Pages.AddObject(PageName,Page);
        OuterRows.AddObject(PageName,OuterRow);
      end
      else
        OuterRow:=TArosaRowPanel(OuterRows.Objects[OuterRows.IndexOf(PageName)]);

      if FDescriptor<>nil then
        GroupName:=LocalValue(Trim(FDescriptor.Value('ToolbarGroups',CommandName,'')),'')
      else
        GroupName:='';
      if GroupName='' then
      begin
        if SameText(PageName,'VIEW') then
        begin
          if SameText(CommandName,'View.List') or SameText(CommandName,'View.Details') or
             SameText(CommandName,'View.Icons') or SameText(CommandName,'View.Windows') then GroupName:='Mode'
          else if SameText(CommandName,'View.Preview') then GroupName:='Preview'
          else if SameText(CommandName,'View.Thumbnails') then GroupName:='Visibility'
          else if SameText(CommandName,'View.Console.Wrap') then GroupName:='Presentation'
          else if SameText(CommandName,'View.Console.ColumnLess') or
                  SameText(CommandName,'View.Console.ColumnMore') then GroupName:='Columns'
          else if SameText(CommandName,'View.Console.FontSmaller') or
                  SameText(CommandName,'View.Console.FontLarger') then GroupName:='Font'
          else if SameText(CommandName,'View.Console.New') or
                  SameText(CommandName,'View.Console.Close') then GroupName:='Console'
          else GroupName:='Panels';
        end
        else
          GroupName:='Commands';
      end;

      RowKey:=PageName+'/'+GroupName;
      RIndex:=Rows.IndexOf(RowKey);
      if RIndex<0 then
      begin
        Box:=TArosaGroupBox.CreateControl(FTheme,FFonts);
        Box.Caption:=GroupName;
        Box.SetConstraintHeight(asmFixed,ArosaCoord(52));
        if SameText(GroupName,'Mode') then Box.SetConstraintWidth(asmFixed,ArosaCoord(176))
        else if SameText(GroupName,'Preview') then Box.SetConstraintWidth(asmFixed,ArosaCoord(176))
        else Box.SetConstraintWidth(asmFixed,ArosaCoord(220));
        InnerRow:=TArosaRowPanel.Create;
        InnerRow.Spacing:=ArosaCoord(2);
        InnerRow.SetConstraintHeight(asmFixed,ArosaCoord(26));
        Box.AddVisual(InnerRow);
        OuterRow.AddVisual(Box);
        Rows.AddObject(RowKey,InnerRow);
      end
      else
        InnerRow:=TArosaRowPanel(Rows.Objects[RIndex]);

      { 0.6.1.2: every toolbar command, including the view modes, is an
        image button; selection is shown with the Toggled state (see
        UpdateViewToolbarState) instead of a radio indicator beside an image. }
      begin
        ButtonWidth:=54;
        if (FCompactFont<>nil) and (FCompactFont.Metrics.AverageWidth>0) then
          ButtonWidth:=ArosaCoordWhole(FCompactFont.Metrics.AverageWidth)*Length(Caption)+14
        else
          ButtonWidth:=Length(Caption)*7+14;
        if ButtonWidth<54 then ButtonWidth:=54;
        B:=NewButton(InnerRow,Caption,CommandName,H,ButtonWidth);
        B.SetConstraintHeight(asmFixed,ArosaCoord(24));
        { Every command surface participates in the Bubble Service, whether it
          is represented by an icon or by text.  A missing icon must not also
          remove the hint/context information. }
        if FDescriptor<>nil then
          B.Hint:=LocalValue(FDescriptor.Value('ToolbarHints',CommandName,Caption),Caption)
        else
          B.Hint:=Caption;
        B.ContextTitle:=Caption;
        if FDescriptor<>nil then
          B.ContextDescription:=LocalValue(
            Trim(FDescriptor.Value('ToolbarDescriptions',CommandName,'')),'');
        { Command surfaces prefer icons.  A descriptor mapping of "none" is
          the explicit text-only override. }
        ApplyButtonIcon(B,'ToolbarIcons',CommandName,30);
        if SameText(CommandName,'View.Hidden') then FHiddenToolbarButton:=B
        else if SameText(CommandName,'View.Thumbnails') then FThumbnailToolbarButton:=B
        else if SameText(CommandName,'View.Preview') then FPreviewToolbarButton:=B
        else if SameText(CommandName,'View.Metadata') then FMetadataToolbarButton:=B
        else if SameText(CommandName,'View.PlacesDetails') then FPlacesDetailToolbarButton:=B
        else if SameText(CommandName,'View.SplitView') or SameText(CommandName,'View.DualPane') then
          FSplitToolbarButton:=B
        else if SameText(CommandName,'View.List') then FListModeRadio:=B
        else if SameText(CommandName,'View.Details') then FDetailsModeRadio:=B
        else if SameText(CommandName,'View.Icons') then FIconsModeRadio:=B
        else if SameText(CommandName,'View.Windows') then FWindowsModeRadio:=B
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.Wrap') or SameText(CommandName,'View.Console.Wrap')) then
          FConsoleWrapButton:=B
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.Columns') or SameText(CommandName,'View.Console.Columns')) then
          FConsoleColumnsButton:=B
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.ColumnLess') or SameText(CommandName,'View.Console.ColumnLess')) then
          FConsoleColumnLessButton:=B
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.ColumnMore') or SameText(CommandName,'View.Console.ColumnMore')) then
          FConsoleColumnMoreButton:=B
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.FontSmaller') or SameText(CommandName,'View.Console.FontSmaller')) then
        begin
          FConsoleFontSmallerButton:=B;
          B.Visible:=True;
        end
        else if ARegisterConsoleStateButtons and
                (SameText(CommandName,'Console.FontLarger') or SameText(CommandName,'View.Console.FontLarger')) then
        begin
          FConsoleFontLargerButton:=B;
          B.Visible:=True;
        end;
      end;

      if SameText(CommandName,'View.Preview') then
      begin
        GroupName:=LocalValue(
          Trim(FDescriptor.Value('ToolbarGroups','View.PreviewShare',
            '@afilemanager_group_panel_size')),
          LocalText('afilemanager_group_panel_size','Panel Size'));
        if GroupName='' then GroupName:=LocalText('afilemanager_group_panel_size','Panel Size');
        RowKey:=PageName+'/'+GroupName;
        RIndex:=Rows.IndexOf(RowKey);
        if RIndex<0 then
        begin
          Box:=TArosaGroupBox.CreateControl(FTheme,FFonts);
          Box.Caption:=GroupName;
          Box.SetConstraintHeight(asmFixed,ArosaCoord(52));
          Box.SetConstraintWidth(asmFixed,ArosaCoord(126));
          InnerRow:=TArosaRowPanel.Create;
          InnerRow.Spacing:=ArosaCoord(2);
          InnerRow.SetConstraintHeight(asmFixed,ArosaCoord(26));
          Box.AddVisual(InnerRow);
          OuterRow.AddVisual(Box);
          Rows.AddObject(RowKey,InnerRow);
        end
        else
          InnerRow:=TArosaRowPanel(Rows.Objects[RIndex]);
        B:=NewButton(InnerRow,'-', 'Preview share -5%',@PreviewShareDownClick,24);
        ApplyButtonIcon(B,'ToolbarIcons','Panel.Smaller',24);
        B.SetConstraintHeight(asmFixed,ArosaCoord(24));
        FPreviewPercentLabel:=TArosaLabel.CreateControl(FTheme,FFonts);
        FPreviewPercentLabel.Text:=IntToStr(FPreviewPercent)+'%';
        FPreviewPercentLabel.FontFamily:=FCompactFont.Description.Family;
        FPreviewPercentLabel.FontSize:=FCompactFont.Description.SizePoints;
        FPreviewPercentLabel.SetConstraintWidth(asmFixed,ArosaCoord(42));
        FPreviewPercentLabel.SetConstraintHeight(asmFixed,ArosaCoord(24));
        InnerRow.AddVisual(FPreviewPercentLabel);
        B:=NewButton(InnerRow,'+', 'Preview share +5%',@PreviewShareUpClick,24);
        ApplyButtonIcon(B,'ToolbarIcons','Panel.Larger',24);
        B.SetConstraintHeight(asmFixed,ArosaCoord(24));
      end;
    end;
    UpdateViewToolbarState;
    UpdateConsoleToolState;
    ATabs.InvalidateLayout;
    ATabs.InvalidatePaint;
  finally
    Rows.Free;
    OuterRows.Free;
    Pages.Free;
  end;
end;

procedure TAFileManagerController.TestAutoCloseIdle(var AMoreWorkPending: Boolean);
var Name, S: string; I: Integer;
begin
  if FTestCloseAfterMs=0 then Exit;
  if (not FTestPreviewDone) and (GetTickCount64-FTestStartTick>=FTestCloseAfterMs div 3) then
  begin
    FTestPreviewDone:=True;
    { 0.7.13.0.0 AROSA_TEST_SURFACES=1: split view on, two new file
      managers (one moved elsewhere), switch back, close one - each step
      logged.  Environment only; inert otherwise. }
    if Trim(GetEnvironmentVariable('AROSA_TEST_SURFACES'))='1' then
    begin
      if (FWindowFrame<>nil) and not FWindowFrame.SplitView then ToggleSplitClick(nil);
      Diagnostic('TEST surfaces start count='+IntToStr(FSurfaces.Count)+' location='+FRightCurrent);
      NewFileManagerClick(nil);
      NavigateView(1,FLocations.Parent(FRightCurrent));
      Diagnostic('TEST surfaces second moved to='+FRightCurrent+' count='+IntToStr(FSurfaces.Count));
      NewFileManagerClick(nil);
      Diagnostic('TEST surfaces third count='+IntToStr(FSurfaces.Count)+' active='+IntToStr(FActiveSurface));
      SaveActiveSurface; ShowSurface(1);
      Diagnostic('TEST surfaces switched to 1 location='+FRightCurrent);
      SaveActiveSurface; ShowSurface(0);
      Diagnostic('TEST surfaces switched to 0 location='+FRightCurrent);
      CloseFileManagerClick(nil);
      Diagnostic('TEST surfaces after close count='+IntToStr(FSurfaces.Count)+' active='+IntToStr(FActiveSurface)+
        ' location='+FRightCurrent+' bar='+IntToStr(FSurfaceBar.ChildVisualCount));
    end;
    { 0.8.6.3 AROSA_TEST_LOCATION=<drawer>: the left pane goes there first,
      and the preview panel is shown, so AROSA_TEST_PREVIEW can name any
      file.  The log then tells how the preview went (see below). }
    Name:=Trim(GetEnvironmentVariable('AROSA_TEST_LOCATION'));
    if Name<>'' then
    begin
      SetActiveView(0);
      NavigateView(0,Name);
      if not FPreviewVisible then SetPanels(True,FMetadataVisible,0);
      Diagnostic('TEST location='+ViewCurrent(0)+' items='+IntToStr(FLeftList.ItemCount)+
        ' preview-visible='+BoolToStr(PreviewPageActive(0),'TRUE','FALSE'));
      { 0.8.6.6: what the pane lists there }
      for I:=0 to FLeftList.ItemCount-1 do
        Diagnostic('TEST row '+IntToStr(I)+' '+SelectedPath(0,I));
    end;
    Name:=Trim(GetEnvironmentVariable('AROSA_TEST_PREVIEW'));
    if (Name<>'') and (FLeftList<>nil) then
      for I:=0 to FLeftList.ItemCount-1 do
        if SameText(ExtractFileName(SelectedPath(0,I)),Name) then
        begin
          SetActiveView(0);
          FLeftList.SelectItem(I);
          UpdatePreview(0);
          Diagnostic('TEST preview name='+Name+' presentation='+
            BoolToStr(FLeftPresentation<>nil,'TRUE','FALSE'));
          Break;
        end;
  end;
  { AROSA_TEST_CONSOLE='line;line;...': the console at the left pane's
    location runs each line; every output line goes to the runtime log }
  if (not FTestConsoleDone) and FTestPreviewDone then
  begin
    FTestConsoleDone:=True;
    Name:=Trim(GetEnvironmentVariable('AROSA_TEST_CONSOLE'));
    if Name<>'' then
    begin
      OpenConsoleAt(ViewCurrent(0));
      while Name<>'' do
      begin
        I:=Pos(';',Name);
        if I=0 then I:=Length(Name)+1;
        ConsoleSubmit(FConsole,Trim(Copy(Name,1,I-1)));
        Delete(Name,1,I);
      end;
      if FConsole<>nil then
        for I:=0 to FConsole.LineCount-1 do Diagnostic('TEST console: '+FConsole.Line(I));
    end;
  end;
  { 0.8.6.4 AROSA_TEST_WORKSPACE_MENU=<workspace id>: that workspace opens on
    its own screen, and its start menu is opened, filled, used and emptied,
    one step every 300 ms }
  if FTestPreviewDone and (FTestMenuStep<5) and (not FWorkspaceSessionMode) and
     (GetTickCount64-FTestMenuTick>=300) then
  begin
    Name:=Trim(GetEnvironmentVariable('AROSA_TEST_WORKSPACE_MENU'));
    if (Name='') or (FWorkspaces=nil) or (FWorkspaces.Find(Name)=nil) then
      FTestMenuStep:=5
    else
    begin
      FTestMenuTick:=GetTickCount64;
      if WorkspacePrototypeById(Name)=nil then
      begin
        OpenWorkspacePrototype(FWorkspaces.Find(Name));
        Diagnostic('TEST menu workspace='+Name+' open='+
          BoolToStr((WorkspacePrototypeById(Name)<>nil) and
            WorkspacePrototypeById(Name).IsOpen,'TRUE','FALSE'));
        if (WorkspacePrototypeById(Name)=nil) or
           (not WorkspacePrototypeById(Name).IsOpen) then FTestMenuStep:=5;
      end
      else
      begin
        if WorkspacePrototypeById(Name).Taskbar<>nil then
          WorkspacePrototypeById(Name).Taskbar.TestStep(FTestMenuStep);
        Inc(FTestMenuStep);
      end;
    end;
  end;
  { AROSA_TEST_WORKSPACE_MODULES=<workspace id> (0.8.7.0): the modules dialog
    of that workspace.  Boxes are ticked and nothing changes; Apply changes
    it; Restore puts the boxes back; Cancel closes and drops what was not
    applied; Save applies and closes.  What the dialog, this window and the
    window of the workspace (if its screen is open) show is written after
    each step. }
  if FTestPreviewDone and (not FWorkspaceSessionMode) and (FTestModStep<9) and
     (GetTickCount64-FTestModTick>=600) then
  begin
    Name:=Trim(GetEnvironmentVariable('AROSA_TEST_WORKSPACE_MODULES'));
    if (Name='') or (FWorkspaces=nil) or (FWorkspaces.Find(Name)=nil) or
       (FWorkspaceModulesDialog=nil) then FTestModStep:=9
    else
    begin
      FTestModTick:=GetTickCount64;
      S:='';
      case FTestModStep of
        0: begin
             S:='open, Resource Monitor not in the workspace';
             if Trim(GetEnvironmentVariable('AROSA_NULL_SCREENS'))='1' then
               OpenWorkspacePrototype(FWorkspaces.Find(Name));
             WorkspaceModuleChanged(nil,Name,'arosa.application.aresourcemonitor',False);
             ShowWorkspaceModules(Name);
           end;
        1: begin
             S:='tick taskbar (not applied)';
             FWorkspaceModulesDialog.TestToggle('arosa.application.aresourcemonitor',2);
             FWorkspaceModulesDialog.TestToggle('arosa.module.security',1);       { planned }
           end;
        2: begin S:='Apply'; FWorkspaceModulesDialog.TestPress('apply'); end;
        3: begin
             S:='tick desktop, untick taskbar (not applied)';
             FWorkspaceModulesDialog.TestToggle('arosa.application.aresourcemonitor',3);
             FWorkspaceModulesDialog.TestToggle('arosa.application.aresourcemonitor',2);
           end;
        4: begin S:='Restore'; FWorkspaceModulesDialog.TestPress('restore'); end;
        5: begin S:='Cancel'; FWorkspaceModulesDialog.TestPress('cancel'); end;
        6: begin
             S:='open again, untick workspace (not applied)';
             ShowWorkspaceModules(Name);
             FWorkspaceModulesDialog.TestToggle('arosa.application.aresourcemonitor',0);
           end;
        7: begin S:='Save'; FWorkspaceModulesDialog.TestPress('save'); end;
        8: S:='end';
      end;
      Diagnostic('TEST modules step='+IntToStr(FTestModStep)+' ('+S+') dialog:'+
        FWorkspaceModulesDialog.TestDescribe);
      NavigateView(0,'arosa://workspace/'+Name);
      S:='';
      for I:=0 to FLeftList.ItemCount-1 do
        if Pos('exec:',SelectedPath(0,I))=1 then S:=S+' '+SelectedPath(0,I);
      Diagnostic('TEST modules step='+IntToStr(FTestModStep)+' primary lists:'+S+
        ' placed(start,taskbar,desktop)='+
        BoolToStr(ModulePlacement(Name,'arosa.application.aresourcemonitor',0),'x','-')+
        BoolToStr(ModulePlacement(Name,'arosa.application.aresourcemonitor',1),'x','-')+
        BoolToStr(ModulePlacement(Name,'arosa.application.aresourcemonitor',2),'x','-'));
      if WorkspacePrototypeById(Name)<>nil then
        with WorkspacePrototypeById(Name) do
          if Controller<>nil then
          begin
            { the window of the workspace follows at its own idle turn: what
              it shows now is the state after the PREVIOUS step }
            S:='';
            for I:=0 to Controller.FLeftList.ItemCount-1 do
              if Pos('exec:',Controller.SelectedPath(0,I))=1 then
                S:=S+' '+Controller.SelectedPath(0,I);
            Controller.Diagnostic('TEST modules before-step='+IntToStr(FTestModStep)+
              ' workspace window lists:'+S+' pins:'+Taskbar.TestPins);
          end;
      Inc(FTestModStep);
    end;
  end;
  { 0.8.6.5 AROSA_TEST_TASKBAR=1: the taskbar of THIS workspace - its start
    menu (steps 0-4), then what it knows about the volumes (every 500 ms) and
    opening the first one announced }
  if FTestPreviewDone and (not FWorkspaceSessionMode) and
     (Trim(GetEnvironmentVariable('AROSA_TEST_TASKBAR'))='1') and
     (GetTickCount64-FTestMenuTick>=500) then
  begin
    FTestMenuTick:=GetTickCount64;
    if FTaskbar=nil then
    begin
      if FTestBarStep=0 then Diagnostic('TEST taskbar none');
      FTestBarStep:=100;
    end
    else if FTestBarStep<5 then FTaskbar.TestStep(FTestBarStep)
    else if FTestBarStep<100 then
    begin
      FTaskbar.TestStep(10);
      if (FVolumeNotices.Count>0) and (FTestBarStep>=9) then
      begin
        FTaskbar.TestStep(11);
        FTestBarStep:=99;
      end;
    end
    else if FTestBarStep=100 then
      Diagnostic('TEST volume opened pending='+FPendingNavigatePath+
        ' location='+ViewCurrent(FActiveView)+
        ' notices='+IntToStr(FVolumeNotices.Count));
    if FTestBarStep<=100 then Inc(FTestBarStep);
  end;
  { 0.8.6.3: how the previewed page fared - once a second, and at the end.
    A page that is laid out or painted again and again shows here. }
  if FTestPreviewDone and (FLeftPresentation<>nil) and (FLeftPresentation.Control is TArosaHtmlView) and
     ((GetTickCount64-FTestReportTick>=1000) or (GetTickCount64-FTestStartTick>=FTestCloseAfterMs)) then
  begin
    FTestReportTick:=GetTickCount64;
    with TArosaHtmlView(FLeftPresentation.Control) do
      Diagnostic('TEST html t='+IntToStr(GetTickCount64-FTestStartTick)+'ms layouts='+IntToStr(LayoutRuns)+
        ' paints='+IntToStr(PaintRuns)+' form-passes='+IntToStr(FForm.LayoutPasses)+
        ' height='+IntToStr(ContentHeight)+' controls='+IntToStr(HostedCount)+
        ' pending='+BoolToStr(LayoutPending,'TRUE','FALSE')+
        ' failure="'+Failure+'" paint-failures='+IntToStr(ArosaPaintFailures)+
        ' last="'+ArosaLastPaintFailure+'"');
  end;
  if GetTickCount64-FTestStartTick>=FTestCloseAfterMs then
  begin
    FTestCloseAfterMs:=0;
    Diagnostic('TEST autoclose: requesting close (close-gadget path)');
    NativeCloseRequested;
  end;
end;

procedure TAFileManagerController.ReleasePresentation(var APresentation: TArosaPresentation);
var C: TArosaControl;
begin
  if APresentation=nil then Exit;
  C:=APresentation.Control;
  if (C<>nil) and (C.ParentVisual is TArosaView) then
    TArosaView(C.ParentVisual).RemoveVisual(C);
  APresentation.Close;
  FreeAndNil(APresentation);
end;

procedure TAFileManagerController.PresentationMessage(ASender: TObject;
  const AText: string);
begin
  SetStatus(AText);
  Diagnostic('PRESENTATION message: '+AText);
end;

function TAFileManagerController.CommandBarText(const AKey: string): string;
begin
  Result:=LocalText(AKey,'');   { '' = missing: the bar uses its fallback }
end;

function TAFileManagerController.ViewCommandBar(AView: Integer): TArosaCommandBar;
begin
  if AView=0 then Result:=FLeftCommandBar else Result:=FRightCommandBar;
end;

function TAFileManagerController.NewCommandBar: TArosaCommandBar;
begin
  Result:=TArosaCommandBar.CreateBar(FTheme,FFonts);
  Result.TextResolver:=@CommandBarText;
  Result.IconResolver:=@CommandBarIcon;
end;

{ 0.6.1.9: every bubble characteristic comes from the window descriptor
  (and its user overlay); texts come from the catalogues.
    [Bubbles]        Enabled, HoverDelayMs (rest time), LeaveGraceMs,
                     MaxWidth, Padding, CornerRadius, Opacity (percent)
    [Bubbles.Dark] / [Bubbles.Light]
                     Background, Text, Title, Border, Link  (#RRGGBB)
  Missing keys keep the AROSA defaults. }
procedure TAFileManagerController.ApplyBubbleColours(ATheme: TArosaTheme;
  const ASection: string);

  procedure One(const AKey, ARole: string);
  var V: string; N: LongInt;
  begin
    V:=Trim(FDescriptor.Value(ASection,AKey,''));
    if V='' then Exit;
    if V[1] in ['#','$'] then V:=Copy(V,2,MaxInt);
    if (Length(V)=6) and TryStrToInt('$'+V,N) then
      ATheme.SetRole(ARole,ArosaColour((N shr 16) and $FF,(N shr 8) and $FF,N and $FF))
    else
      Diagnostic('BUBBLE configuration: invalid colour ['+ASection+'] '+AKey+'='+V);
  end;

begin
  if (ATheme=nil) or (FDescriptor=nil) then Exit;
  ArosaRegisterBubbleRoles(ATheme);
  One('Background',AROSA_ROLE_BUBBLE_BG);
  One('Text',AROSA_ROLE_BUBBLE_TEXT);
  One('Title',AROSA_ROLE_BUBBLE_TITLE);
  One('Border',AROSA_ROLE_BUBBLE_BORDER);
  One('Link',AROSA_ROLE_BUBBLE_LINK);
end;

procedure TAFileManagerController.ApplyBubbleConfiguration;
var B: TArosaBubbleService;
begin
  if (FNativeHost=nil) or (FNativeHost.Bubbles=nil) then Exit;
  B:=FNativeHost.Bubbles;
  if FDescriptor<>nil then
  begin
    B.HoverDelayMs:=FDescriptor.IntValue('Bubbles','HoverDelayMs',1500);
    B.LeaveGraceMs:=FDescriptor.IntValue('Bubbles','LeaveGraceMs',350);
    B.MaxWidth:=ArosaCoord(FDescriptor.IntValue('Bubbles','MaxWidth',320));
    B.Padding:=ArosaCoord(FDescriptor.IntValue('Bubbles','Padding',6));
    B.CornerRadius:=ArosaCoord(FDescriptor.IntValue('Bubbles','CornerRadius',8));
    B.Opacity:=FDescriptor.IntValue('Bubbles','Opacity',88);
    ApplyBubbleColours(FDarkTheme,'Bubbles.Dark');
    ApplyBubbleColours(FLightTheme,'Bubbles.Light');
  end;
  B.MoreText:='@arosa_bubble_more|More...';
  B.LessText:='@arosa_bubble_less|Less';
  Diagnostic('BUBBLE configuration rest='+IntToStr(B.HoverDelayMs)+'ms radius='+
    IntToStr(ArosaCoordWhole(B.CornerRadius))+' opacity='+IntToStr(B.Opacity)+'%');
end;

{ ---- 0.7.5.3 theme icons ------------------------------------------------
  One loader for every icon: 'theme:name' resolves through the layered theme
  (application first, shared AROSA last); any other spec is a path.  Each
  icon is loaded once (menus are rebuilt on every toggle) and a miss is
  remembered.  Resources live until the controller is disposed.  A caller
  that gets False keeps its text or glyph - an icon is never required. }
function TAFileManagerController.LoadThemeIcon(const ASpec: string;
  out AImage: TArosaPlatformHandle; out ASource: TArosaRect): Boolean;
var
  Spec, CacheKey, Path, Err: string;
  I: Integer;
  R: TArosaImageResource;
begin
  AImage:=ArosaNilHandle;
  ASource:=ArosaRectRaw(0,0,0,0);
  Result:=False;
  Spec:=Trim(ASpec);
  if (Spec='') or (FImageLoader=nil) then Exit;
  CacheKey:=Spec;
  if Pos('theme:',LowerCase(Spec))=1 then
    CacheKey:=FActiveThemePackageId+'|'+Spec;
  if FIconCache=nil then
  begin
    FIconCache:=TStringList.Create;
    FIconCache.Sorted:=True;
    FIconCache.CaseSensitive:=False;
  end;
  I:=FIconCache.IndexOf(CacheKey);
  if I<0 then
  begin
    Path:=Spec;
    if Pos('theme:',LowerCase(Path))=1 then
      Path:=ThemeIconPath(Copy(Path,7,MaxInt));
    R:=nil; Err:='';
    if not FImageLoader.TryLoadFile(Path,R,Err) then
    begin
      R:=nil;
      ArosaTrace('ICON','unavailable spec='+Spec+' path='+Path+' error='+Err);
    end;
    I:=FIconCache.AddObject(CacheKey,R);
  end;
  R:=TArosaImageResource(FIconCache.Objects[I]);
  if R=nil then Exit;
  AImage:=R.Bitmap;
  ASource:=ArosaRectXYWH(0,0,R.Width,R.Height);
  Result:=AImage<>ArosaNilHandle;
end;

{ 0.7.5.5: built-in default icon mapping - the lowest layer.  A
  descriptor key wins; the value 'none' removes the icon; a key no
  descriptor defines (an empty value counts as undefined - descriptor
  semantics) falls back to this table.  Icons therefore appear even with
  window files from before the mappings existed. }
const
  AFM_DEFAULT_ICONS: array[0..69] of string = (
    'ToolbarIcons|View.Hidden=theme:hidden', 'ToolbarIcons|View.List=theme:list',
    'ToolbarIcons|View.Details=theme:details', 'ToolbarIcons|View.Icons=theme:icons',
    'ToolbarIcons|View.Preview=theme:preview', 'ToolbarIcons|View.Metadata=theme:metadata',
    'ToolbarIcons|View.SplitView=theme:split', 'ToolbarIcons|View.PlacesDetails=theme:places-details',
    'ToolbarIcons|History.Undo=theme:undo', 'ToolbarIcons|History.Redo=theme:redo',
    'ToolbarIcons|File.Copy=theme:copy', 'ToolbarIcons|File.Paste=theme:paste',
    'ToolbarIcons|File.Delete=theme:delete', 'ToolbarIcons|Console.Commands=theme:console',
    'ToolbarIcons|ARexx.Execute=theme:arexx', 'ToolbarIcons|Macros.Execute=theme:macros',
    'ToolbarIcons|Panel.Smaller=theme:minus', 'ToolbarIcons|Panel.Larger=theme:plus',
    'WindowIcons|Window.Close=theme:window-close', 'WindowIcons|Window.Menu=theme:window-menu',
    'WindowIcons|Window.Minimize=theme:window-minimize', 'WindowIcons|Window.Zoom=theme:window-zoom',
    'WindowIcons|Window.Depth=theme:window-depth', 'WindowIcons|Navigation.Back=theme:nav-back',
    'WindowIcons|Navigation.Up=theme:nav-up', 'WindowIcons|Navigation.Forward=theme:nav-forward',
    'WindowIcons|Navigation.Home=theme:nav-home', 'WindowIcons|View.Swap=theme:swap',
    'WindowIcons|Field.Clear=theme:clear',
    'WindowIcons|Surface.New=theme:plus', 'WindowIcons|Surface.Close=theme:window-close',
    'MenuIcons|View.NewFileManager=theme:plus', 'MenuIcons|View.CloseFileManager=theme:window-close',
    'MenuIcons|Theme=theme:theme-dark', 'MenuIcons|Theme.Dark=theme:theme-dark',
    'MenuIcons|Theme.Light=theme:theme-light', 'MenuIcons|View.Preview=theme:preview',
    'MenuIcons|View.PreviewRight=theme:preview-right', 'MenuIcons|View.PreviewBottom=theme:preview-bottom',
    'MenuIcons|View.Toolbar=theme:toolbar', 'MenuIcons|View.Operations=theme:operations',
    'MenuIcons|View.SplitView=theme:split', 'MenuIcons|View.SyncScrolling=theme:sync-scrolling',
    'MenuIcons|View.SyncWindows=theme:sync-windows',
    'ContextMenuIcons|Resource.Open=theme:open', 'ContextMenuIcons|Resource.Edit=theme:edit',
    'ContextMenuIcons|Resource.Preview=theme:preview', 'ContextMenuIcons|Resource.Metadata=theme:metadata',
    'ContextMenuIcons|Resource.Copy=theme:copy', 'ContextMenuIcons|Resource.Cut=theme:cut',
    'ContextMenuIcons|Resource.Paste=theme:paste', 'ContextMenuIcons|Resource.Delete=theme:delete',
    'ContextMenuIcons|Resource.Rename=theme:rename', 'ContextMenuIcons|Resource.CreateFile=theme:new-file',
    'ContextMenuIcons|Resource.CreateFolder=theme:new-folder', 'ContextMenuIcons|History.Undo=theme:undo',
    'ContextMenuIcons|Navigation.Refresh=theme:refresh', 'ContextMenuIcons|Selection.All=theme:select-all',
    'ContextMenuIcons|Selection.None=theme:select-none', 'ContextMenuIcons|Favorites.Toggle=theme:favorites',
    'ContextMenuIcons|Archive.CompressHere=theme:archive-compress', 'ContextMenuIcons|Archive.CompressTo=theme:archive-compress',
    'ContextMenuIcons|Archive.ExtractHere=theme:archive-extract', 'ContextMenuIcons|Archive.ExtractTo=theme:archive-extract',
    'ContextMenuIcons|Places.Open=theme:open', 'ContextMenuIcons|Places.OpenLeft=theme:open-left',
    'ContextMenuIcons|Places.OpenRight=theme:open-right', 'ContextMenuIcons|Places.Properties=theme:properties',
    'ContextMenuIcons|Places.Refresh=theme:refresh',
    'ContextMenuIcons|Console.OpenHere=theme:console');

function TAFileManagerController.IconSpecFor(const ASection, AKey: string): string;
var I, P: Integer; Prefix: string;
begin
  Result:='';
  if AKey='' then Exit;
  if (FDescriptor<>nil) and FDescriptor.HasKey(ASection,AKey) then
  begin
    Result:=Trim(FDescriptor.Value(ASection,AKey,''));
    if SameText(Result,'none') then Result:='';
    Exit;
  end;
  Prefix:=LowerCase(ASection+'|'+AKey+'=');
  for I:=0 to High(AFM_DEFAULT_ICONS) do
    if Pos(Prefix,LowerCase(AFM_DEFAULT_ICONS[I]))=1 then
    begin
      P:=Pos('=',AFM_DEFAULT_ICONS[I]);
      Exit(Copy(AFM_DEFAULT_ICONS[I],P+1,MaxInt));
    end;
end;

{ icon-only button when the icon exists: caption moves to the bubble
  title (the hint is kept); without an icon nothing changes }
function TAFileManagerController.ApplyButtonIcon(AButton: TArosaButton;
  const ASection, AKey: string; AIconWidth: Integer): Boolean;
var Img: TArosaPlatformHandle; Src: TArosaRect;
begin
  Result:=False;
  if AButton=nil then Exit;
  if not LoadThemeIcon(IconSpecFor(ASection,AKey),Img,Src) then Exit;
  AButton.Image:=Img;
  AButton.ImageSourceRect:=Src;
  if (AButton.Caption<>'') and (AButton.ContextTitle='') then
    AButton.ContextTitle:=AButton.Caption;
  AButton.Caption:='';
  if AIconWidth>0 then AButton.SetConstraintWidth(asmFixed,ArosaCoord(AIconWidth));
  Result:=True;
end;

function TAFileManagerController.ContextCommandIcon(ASender: TArosaControl;
  const ACommand: string; out AImage: TArosaPlatformHandle; out ASource: TArosaRect): Boolean;
begin
  Result:=LoadThemeIcon(IconSpecFor('ContextMenuIcons',ACommand),AImage,ASource);
  if Result then Exit;
  { Document-toolbar fallbacks are semantic AROSA icons. Keep the button
    compact even when older descriptors do not yet contain these commands. }
  if SameText(ACommand,'Search.Replace') then
  begin
    Result:=LoadThemeIcon('theme:replace',AImage,ASource);
    if not Result then Result:=LoadThemeIcon('theme:edit',AImage,ASource);
  end
  else if SameText(ACommand,'Search.GoToLine') then
    Result:=LoadThemeIcon('theme:go-to-line',AImage,ASource)
  else if SameText(ACommand,'View.Rendition') then
    Result:=LoadThemeIcon('theme:preview-right',AImage,ASource);
end;

function TAFileManagerController.CommandBarIcon(const AIconRef: string;
  out AImage: TArosaPlatformHandle; out ASource: TArosaRect): Boolean;
var
  Ref, Key, AppSpec: string;
begin
  AImage:=ArosaNilHandle;
  ASource:=ArosaRectRaw(0,0,0,0);
  Ref:=Trim(AIconRef);
  if Ref='' then Exit(False);

  { Application -> AROSA -> text.
    app:<semantic> is explicitly application-owned.  theme:<semantic> is an
    AROSA semantic request but the application is still allowed to override
    it in [CommandIcons].  'none' suppresses the application layer only; the
    standard AROSA semantic remains the fallback unless the caller requested
    app: explicitly. }
  Key:=Ref;
  if Pos('app:',LowerCase(Key))=1 then
    Key:=Copy(Key,5,MaxInt)
  else if Pos('theme:',LowerCase(Key))=1 then
    Key:=Copy(Key,7,MaxInt);

  AppSpec:='';
  if (FDescriptor<>nil) and FDescriptor.HasKey('CommandIcons',Key) then
    AppSpec:=Trim(FDescriptor.Value('CommandIcons',Key,''));

  if (AppSpec<>'') and not SameText(AppSpec,'none') and
     LoadThemeIcon(AppSpec,AImage,ASource) then Exit(True);

  if Pos('app:',LowerCase(Ref))=1 then
  begin
    { Built-in application equivalences keep ubiquitous application actions
      coherent even when a descriptor predates [CommandIcons]. }
    if SameText(Key,'previous') then AppSpec:='theme:browse-prev'
    else if SameText(Key,'next') then AppSpec:='theme:browse-next'
    else if SameText(Key,'back') then AppSpec:='theme:nav-back'
    else if SameText(Key,'top') then AppSpec:='theme:page-top'
    else if SameText(Key,'text-smaller') then AppSpec:='theme:text-smaller'
    else if SameText(Key,'text-reset') then AppSpec:='theme:text-reset'
    else if SameText(Key,'text-larger') then AppSpec:='theme:text-larger'
    else AppSpec:='';
    if (AppSpec<>'') and LoadThemeIcon(AppSpec,AImage,ASource) then Exit(True);
    Exit(False);
  end;

  { AROSA semantic fallback.  If this also cannot be resolved the generic
    command bar keeps its caption, giving the final text fallback. }
  Result:=LoadThemeIcon(Ref,AImage,ASource);
end;

{ window gadgets (drawn glyph replaced by the icon when one exists) }
procedure TAFileManagerController.ApplyWindowIconsTo(AFrame: TArosaWindowFrame);
var Img: TArosaPlatformHandle; Src: TArosaRect;

  procedure Gadget(G: TArosaButton; const AKey: string);
  begin
    if (G<>nil) and LoadThemeIcon(IconSpecFor('WindowIcons',AKey),Img,Src) then
    begin
      G.Image:=Img;
      G.ImageSourceRect:=Src;
      G.InvalidatePaint;
    end;
  end;

begin
  if AFrame=nil then Exit;
  Gadget(AFrame.CloseGadget,'Window.Close');
  Gadget(AFrame.MenuGadget,'Window.Menu');
  Gadget(AFrame.MinimizeGadget,'Window.Minimize');
  Gadget(AFrame.ZoomGadget,'Window.Zoom');
  Gadget(AFrame.DepthGadget,'Window.Depth');
end;

procedure TAFileManagerController.ApplyWindowIcons;
begin
  ApplyWindowIconsTo(FWindowFrame);
end;

{ 0.7.5.10 remote preview governance ------------------------------------ }

constructor TAFMLoadPreviewCommand.CreateFor(AOwner: TAFileManagerController; AView: Integer);
begin
  inherited Create;
  FOwner:=AOwner;
  FView:=AView;
end;

function TAFMLoadPreviewCommand.CommandCount: Integer;
begin
  Result:=1;
end;

function TAFMLoadPreviewCommand.CommandInfo(AIndex: Integer): TArosaCommandInfo;
begin
  Result:=ArosaCommandInfo('preview.load','@afilemanager_preview_load|Load preview',
    '@afilemanager_preview_load_hint|Download this file and show its preview',
    '','theme:open','preview',False);
end;

function TAFMLoadPreviewCommand.CanHandleCommand(const ACommandId: TArosaCommandId): Boolean;
begin
  Result:=SameText(ACommandId,'preview.load');
end;

function TAFMLoadPreviewCommand.ExecuteCommand(const ACommandId: TArosaCommandId;
  AContext: TArosaCommandContext): Boolean;
begin
  Result:=CanHandleCommand(ACommandId) and (FOwner<>nil);
  if Result then FOwner.ForcePreview(FView);
end;

procedure TAFMLoadPreviewCommand.QueryCommandState(const ACommandId: TArosaCommandId;
  var AEnabled, AVisible, AChecked: Boolean);
begin
  AVisible:=CanHandleCommand(ACommandId);
  AEnabled:=AVisible;
  AChecked:=False;
end;

{ True when ALocation is a remote file above [Preview] RemoteAutoLoadKB and
  the user has not asked to load this very location.  The size comes from
  the Location cache (the folder listing seeded it): deciding costs no
  remote request. }
function TAFileManagerController.RemotePreviewDeferred(AView: Integer;
  const ALocation: string; out ASize, ALimit: Int64): Boolean;
var Info: TArosaFileInfo; L: TArosaFilteredListView; R: TArosaListRow; S: string;
begin
  Result:=False;
  ASize:=0;
  ALimit:=0;
  if FDescriptor<>nil then ALimit:=Int64(FDescriptor.IntValue('Preview','RemoteAutoLoadKB',0))*1024;
  if (AView<0) or (AView>1) or SameText(FForcePreviewLocation[AView],ALocation) then Exit;

  { LIST already returned the selected row's size.  Use that metadata rather
    than issuing a STAT merely to decide whether preview should download the
    file. This is especially important with RemoteAutoLoadKB=0, where the
    answer is normally "do not fetch" and no network round-trip is needed. }
  L:=ViewList(AView);
  if (L<>nil) and (L.SelectedIndex>=0) then
  begin
    R:=L.VisibleRowsView[L.SelectedIndex];
    if (R<>nil) and SameText(R.Tags,ALocation) then
    begin
      S:=R.SortKey['resource.size'];
      if (S<>'') and TryStrToInt64(S,ASize) then
        Exit((ALimit>0) and (ASize>ALimit));
    end;
  end;

  if (FLocations=nil) or not FLocations.GetInfo(ALocation,Info) then Exit;
  ASize:=Info.Size;
  Result:=(ALimit>0) and (Info.Size>ALimit);
end;

procedure TAFileManagerController.ForcePreview(AView: Integer);
var L: TArosaFilteredListView;
begin
  if (AView<0) or (AView>1) then Exit;
  L:=ViewList(AView);
  if (L=nil) or (L.SelectedIndex<0) then Exit;
  FForcePreviewLocation[AView]:=SelectedPath(AView,L.SelectedIndex);
  FDisplayedPreviewPath[AView]:='';
  Diagnostic('PREVIEW load requested view='+IntToStr(AView)+' location='+FForcePreviewLocation[AView]);
  UpdatePreview(AView);
end;

{ Bubble resolver: '@key' through the localization catalogue; '' for a
  missing key so the service reports it and applies its fallback. }
function TAFileManagerController.BubbleText(const AText: string): string;
begin
  if (AText<>'') and (AText[1]='@') then
    Result:=LocalText(Copy(AText,2,MaxInt),'')
  else
    Result:=AText;
end;

procedure TAFileManagerController.BindNativeHost(AHost: TArosaFormHost);
begin
  FNativeHost := AHost;
  if FNativeHost<>nil then
  begin
    { Standard window movement/resizing/snapping/minimize/zoom/depth are owned
      by the shared AROSA form host. AFileManager retains only its
      application-specific close and document/session behaviour. }
    FNativeHost.BindWindowFrame(FWindowFrame);
    FNativeHost.OnCloseRequest:=@NativeCloseRequested;
    FNativeHost.OnActivate:=@NativeActivated;
    FNativeHost.OnDeactivate:=@NativeDeactivated;
    Diagnostic('HOST bound window='+IntToHex(PtrUInt(FNativeHost.Window),
      SizeOf(Pointer)*2));
    ApplyWindowIcons;
    { 0.8.27.10: the application endpoint is served from the event loop:
      every pass advances its heartbeat and takes the requests that another
      launch or Foundation left there.  The loop wakes at least every
      WaitTimeoutMs (50 ms), so a request is seen within that time. }
    { Only the primary controller serves it: a workspace-screen controller
      (FWorkspaceSessionMode) closing on "quit" would close just that
      workspace. }
    if (not FWorkspaceSessionMode) and (FNativeHost.Application<>nil) and
       (FNativeHost.Application.Loop<>nil) and not FEndpointIdleAttached then
    begin
      FNativeHost.Application.Loop.AddIdleHandler(@EndpointIdle);
      FEndpointIdleAttached:=True;
    end;
    { 0.6.1.6 shutdown test hook.  AROSA_TEST_AUTOCLOSE_MS=n requests close
      after n ms through the SAME path as the close gadget;
      AROSA_TEST_PREVIEW=name first previews that file in the left pane, so
      a presentation is open at quit.  Environment only: launch arguments
      and normal runs are unaffected.  Used by tests/baseline. }
    FTestCloseAfterMs:=StrToQWordDef(Trim(GetEnvironmentVariable('AROSA_TEST_AUTOCLOSE_MS')),0);
    if (FTestCloseAfterMs>0) and (FNativeHost.Application<>nil) and
       (FNativeHost.Application.Loop<>nil) then
    begin
      FTestStartTick:=GetTickCount64;
      FTestPreviewDone:=False;
      FNativeHost.Application.Loop.AddIdleHandler(@TestAutoCloseIdle);
      Diagnostic('TEST autoclose armed ms='+IntToStr(FTestCloseAfterMs));
    end;
    { 0.6.1.3 Contextual Information Bubble Service.  AFileManager supplies
      only semantics (Hint / ContextTitle / ContextDescription, localized);
      AROSA owns timing, placement, rendering and dismissal. }
    if (FDescriptor=nil) or FDescriptor.BoolValue('Bubbles','Enabled',True) then
    begin
      if FWindowFrame<>nil then
        FNativeHost.Bubbles:=TArosaBubbleService.CreateService(FWindowFrame,FTheme,FFonts)
      else
        FNativeHost.Bubbles:=TArosaBubbleService.CreateService(FForm,FTheme,FFonts);
      FNativeHost.Bubbles.Resolver:=@BubbleText;
      ApplyBubbleConfiguration;
    end;
    if (FNativeHost.Application<>nil) and
       (FNativeHost.Application.Loop<>nil) then
    begin
      FNativeHost.Application.Loop.AddIdleHandler(@DocumentCloseIdle);
      FNativeHost.Application.Loop.AddIdleHandler(@PreviewIdle);
    end;
  end;
  FNativeDragging := False;
  FNativeDragMoved := False;
  FNativeSnapped := False;
  FNativePendingRestore := False;
  FNativeRestoreDragStart := ArosaEmptyRect;
  FNativeMaximized := False;
  FNativeCollapsed := False;
  FNativeRestoreBounds := ArosaEmptyRect;
end;

procedure TAFileManagerController.WindowNativeDrag(AZone: TArosaWindowHitZone;
  const APosition: TArosaPoint; AStarting, AEnding: Boolean);
const
  SnapMargin = 16;
var
  Current, Proposed, Desktop, Previous: TArosaRect;
  X, Y, L, T, R, B, DX, DY, DW, DH, SW, SH: Integer;
  AtLeft, AtRight, AtTop, AtBottom: Boolean;
begin
  if (FNativeHost = nil) or (FNativeHost.Window = ArosaNilHandle) or
     (FPlatform = nil) then Exit;
  Current := FPlatform.Windows.GetWindowBounds(FNativeHost.Window);
  if AStarting then
  begin
    FNativeDragging := True;
    FNativeDragMoved := False;
    FNativePendingRestore := (AZone = awhzTitle) and
      (not FNativeCollapsed) and (FNativeMaximized or FNativeSnapped) and
      (not ArosaRectIsEmpty(FNativeRestoreBounds));
    FNativePointerStart := ArosaPointRaw(
      Current.Left + APosition.X, Current.Top + APosition.Y);
    FNativeDragStart := Current;
    FNativeRestoreDragStart := FNativeRestoreBounds;
    FNativeLastPointer := FNativePointerStart;
    Exit;
  end;
  if not FNativeDragging then Exit;
  if AEnding then
  begin
    FNativeDragging := False;
    FNativePendingRestore := False;
    if not FNativeDragMoved or FNativeCollapsed or
       (AZone <> awhzTitle) then Exit;
    Desktop := FPlatform.Windows.GetDesktopBounds(FNativeHost.Window);
    if ArosaRectIsEmpty(Desktop) then Exit;
    L := ArosaCoordWhole(Desktop.Left);
    T := ArosaCoordWhole(Desktop.Top);
    SW := ArosaCoordWhole(ArosaRectWidth(Desktop));
    SH := ArosaCoordWhole(ArosaRectHeight(Desktop));
    X := ArosaCoordWhole(FNativeLastPointer.X);
    Y := ArosaCoordWhole(FNativeLastPointer.Y);
    AtLeft := X <= L + SnapMargin;
    AtRight := X >= L + SW - SnapMargin;
    AtTop := Y <= T + SnapMargin;
    AtBottom := Y >= T + SH - SnapMargin;
    if not (AtLeft or AtRight or AtTop or AtBottom) then Exit;
    if not FNativeSnapped then
      FNativeRestoreBounds := FNativeDragStart;
    { Corner priority: quarters, then left/right halves, then top/bottom halves.
      Maximization is reserved for title-bar double-click. }
    if AtLeft and AtTop then Proposed := ArosaRectXYWH(L,T,SW div 2,SH div 2)
    else if AtRight and AtTop then Proposed := ArosaRectXYWH(L+SW div 2,T,SW-SW div 2,SH div 2)
    else if AtLeft and AtBottom then Proposed := ArosaRectXYWH(L,T+SH div 2,SW div 2,SH-SH div 2)
    else if AtRight and AtBottom then Proposed := ArosaRectXYWH(L+SW div 2,T+SH div 2,SW-SW div 2,SH-SH div 2)
    else if AtLeft then Proposed := ArosaRectXYWH(L,T,SW div 2,SH)
    else if AtRight then Proposed := ArosaRectXYWH(L+SW div 2,T,SW-SW div 2,SH)
    else if AtTop then Proposed := ArosaRectXYWH(L,T,SW,SH div 2)
    else if AtBottom then Proposed := ArosaRectXYWH(L,T+SH div 2,SW,SH-SH div 2)
    else Exit;
    FNativeMaximized := False;
    FNativeSnapped := True;
    FPlatform.Windows.SetWindowBounds(FNativeHost.Window, Proposed);
    Exit;
  end;
  if FNativeMaximized and not FNativePendingRestore then Exit;
  if FNativeCollapsed and (AZone <> awhzTitle) then Exit;
  { Pointer is root/client relative, while window geometry is screen relative. }
  X := ArosaCoordWhole(Current.Left + APosition.X);
  Y := ArosaCoordWhole(Current.Top + APosition.Y);
  FNativeLastPointer := ArosaPointRaw(ArosaCoord(X), ArosaCoord(Y));
  if FNativePendingRestore then
  begin
    { A plain title click (including the first click of a double-click) must
      not restore. Only actual pointer motion initiates restore-and-drag. }
    if (Abs(X - ArosaCoordWhole(FNativePointerStart.X)) < 4) and
       (Abs(Y - ArosaCoordWhole(FNativePointerStart.Y)) < 4) then Exit;
    Previous := FNativeRestoreBounds;
    DW := ArosaCoordWhole(ArosaRectWidth(Previous));
    DH := ArosaCoordWhole(ArosaRectHeight(Previous));
    SW := ArosaCoordWhole(ArosaRectWidth(Current));
    if SW < 1 then SW := 1;
    L := X - (ArosaCoordWhole(APosition.X) * DW) div SW;
    T := Y - 14;
    Current := ArosaRectXYWH(L,T,DW,DH);
    FNativeMaximized := False;
    FNativeSnapped := False;
    FNativePendingRestore := False;
    FPlatform.Windows.SetWindowBounds(FNativeHost.Window, Current);
    FNativeDragStart := Current;
    FNativePointerStart := ArosaPointRaw(ArosaCoord(X),ArosaCoord(Y));
    FNativeDragMoved := True;
    Exit;
  end;
  DX := X - ArosaCoordWhole(FNativePointerStart.X);
  DY := Y - ArosaCoordWhole(FNativePointerStart.Y);
  if (DX = 0) and (DY = 0) then Exit;
  FNativeDragMoved := True;
  L := ArosaCoordWhole(FNativeDragStart.Left);
  T := ArosaCoordWhole(FNativeDragStart.Top);
  R := ArosaCoordWhole(FNativeDragStart.Right);
  B := ArosaCoordWhole(FNativeDragStart.Bottom);
  case AZone of
    awhzTitle: begin Inc(L,DX); Inc(R,DX); Inc(T,DY); Inc(B,DY); end;
    awhzLeft: Inc(L,DX);
    awhzRight: Inc(R,DX);
    awhzTop: Inc(T,DY);
    awhzBottom: Inc(B,DY);
    awhzTopLeft: begin Inc(L,DX); Inc(T,DY); end;
    awhzTopRight: begin Inc(R,DX); Inc(T,DY); end;
    awhzBottomLeft: begin Inc(L,DX); Inc(B,DY); end;
    awhzBottomRight: begin Inc(R,DX); Inc(B,DY); end;
  else Exit;
  end;
  if R-L < 320 then
    if AZone in [awhzLeft,awhzTopLeft,awhzBottomLeft] then L:=R-320
    else R:=L+320;
  if B-T < 180 then
    if AZone in [awhzTop,awhzTopLeft,awhzTopRight] then T:=B-180
    else B:=T+180;
  Proposed := ArosaRectXYWH(L,T,R-L,B-T);
  FPlatform.Windows.SetWindowBounds(FNativeHost.Window, Proposed);
  if FNativeCollapsed and (AZone = awhzTitle) and
     (not ArosaRectIsEmpty(FNativeRestoreDragStart)) then
    FNativeRestoreBounds := ArosaRectXYWH(
      ArosaCoordWhole(FNativeRestoreDragStart.Left) + DX,
      ArosaCoordWhole(FNativeRestoreDragStart.Top) + DY,
      ArosaCoordWhole(ArosaRectWidth(FNativeRestoreDragStart)),
      ArosaCoordWhole(ArosaRectHeight(FNativeRestoreDragStart)));
end;

procedure TAFileManagerController.WindowZoomRequested(ASender: TArosaControl);
var
  Desktop, Current: TArosaRect;
begin
  if (FNativeHost = nil) or (FNativeHost.Window = ArosaNilHandle) or
     (FPlatform = nil) then Exit;
  { Title-bar double-click raises the native window and toggles zoom. }
  FPlatform.Windows.BringWindowToFront(FNativeHost.Window);
  if FNativeCollapsed then WindowMinimizeRequested(ASender);
  if FNativeMaximized then
  begin
    FNativeMaximized := False;
    FNativeSnapped := False;
    if not ArosaRectIsEmpty(FNativeRestoreBounds) then
      FPlatform.Windows.SetWindowBounds(FNativeHost.Window, FNativeRestoreBounds);
  end
  else
  begin
    Desktop := FPlatform.Windows.GetDesktopBounds(FNativeHost.Window);
    if ArosaRectIsEmpty(Desktop) then Exit;
    Current := FPlatform.Windows.GetWindowBounds(FNativeHost.Window);
    FNativeRestoreBounds := Current;
    FNativeMaximized := True;
    FNativeSnapped := False;
    FPlatform.Windows.SetWindowBounds(FNativeHost.Window, Desktop);
  end;
end;

procedure TAFileManagerController.WindowMinimizeRequested(ASender: TArosaControl);
var
  Current: TArosaRect;
begin
  if (FNativeHost = nil) or (FNativeHost.Window = ArosaNilHandle) or
     (FPlatform = nil) then Exit;
  { Native compact-window fallback: do not hide the retained client frame.
    True Workbench iconification requires a separate native app-icon service. }
  if FNativeCollapsed then
  begin
    FNativeCollapsed := False;
    if not ArosaRectIsEmpty(FNativeRestoreBounds) then
      FPlatform.Windows.SetWindowBounds(FNativeHost.Window, FNativeRestoreBounds);
  end
  else
  begin
    Current := FPlatform.Windows.GetWindowBounds(FNativeHost.Window);
    if not FNativeMaximized then FNativeRestoreBounds := Current;
    FNativeMaximized := False;
    FNativeSnapped := False;
    FNativeCollapsed := True;
    FPlatform.Windows.SetWindowBounds(FNativeHost.Window,
      ArosaRectXYWH(ArosaCoordWhole(Current.Left), ArosaCoordWhole(Current.Top),
        380, 90));
  end;
end;

procedure TAFileManagerController.WindowActivateRequested(ASender: TArosaControl);
begin
  if (FNativeHost <> nil) and (FNativeHost.Window <> ArosaNilHandle) and
     (FPlatform <> nil) then
    FPlatform.Windows.BringWindowToFront(FNativeHost.Window);
end;

procedure TAFileManagerController.WindowDepthRequested(ASender: TArosaControl);
begin
  if (FNativeHost = nil) or (FNativeHost.Window = ArosaNilHandle) or
     (FPlatform = nil) then Exit;
  { Never infer depth from a previous gadget click. Read Intuition's current
    screen window list on EVERY click, including after external activation. }
  if FPlatform.Windows.IsWindowFront(FNativeHost.Window) then
    FPlatform.Windows.SendWindowToBack(FNativeHost.Window)
  else
    FPlatform.Windows.BringWindowToFront(FNativeHost.Window);
end;

procedure TAFileManagerController.WindowCloseRequested(ASender: TArosaControl);
begin
  RequestApplicationClose;
end;

procedure TAFileManagerController.NativeCloseRequested;
begin
  RequestApplicationClose;
end;

procedure TAFileManagerController.EndpointIdle(var AMoreWorkPending: Boolean);
var
  Requests: TArosaAppEndpointRequests;
  Source: string;
begin
  { Never reports more work: this handler must not keep the loop awake. }
  if AMoreWorkPending then ;
  ArosaAppEndpointBeat;
  Requests:=ArosaAppEndpointTakeRequests;
  Source:='endpoint';
  { Ctrl-C (Foundation "application stop", "exec task ... kill", or the
    Shell) is a request to close, handled exactly like the close gadget.
    The RTL no longer ends the program from inside file I/O for it. }
  if ArosaBreakPending(True) then
  begin
    Include(Requests,aaerQuit);
    Source:='break-signal';
  end;

  if aaerActivate in Requests then
  begin
    DiagnosticInfo('lifecycle request=activate source=endpoint instance='+
      ArosaCurrentTaskText);
    DiagnosticPump;
    if (FNativeHost<>nil) and (not FNativeHost.Closed) then
      FNativeHost.Activate;
  end;

  if aaerQuit in Requests then
  begin
    if FClosingApplication and FEndpointQuitRequested then Exit;
    FEndpointQuitRequested:=True;
    DiagnosticInfo('lifecycle request=quit source='+Source+' instance='+
      ArosaCurrentTaskText);
    DiagnosticPump;
    NativeCloseRequested;
  end;
end;

constructor TAFileManagerController.CreateManager(
  const APlatform: IArosaPlatform; AForm: TArosaForm; ATheme: TArosaTheme;
  AFonts: TArosaFontCache; const ADescriptorPath: string;
  const AInitialWorkspaceId: string);
var
  Header, Main, P, EditPanel: TArosaColumnPanel;
  HtmlProvider: TArosaHtmlPresentationProvider;
  WindowFrame: TArosaWindowFrame;
  Row: TArosaRowPanel;
  Page: TArosaTabPage;
  PreviewTabs: TArosaTabControl;
  L: TArosaLabel;
  B: TArosaButton;
  OperationDescriptor, ContextDescriptor: TStringList;
  StaticFontProvider: TArosaStaticFontProvider;
  ATransferProvider: TArosaATransferLocationProvider;
  CI: Integer;
  HasDualView, HasPreview, HasStatus: Boolean;
  InitialLeft, InitialRight: string;
  HistoryText, FavoritesText: AnsiString;
  ContentCachePath: string;
  StartupStartTick, StartupStageTick, StartupNowTick: QWord;

  procedure ControllerStage(const AStage: string);
  begin
    StartupNowTick:=GetTickCount64;
    { 0.8.27.10: the stage is also published in the application endpoint,
      so a later launch and Foundation can name the stage a stuck process
      is in even when its log is no longer being written. }
    ArosaAppEndpointSetStage('controller-'+AStage);
    DiagnosticInfo('startup stage=controller-'+AStage+
      ' delta_ms='+IntToStr(StartupNowTick-StartupStageTick)+
      ' total_ms='+IntToStr(StartupNowTick-StartupStartTick)+
      ' build='+ArosaBuildTag+' instance='+ArosaCurrentTaskText);
    StartupStageTick:=StartupNowTick;
    DiagnosticFlush;
  end;
begin
  StartupStartTick:=GetTickCount64;
  StartupStageTick:=StartupStartTick;
  ControllerStage('enter');
  inherited Create;
  FPlatform := APlatform;
  FForm := AForm;
  FTheme := ATheme;
  FLightTheme := ArosaCreateArosaLightTheme;
  FDarkTheme := ArosaCreateArosaDarkTheme;
  FFonts := AFonts;
  FPaths := TArosaPathService.CreateForPlatform(FPlatform);
  FFiles := TArosaFileService.CreateForPlatform(FPlatform, FPaths);
  ControllerStage('filesystem-ready');

  FFontService:=TArosaFontService.Create;
  {$IFDEF AROS}
  { The picker must list fonts that the normal AROS graphics path can
    actually open. AvailFonts includes installed bitmap and scaled outline
    faces, and marks scalable faces with AFF_SCALED. Raw .ttf files are still
    previewable as resources, but they do not enter the UI picker until AROS
    has installed/registered them as fonts. }
  FFontService.RegisterProvider(TArosaArosDiskfontProvider.Create);
  {$ENDIF}
  StaticFontProvider:=TArosaStaticFontProvider.CreateNamed('arosa-baseline');
  StaticFontProvider.AddFace('topaz',afkBitmap);
  FFontService.RegisterProvider(StaticFontProvider);
  {$IFNDEF AROS}
  FFontService.RegisterProvider(
    TArosaDirectoryFontProvider.CreateForDir('host-fonts','FONTS:'));
  {$ENDIF}
  ControllerStage('font-refresh-begin');
  FFontService.Refresh;
  ControllerStage('font-refresh-end');

  FLocations := TArosaLocationService.Create;
  FLocationChanges:=TArosaLocationChangeService.Create;
  FLocationChanges.Subscribe(@LocationChanged);
  FVirtualLocations:=nil;
  FWorkspaces:=TArosaWorkspaceService.Create;
  FWorkspacePrototypes:=TList.Create;
  FActiveWorkspaceId:=Trim(AInitialWorkspaceId);
  if FActiveWorkspaceId='' then FActiveWorkspaceId:='default';
  FWorkspaceProfilePath:='';
  FPendingDeleteWorkspaceId:='';
  FPendingEditWorkspaceId:='';
  FWorkspaceSessionMode:=not SameText(FActiveWorkspaceId,'default');
  FWorkspaceSessionClose:=nil;
  FWorkspaceNavigationOwner:=nil;
  FWorkspaceStatusSource:='afilemanager.'+
    IntToHex(PtrUInt(Self),SizeOf(Pointer)*2);
  FInstanceId:='';
  FInstanceLogPath:='';
  FInstanceLogStream:=nil;
  FInstanceLogPending:=nil;
  FInstanceLogLastFlush:=0;
  StartInstanceDiagnostics;
  ControllerStage('instance-diagnostics-ready');
  FLocations.RegisterProvider(TArosaLocalLocationProvider.CreateProvider(FPaths));
  { AROSA-first shell composition: applications borrow shell facilities rather
    than creating private process/association/datatype/sound/localization
    stacks or reaching into IArosaPlatform directly. }
  ControllerStage('shell-service-begin');
  FShellService := TArosaShellService.CreateForApplication(
    'arosa.application.afilemanager',IntToHex(PtrUInt(Self),SizeOf(Pointer)*2),
    FPlatform,FPaths,FFiles);
  ControllerStage('shell-service-end');
  { 0.7.1.0: ATransfer locations are a provider of the same logical location
    service used for local paths.  AFileManager contains no ATransfer protocol
    parsing or remote-navigation branch. }
  ATransferProvider:=TArosaATransferLocationProvider.CreateProvider(FShellService,FPaths);
  ATransferProvider.TraceComponentId:=AFM_ATRANSFER_TRACE_COMPONENT;
  FLocations.RegisterProvider(ATransferProvider);
  { 0.7.4.0: content is resolved above Location Service and below
    Presentation. Provider resources are materialised/cached here so existing
    presentation providers remain independent of transport. }
  FContent := TArosaContentService.CreateForLocations(FLocations,FPaths,FFiles);
  ControllerStage('service-settings-begin');
  ApplyServiceSettings;
  { 0.10.12.1: use a persistent resource-cache tier by default.  Location
    metadata remains in-process; materialised remote bytes survive redraws,
    helper processes and AFM restarts and are validated before reuse. }
  if Trim(FContent.CacheDirectory)='' then
  begin
    ContentCachePath:='AROSASTATE:AFileManager/Cache/Content';
    FFiles.CreateDirectoryTree(ContentCachePath);
    FContent.CacheDirectory:=ContentCachePath;
  end;
  ControllerStage('service-settings-end');
  FLocationResourceAccess := TArosaLocationResourceAccess.CreateForLocations(
    FLocations,FContent,FPaths,FFiles);
  FDataTypes := FShellService.DataTypes;
  FSoundService := FShellService.Sound;
  {$IFDEF AROS}
  { Native sound.datatype provider: WAV/8SVX and any other installed sound
    datatype are played through the AROS datatype/AHI path. }
  if FSoundService<>nil then
    FSoundService.RegisterProvider(TArosaArosDataTypeSoundProvider.Create);
  {$ENDIF}
  FLocalization := FShellService.Localization;
  FImageLoader := TArosaImageLoaderService.Create;
  FImageTransforms := TArosaImageTransformService.Create;
  FResources := TArosaResourceService.Create;
  FPresentationService:=TArosaPresentationService.CreateForContent(FContent,FResources,FDataTypes);
  ControllerStage('presentation-service-ready');
  { 0.5.110.55: real HTML and AmigaGuide renditions (both on TArosaHtmlView,
    validated by PresentationDriver).  They outrank the diagnostic probe,
    which remains registered for any other type it claims. }
  FPresentationService.RegisterProvider(TArosaAmigaGuidePresentationProvider.CreateProvider(FTheme,FFonts,FImageLoader));
  { 0.8.6.2: http/https links of a previewed page open in ABrowser }
  HtmlProvider:=TArosaHtmlPresentationProvider.CreateProvider(FTheme,FFonts,FImageLoader);
  HtmlProvider.OnWebLink:=@OpenWebLink;
  FPresentationService.RegisterProvider(HtmlProvider);
  { 0.6.1.5: images through DataTypes + Presentation Service.  The former
    apkImage branch in UpdatePreview remains only as the fallback for an
    image the provider declines, until this path is confirmed on AROS. }
  { 0.7.5.10: archive listings in portable code (ZIP, LHA, TAR) }
  FPresentationService.RegisterProvider(TArosaArchivePresentationProvider.CreateProvider(FTheme,FFonts));
  FLoadPreviewCmd[0]:=TAFMLoadPreviewCommand.CreateFor(Self,0);
  FLoadPreviewCmd[1]:=TAFMLoadPreviewCommand.CreateFor(Self,1);
  FPresentationService.RegisterProvider(TArosaImagePresentationProvider.CreateProvider(
    FTheme,FFonts,FImageLoader,FImageTransforms));
  { 0.7.33: TTF/OTF resource preview.  Metadata-only first; this same
    presentation becomes the visual harness for the outline-renderer phase. }
  FPresentationService.RegisterProvider(
    TArosaFontPresentationProvider.CreateProvider(FTheme,FFonts));
  FPresentationService.RegisterProvider(TArosaProbePresentationProvider.CreateProvider(FTheme,FFonts));
  FLeftPresentation:=nil; FRightPresentation:=nil;
  FResources.RegisterProvider(TArosaDirectFileResourceProvider.CreateProvider(
    'arosa.files.direct',100,FPaths,FFiles));
  FResources.RegisterMetadataProvider(TArosaBasicMetadataProvider.CreateProvider(FPaths,FFiles));
  FResources.RegisterMetadataProvider(TArosaImageMetadataProvider.CreateProvider(FImageLoader));
  { DataTypes-backed metadata: classify the file (picture/sound/music/archive/
    text/...) and surface its type, media type and attributes in the metadata
    panel. The extension/magic provider is the portable fallback; on AROS a
    datatypes.library provider registered ahead of it takes precedence. }
  FResources.RegisterMetadataProvider(
    TArosaDataTypeMetadataProvider.CreateForDataTypes(FDataTypes));
  { 0.7.33: format-specific TTF/OTF structure metadata through the same
    generic Resource Metadata chain used by SVG/IFF. }
  FResources.RegisterMetadataProvider(TArosaFontMetadataProvider.CreateProvider);
  FResources.RegisterMetadataProvider(TArosaSvgMetadataProvider.CreateProvider);
  { 0.8.31: what a file is - type, metadata, picture size - is answered by
    the knowledge worker of AROSAResourceService (its own process, with a
    classification cache).  The providers above answer only when it is not
    running, and for paths that mean something else in another process
    (PROGDIR:, relative paths, provider addresses). }
  ArosaInstallKnowledgeProbe(FResources);
  { Sound playback + an animated 3-bar visualizer that beats while a sound is
    playing. A native AHI/datatypes sound provider registered here would make
    it audible on AROS; without one, selecting audio still animates the bars as
    visual feedback. }
  FCurrentSound := nil;
  FAudioPath:='';
  FAudioDurationMS:=0;
  FAudioBasePositionMS:=0;
  FAudioRunTick:=0;
  FAudioLastTelemetryTick:=0;
  FAudioPreviewView:=0;
  FPendingNavigateActive:=False;
  FPendingNavigateView:=0;
  FPendingNavigatePath:='';
  FPendingExecLaunch:=False;
  FPendingExecTarget:='';
  FPendingExecWorkspace:='';
  FLastExecLaunchTarget:='';
  FLastExecLaunchTick:=0;
  FPreviewVisible := False;
  FMetadataVisible := False;
  FPreviewPreferredPlacement := 2;
  FPreviewPercent := 70;
  FPlacesDetailVisible := True;
  FPlacesActive := False;
  FPlacesDetailPercent := 70;
  FMetadataView := nil; FRightMetadataView := nil;
  FPlacesDetailSplit := nil; FPlacesDetailTabs := nil; FPlacesMetadata := nil;
  FMetadataPage := nil; FPreviewPage := nil;
  FRightPreviewPage := nil; FRightMetadataPage := nil;
  FMetadataTabs := nil; FRightMetadataTabs := nil;
  FListModeRadio := nil; FDetailsModeRadio := nil; FIconsModeRadio := nil; FWindowsModeRadio:=nil;
  FUpdatingToolbarState := False;
  FConsoleWrapButton:=nil;
  FConsoleColumnsButton:=nil;
  FConsoleColumnLessButton:=nil;
  FConsoleColumnMoreButton:=nil;
  FConsoleFontSmallerButton:=nil;
  FConsoleFontLargerButton:=nil;
  FCommandService := nil; FCommandTarget := nil; FMacroService := nil; FARexxService := nil; FConsole := nil;
  FShellSession := nil; FConsoles := TList.Create;
  FApplicationFrames := TArosaApplicationFrameService.CreateService;
  FMusicBars := nil;
  FRightMusicBars := nil;
  FLeftAudioHost:=nil; FRightAudioHost:=nil;
  FLeftAudioSummary:=nil; FRightAudioSummary:=nil;
  FLeftAudioPlayback:=nil; FRightAudioPlayback:=nil;
  FLeftAudioProgress:=nil; FRightAudioProgress:=nil;
  FLeftImageResource := nil;
  FRightImageResource := nil;
  FDocuments := TList.Create;
  FPendingCloseDocument:=nil;
  FDeferredCloseDocument:=nil;
  FClosingApplication:=False;
  FApplicationCloseQueued:=False;
  FDeferredCloseConsole:=nil;
  FConsoleCloseIdleAttached:=False;
  FApplicationCloseIdleAttached:=False;
  FDocumentTabs := nil;
  FUndoSources := TStringList.Create;
  FUndoDestinations := TStringList.Create;
  FRecentLocations := TStringList.Create;
  FFavorites := TStringList.Create;
  FFavorites.NameValueSeparator := '=';
  FShortcutService:=nil;
  FLauncherService:=nil;
  FNetworkLocations := TStringList.Create;
  FNetworkLocations.NameValueSeparator := '=';
  FNetworkDialog := nil;
  FEditingNetworkLocation := '';
  FListMenuBase := TStringList.Create;
  FListMenuBase.NameValueSeparator := '=';
  FShortcutBindings:=nil;
  FRecentFiles := TStringList.Create;
  FPlaceIconResources := TList.Create;
  FToolbarIconResources := TList.Create;
  FHistoryService := FShellService.History;
  FLeftNavigationHistory := FHistoryService.CreateChain('navigation.left',100);
  FRightNavigationHistory := FHistoryService.CreateChain('navigation.right',100);
  FOperationHistory := FShellService.OperationHistory;
  FResourceClipboard := FShellService.Clipboard;
  FSearchService := FShellService.Search;
  FResourceOperations := FShellService.Operations;
  if FResourceOperations<>nil then
    FResourceOperations.ResourceAccess:=FLocationResourceAccess;
  { Canonical command layer for the Console / ARexx / Macro operation tabs.
    A command target routes ids through the existing UI handler table. }
  FCommandService := TArosaCommandService.Create;
  FCommandTarget := TAFileManagerCommandTarget.CreateForController(Self);
  FCommandService.AppendTarget(FCommandTarget);
  FMacroService := TArosaMacroService.Create;
  FARexxService := TArosaARexxService.CreateForPort('AFILEMANAGER.1', FCommandService);
  FARexxService.RegisterVerb('REFRESH','view.refresh');
  FARexxService.RegisterVerb('UP','navigation.up');
  FARexxService.RegisterVerb('BACK','navigation.back');
  FARexxService.RegisterVerb('COPY','file.copy');
  FARexxService.RegisterVerb('PASTE','file.paste');
  FARexxService.RegisterVerb('DELETE','file.delete');
  FCommandHistory := TAFileManagerCommandHistory.CreateHistory(
    'PROGDIR:AFileManager.commands', 0);
  FCommandHistory.Load;
  FPendingInputKind := '';
  FPendingInputSource := '';
  FPendingInputView := 0;
  FDeleteConfirmationPending := False;
  FPendingEmptyTrash:=False;
  FPendingPermanentTrashDelete:=False;
  FSynchronizingLocationRefresh:=False;
  FConfirmDeletion := True;
  FShowThumbnails := True;
  FThumbnailSize := 16;
  FColumnOrder:=TStringList.Create;
  FVisibleColumns:=TStringList.Create;
  FDefaultSortColumn:='resource.name';
  FDefaultSortAscending:=True;
  FActiveThemeId := 'Dark';
  FActiveThemePackageId := 'default';
  FConfigurationDialog := nil;
  FConfigurationDialogNeedsRebuild := False;
  FHasFontConfigurationOverride:=False;
  FNameDialog := nil; FWorkspacePropertiesDialog := nil; FBackgroundFileDialog := nil;
  FWorkspaceRegistry:=nil; FWorkspaceRegistryPersistence:=nil;
  FWorkspaceModules:=nil; FWorkspaceModulesDialog:=nil; FWorkspaceRegistryPath:='';
  FInfoDialog := nil; FHelpSystem := nil;
  FDeleteDialog := nil;
  FInformationDialog := nil;
  FPermissionService := TArosaPermissionService.CreateForPlatform(FPlatform);
  FPermissionDialog := nil;
  FArchiveDialogMode := 0; FArchiveSourcePath := ''; FArchiveToOtherPane := False;
  FArchiveOverwriteDialog:=nil; FArchiveOverwriteApproved:=False;
  FOperationRequester:=nil; FPendingOpKind:=''; FPendingDest:='';
  FPendingItems:=TStringList.Create; FConflictSources:=TStringList.Create;
  FMoveToItems:=TStringList.Create; FLocationPickerPurpose:=''; FMoveToView:=0;
  FConflictDests:=TStringList.Create; FConflictIndex:=0; FUnplannedConflicts:=0;
  FConflictPlan:=nil;
  FNewFolderIcon:=True;
  FRemoteRole:=AROSA_ROLE_REMOTE;
  FDragSourceParents:=TStringList.Create; FDragParentsReady:=False;
  FDragVolumeDest:=''; FDragVolumeCrosses:=False;
  FDragSameVolume:='Move'; FDragOtherVolume:='Copy';
  FPendingDropItems:=TStringList.Create; FPendingDropDestination:=''; FPendingDropView:=0;
  FCollectOperationErrors:=False; FOperationErrors:=TStringList.Create;
  FPendingDeleteItems := TStringList.Create;
  FPendingDeleteView := 0;
  FSyncScrolling := False;
  FSyncWindows := False;
  FSyncingScroll := False;
  FSyncingSplitter := False;
  FRestoringHistory := False;
  FDescriptorBase := 'PROGDIR:';
  { 0.7.66.1.0.1: restore the registry-backed workspace-module manager. }
  FWorkspaceRegistryPath:=FDescriptorBase+'AFileManager.registry';
  FWorkspaceRegistry:=TArosaRegistry.Create;
  FWorkspaceRegistryPersistence:=TArosaPersistence.CreatePersistence(FFiles);
  if (FPaths<>nil) and FPaths.Exists(FWorkspaceRegistryPath) then
    FWorkspaceRegistryPersistence.LoadRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath,True);
  FWorkspaceModules:=TArosaWorkspaceModuleService.CreateService(FWorkspaceRegistry);
  FWorkspaceModules.SeedStandardModules;
  { Administration starts with the first usable administration tool unless
    the user has already recorded an explicit membership decision. }
  if not FWorkspaceRegistry.Contains('arosa.workspace.administration.modules',
      'arosa.application.asqlitemanager') then
  begin
    FWorkspaceModules.SetEnabled('administration','arosa.application.asqlitemanager',True);
    FWorkspaceRegistryPersistence.SaveRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath);
  end;
  { 0.8.6.1: the Font Manager joins Administration the first time it is
    seen.  A workspace where the user has since switched it off keeps that
    decision: only the absence of any recorded decision enables it. }
  if not FWorkspaceRegistry.Contains('arosa.workspace.administration.modules',
      'arosa.application.afontmanager') then
  begin
    FWorkspaceModules.SetEnabled('administration','arosa.application.afontmanager',True);
    FWorkspaceRegistryPersistence.SaveRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath);
  end;
  FHistoryPath := FDescriptorBase + 'AFileManager.workspace.'+
    FActiveWorkspaceId+'.history';
  FLayoutPath := FDescriptorBase + 'AFileManager.workspace.'+
    FActiveWorkspaceId+'.layout';
  FFavoritesPath := FDescriptorBase + 'AFileManager.workspace.'+
    FActiveWorkspaceId+'.favorites';

  { Only the default workspace imports the pre-workspace state files. Other
    workspaces start with their own independent state from first construction. }
  if (FFiles<>nil) and SameText(FActiveWorkspaceId,'default') then
  begin
    if not FFiles.ReadAllText(FHistoryPath,HistoryText) then
      if FFiles.ReadAllText(FDescriptorBase+'AFileManager.history',HistoryText) then
        FFiles.WriteAllText(FHistoryPath,HistoryText);
    if not FFiles.ReadAllText(FFavoritesPath,FavoritesText) then
      if FFiles.ReadAllText(FDescriptorBase+'AFileManager.favorites',FavoritesText) then
        FFiles.WriteAllText(FFavoritesPath,FavoritesText);
    if not FFiles.ReadAllText(FLayoutPath,HistoryText) then
      if FFiles.ReadAllText(FDescriptorBase+'AFileManager.layout',HistoryText) then
        FFiles.WriteAllText(FLayoutPath,HistoryText);
  end;
  LoadHistory;
  LoadFavorites;
  FShortcutService:=TArosaShortcutService.CreateService(FFiles,FPaths,
    TArosaShortcutService.WorkspaceStoragePath(FDescriptorBase,FActiveWorkspaceId),
    FActiveWorkspaceId);
  { Import the pre-service AFileManager desktop catalogue once, then all
    applications use the shared AROSA shortcut service and canonical file. }
  FShortcutService.MigrateLegacy(FDescriptorBase+'AFileManager.workspace.'+
    FActiveWorkspaceId+'.desktop');
  ControllerStage('desktop-shortcuts-begin');
  LoadDesktopShortcuts;
  ControllerStage('desktop-shortcuts-end');
  FLauncherService:=TArosaWorkspaceLauncherService.CreateService(FFiles,FPaths,
    TArosaWorkspaceLauncherService.WorkspaceStoragePath(FDescriptorBase,FActiveWorkspaceId),
    FActiveWorkspaceId);
  FLauncherService.Load;
  FStartMenuService:=TArosaShortcutService.CreateService(FFiles,FPaths,
    TArosaShortcutService.StartMenuStoragePath(FDescriptorBase,FActiveWorkspaceId),
    FActiveWorkspaceId);
  FStartMenuService.Load;
  FVolumes:=TStringList.Create;
  FVolumeNotices:=TStringList.Create;
  FNetworkLocationsPath := FDescriptorBase + 'AFileManager.network-locations';
  ControllerStage('network-locations-begin');
  LoadNetworkLocations;
  ControllerStage('network-locations-end');
  FContext := TAFileManagerContext.Create;
  FCapabilities := TArosaWindowCapabilityRegistry.Create;
  FDescriptor := TArosaWindowDescriptor.Create;
  ControllerStage('descriptor-load-begin');
  if Trim(ADescriptorPath)<>'' then
    FDescriptor.TryLoadFromFileWithUserConfiguration(
      ADescriptorPath,
      FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId))
  else
    FDescriptor.TryLoadFromFileWithUserConfiguration(
      FDescriptorBase+'AFileManager.window',
      FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId));
  { 0.15.0.2.2.0: live/minimal packages may place the authoritative release
    descriptor under Resources or beside the executable without the complete
    development descriptor tree.  Resolve those supported layouts before
    falling back to descriptor defaults; never show an unexplained empty
    AROSA frame merely because one packaging layout was used. }
  if not FDescriptor.Loaded then
    FDescriptor.TryLoadFromFileWithUserConfiguration(
      FDescriptorBase+'AFileManager.release.window',
      FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId));
  if not FDescriptor.Loaded then
    FDescriptor.TryLoadFromFileWithUserConfiguration(
      FDescriptorBase+'Resources/AFileManager.window',
      FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId));
  if not FDescriptor.Loaded then
    FDescriptor.TryLoadFromFileWithUserConfiguration(
      FDescriptorBase+'Resources/descriptors/AFileManager.release.window',
      FDescriptorBase+WorkspaceUserConfigurationPath(FActiveWorkspaceId));
  ControllerStage('descriptor-load-end');
  { 0.10.6: the Configuration Service's view goes over the profile file }
  ApplyServiceConfiguration;
  { Diagnostics are launch-controlled only.  Descriptors and user profiles
    must never silently enable debug/console output.  --trace is explicit. }
  FShortcutBindings:=FDescriptor.Section('Shortcuts');
  FShortcutBindings.NameValueSeparator:='=';

  FActiveThemePackageId:=Trim(FDescriptor.Value('Presentation','ThemePackage','default'));
  if FActiveThemePackageId='' then FActiveThemePackageId:='default';
  ControllerStage('localization-begin');
  LoadLocalization;
  ControllerStage('localization-end');
  ApplyThemeColourLayers;
  ApplyConfiguredFontsToTheme(FTheme);
  ApplyConfiguredFontsToTheme(FDarkTheme);
  ApplyConfiguredFontsToTheme(FLightTheme);
  { 0.7.5.4: stack for every program AFileManager starts (unzip, lha,
    ATransfer, AGet, APut, ...): [Processes] StackKB }
  if FDescriptor<>nil then
    ArosaSetChildProcessStack(LongWord(FDescriptor.IntValue('Processes','StackKB',512))*1024);
  Diagnostic('PROCESS child stack='+IntToStr(ArosaChildProcessStack div 1024)+' KB');
  Diagnostic('WINDOW descriptor='+FDescriptor.Path+' loaded='+BoolToStr(FDescriptor.Loaded,'TRUE','FALSE'));
  { 0.7.5.5: which window files were actually read (parents first) }
  Diagnostic('WINDOW chain: '+StringReplace(Trim(FDescriptor.Chain.Text),LineEnding,' > ',[rfReplaceAll]));
  ArosaTrace('WINDOW','descriptor='+FDescriptor.Path+' loaded='+BoolToStr(FDescriptor.Loaded,True));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
  FWindowDescriptor := FDescriptor.Section('Window');
  FGadgetDescriptor := FDescriptor.Section('Gadgets');
  FMenuDescriptor := FDescriptor.Section('Menu');
  FToolbarDescriptor := FDescriptor.Section('Toolbar');
  FFileDescriptor := FDescriptor.Section('AFileManager');
  FConfiguredLoggingEnabled:=FDescriptor.BoolValue('Diagnostics','Logging',True);
  FConfiguredLoggingLevel:=Trim(FDescriptor.Value('Diagnostics','Level','Info'));
  if FConfiguredLoggingLevel='' then FConfiguredLoggingLevel:='Info';
  if not DiagnosticCommandLineOverride then
    DiagnosticConfigure(FConfiguredLoggingEnabled,
      DiagnosticSeverityFromName(FConfiguredLoggingLevel,amsInfo),'descriptor/user-configuration');
  FLoggingEnabled:=DiagnosticLoggingEnabled;
  DiagnosticInfo('logging-request enabled='+BoolToStr(FLoggingEnabled,True)+
    ' level='+ArosaMessageSeverityName(DiagnosticRequestedSeverity));
  FTrashDirectory := DescriptorValue(FFileDescriptor,'TrashDirectory','SYS:Trash/AROSA');
  FConfirmDeletion := FDescriptor.BoolValue('AFileManager','ConfirmDeletion',True);
  { 0.10.6.2: what a plain drag does: Move, Copy or Ask }
  FDragSameVolume := AfmDragRule(FDescriptor.Value('FileOperations','DragSameVolume','Move'),'Move');
  FDragOtherVolume := AfmDragRule(FDescriptor.Value('FileOperations','DragOtherVolume','Copy'),'Copy');
  FShowThumbnails := FDescriptor.BoolValue('FileView','ShowThumbnails',True);
  LoadColumnConfigurationFromDescriptor;
  FThumbnailSize := FDescriptor.IntValue('FileView','ThumbnailSize',16);
  if FThumbnailSize<12 then FThumbnailSize:=12 else if FThumbnailSize>64 then FThumbnailSize:=64;
  FActiveThemeId := FDescriptor.Value('Presentation','Theme','Dark');
  if not SameText(FActiveThemeId,'Light') then FActiveThemeId:='Dark' else FActiveThemeId:='Light';
  FShowHiddenFiles := FDescriptor.BoolValue('CurrentLocation','ShowHiddenFiles',
    FDescriptor.BoolValue('AFileManager','ShowHiddenFiles',False));
  FFileIconSize:=FDescriptor.IntValue('FileView','IconSize',24);
  if FFileIconSize<12 then FFileIconSize:=12 else if FFileIconSize>96 then FFileIconSize:=96;
  FFileRowPadding:=FDescriptor.IntValue('FileView','RowPadding',3);
  if FFileRowPadding<0 then FFileRowPadding:=0 else if FFileRowPadding>24 then FFileRowPadding:=24;
  FFileIconTextGap:=FDescriptor.IntValue('FileView','IconTextGap',6);
  if FFileIconTextGap<0 then FFileIconTextGap:=0 else if FFileIconTextGap>48 then FFileIconTextGap:=48;
  Diagnostic('FILEVIEW icon='+IntToStr(FFileIconSize)+' row-padding='+IntToStr(FFileRowPadding)+
    ' icon-text-gap='+IntToStr(FFileIconTextGap));
  FPreviewVisible := FDescriptor.BoolValue('Visibility','Preview',False);
  FEditorRenditionVisible := FDescriptor.BoolValue('Editor','RenditionVisible',True);
  FMetadataVisible := FDescriptor.BoolValue('Visibility','Metadata',False);
  if SameText(FDescriptor.Value('Preview','Placement','Bottom'),'Right') then FPreviewPreferredPlacement:=1
  else FPreviewPreferredPlacement:=2;
  FPreviewPercent := StrToIntDef(FDescriptor.Value('Preview','ContentPercent','70'),70);
  FPlacesDetailVisible := FDescriptor.BoolValue('PlacesDetails','Visible',True);
  FPlacesDetailPercent := StrToIntDef(FDescriptor.Value('PlacesDetails','ContentPercent','70'),70);
  if FPlacesDetailPercent<10 then FPlacesDetailPercent:=10 else if FPlacesDetailPercent>90 then FPlacesDetailPercent:=90;
  if FPreviewPercent<10 then FPreviewPercent:=10 else if FPreviewPercent>90 then FPreviewPercent:=90;
  if SameText(FDescriptor.Value('CurrentLocation','ViewMode','Details'),'Windows') then FLeftViewMode:=3
  else if SameText(FDescriptor.Value('CurrentLocation','ViewMode','Details'),'Icons') then FLeftViewMode:=2
  else if SameText(FDescriptor.Value('CurrentLocation','ViewMode','Details'),'List') then FLeftViewMode:=0
  else FLeftViewMode:=1;
  if SameText(FDescriptor.Value('SecondaryLocation','ViewMode','Icons'),'Windows') then FRightViewMode:=3
  else if SameText(FDescriptor.Value('SecondaryLocation','ViewMode','Icons'),'Icons') then FRightViewMode:=2
  else if SameText(FDescriptor.Value('SecondaryLocation','ViewMode','Icons'),'List') then FRightViewMode:=0
  else FRightViewMode:=1;
  FResourceOperations.TrashDirectory := FTrashDirectory;
  if (FShellService<>nil) and (FShellService.Trash<>nil) then
  begin
    FShellService.Trash.FallbackDirectory:=FTrashDirectory;
    FShellService.Trash.ScopeId:=FActiveWorkspaceId;
  end;
  ControllerStage('workspaces-begin');
  LoadWorkspacesFromUserProfile;
  ControllerStage('workspaces-end');

  { AROSA desktop and logical catalogue locations are first-class Location
    Service resources, not hard-coded controls. }
  ControllerStage('virtual-locations-begin');
  FVirtualLocations:=TArosaVirtualLocationProvider.CreateProvider('arosa',300);
  FLocations.RegisterProvider(FVirtualLocations);
  RebuildVirtualLocations;
  ControllerStage('virtual-locations-end');

  FResourceOperations.OnError := @ResourceOperationError;
  FResourceOperations.OnConflict := @ResourceConflict;
  FWorkerService:=TArosaWorkerService.Create;
  FTaskRunner:=TArosaArosTaskRunner.Create;
  FEnumerationWorkerActive:=False;
  FEnumerationWorkerIdleAttached:=False;
  FEnumerationWorkerView:=0;
  FEnumerationWorkerPath:='';
  FEnumerationWorkerSyncOther:=False;
  FEnumerationWorkerGeneration:=0;
  FEnumerationWorkerTargetCPU:=-1;
  FEnumerationPending:=False;
  FEnumerationPendingPath:='';
  { Native CreateNewProc execution is disabled on AROS until a Pascal-runtime
    safe task bootstrap exists. Provider transfers use cooperative idle steps. }
  FWorkerService.UseNativeTask:=False;
  FWorkerService.OnSpawn:=nil;
  FTransferJob:=nil;
  FTransferLastProgress:=-1;
  FTransferIdleAttached:=False;
  FExternalTransferActive:=False;
  FExternalTransferJobPath:='';
  FExternalTransferResultPath:='';
  FExternalTransferStartedTick:=0;
  FExternalTransferPhase:='';
  FExternalTransferProgressPath:='';
  FExternalTransferCancelPath:='';
  FExternalTransferSawWorker:=False;
  FExternalTransferSerial:=0;
  FExternalTransferByteSerial:=0;
  FExternalTransferChangeTick:=0;
  FExternalTransferPollTick:=0;
  FExternalTransferCancelAsked:=False;
  FPreviewMenuButton := nil;
  FLeftPreviewPlacementApplied := -1;
  FRightPreviewPlacementApplied := -1;
  ControllerStage('workers-ready');
  FCapabilities.ConfigureFromDescriptor(FDescriptor);
  Diagnostic('WINDOW capabilities frame='+BoolToStr(FDescriptor.BoolValue('Capabilities','Frame',False),'TRUE','FALSE')+
    ' menu='+BoolToStr(FDescriptor.BoolValue('Capabilities','Menu',False),'TRUE','FALSE')+
    ' toolbar='+BoolToStr(FDescriptor.BoolValue('Capabilities','Toolbar',False),'TRUE','FALSE')+
    ' operations='+BoolToStr(FDescriptor.BoolValue('Capabilities','Operations',False) or
      FDescriptor.BoolValue('Capabilities','FileOperations',False),'TRUE','FALSE')+
    ' split='+BoolToStr(FDescriptor.BoolValue('Capabilities','SplitView',False),'TRUE','FALSE')+
    ' preview='+BoolToStr(FDescriptor.BoolValue('Capabilities','Preview',False),'TRUE','FALSE')+
    ' commandline='+BoolToStr(FDescriptor.BoolValue('Capabilities','CommandLine',False),'TRUE','FALSE'));
  ArosaTrace('WINDOW','capabilities frame='+BoolToStr(FDescriptor.BoolValue('Capabilities','Frame',False),True)+
    ' menu='+BoolToStr(FDescriptor.BoolValue('Capabilities','Menu',False),True)+
    ' toolbar='+BoolToStr(FDescriptor.BoolValue('Capabilities','Toolbar',False),True)+
    ' operations='+BoolToStr((FDescriptor.BoolValue('Capabilities','Operations',False) or
      FDescriptor.BoolValue('Capabilities','FileOperations',False)),True)+
    ' split='+BoolToStr(FDescriptor.BoolValue('Capabilities','SplitView',False),True)+
    ' preview='+BoolToStr(FDescriptor.BoolValue('Capabilities','Preview',False),True)+
    ' commandline='+BoolToStr(FDescriptor.BoolValue('Capabilities','CommandLine',False),True));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}

  FForm.Caption := LocalValue(DescriptorValue(FWindowDescriptor,'Title','@afilemanager_window_title'),'AFileManager') + ' ' + ArosaBuildTag;
  FForm.WindowBounds := ArosaRectXYWH(25,25,
    StrToIntDef(DescriptorValue(FWindowDescriptor,'Width','1100'),1100),
    StrToIntDef(DescriptorValue(FWindowDescriptor,'Height','700'),700));
  FForm.MinSize := ArosaSize(
    StrToIntDef(DescriptorValue(FWindowDescriptor,'MinWidth','760'),760),
    StrToIntDef(DescriptorValue(FWindowDescriptor,'MinHeight','470'),470));
  ControllerStage('fonts-acquire-begin');
  FCompactFont := FFonts.Acquire(FTheme.FontFor(afrUI));
  FFileFont := FFonts.Acquire(FTheme.FontFor(afrSmall));
  ControllerStage('fonts-acquire-end');

  { Reuse the framework's real retained window object as the application
    shell.  The native TArosaForm remains only the platform host; window
    chrome, menu/context menu, minimize/maximize and client ownership are
    supplied by TArosaWindowFrame. }
  FContentConsumer := TArosaContentConsumerFrame.CreateFrame(FTheme,FFonts,
    LocalValue(DescriptorValue(FWindowDescriptor,'Title','@afilemanager_window_title'),'AFileManager') + ' ' + ArosaBuildTag);
  WindowFrame := FContentConsumer.WindowFrame;
  FWindowFrame := WindowFrame;
  WindowFrame.DarkTheme := FDarkTheme;
  WindowFrame.LightTheme := FLightTheme;
  WindowFrame.ApplyDescriptor(FDescriptor);
  { AROS native Intuition window supplies the actual window decorations.
    Keep AROSA's burger and navigation as an application command strip. }
  WindowFrame.NativeDecorations := False;
  { ApplyDescriptor retains canonical descriptor values.  Resolve the visible
    frame title through the application language catalogue before painting. }
  WindowFrame.Title := LocalValue(
    DescriptorValue(FWindowDescriptor,'Title','@afilemanager_window_title'),
    'AFileManager') + ' ' + ArosaBuildTag;
  WindowFrame.SetConstraintWidth(asmStar, ArosaCoord(1));
  WindowFrame.SetConstraintHeight(asmStar, ArosaCoord(1));
  FForm.AddVisual(WindowFrame);
  ControllerStage('window-frame-ready');


  { AFileManager is always independently closeable.  Generic AROSA forms may
    deliberately omit a close gadget, but when AFileManager has no usable
    descriptor it supplies its own minimal AROSA close gadget rather than
    leaving an inescapable bare window. }
  if not FDescriptor.Loaded then
  begin
    { Continue with the built-in baseline defaults instead of returning with
      only a title frame.  This keeps AFileManager usable even when optional
      descriptor resources are incomplete and makes deployment faults visible
      in diagnostics rather than as a blank application window. }
    FForm.Caption := 'AFileManager ' + ArosaBuildTag;
    WindowFrame.Title := 'AFileManager ' + ArosaBuildTag;
    WindowFrame.CloseGadget.Visible := True;
    WindowFrame.OnCloseRequest := @WindowCloseRequested;
    DiagnosticWarning('WINDOW descriptor unavailable; using built-in baseline defaults');
  end;

  if FDescriptor.BoolValue('Capabilities','Menu',False) then
  begin
    { Compact navigation commands live in the standard window title-command
        slot so every descriptor can expose them without synthesizing a toolbar. }
      FNavigationTitleBar := TArosaRowPanel.Create;
      FNavigationTitleBar.Spacing := ArosaCoord(1);
      FNavigationTitleBar.SetConstraintWidth(asmFixed,ArosaCoord(135));
      FNavigationTitleBar.SetConstraintHeight(asmFixed,ArosaCoord(24));
      B := NewButton(FNavigationTitleBar,'<',LocalText('afilemanager_hint_back','Back'),@BackClick,26);
      B.SetConstraintHeight(asmFixed,ArosaCoord(22));
      ApplyButtonIcon(B,'WindowIcons','Navigation.Back',26);
      B := NewButton(FNavigationTitleBar,'^',LocalText('afilemanager_hint_up','Parent location'),@UpClick,26);
      B.SetConstraintHeight(asmFixed,ArosaCoord(22));
      ApplyButtonIcon(B,'WindowIcons','Navigation.Up',26);
      B := NewButton(FNavigationTitleBar,'>',LocalText('afilemanager_hint_forward','Forward'),@ForwardClick,26);
      B.SetConstraintHeight(asmFixed,ArosaCoord(22));
      ApplyButtonIcon(B,'WindowIcons','Navigation.Forward',26);
      B := NewButton(FNavigationTitleBar,'H',LocalText('afilemanager_hint_home','Home location'),@HomeClick,26);
      B.SetConstraintHeight(asmFixed,ArosaCoord(22));
      ApplyButtonIcon(B,'WindowIcons','Navigation.Home',26);
      B := NewButton(FNavigationTitleBar,'><',LocalText('afilemanager_action_swap_views','Swap views'),@SwapViewsClick,26);
      B.SetConstraintHeight(asmFixed,ArosaCoord(22));
      ApplyButtonIcon(B,'WindowIcons','View.Swap',26);
      WindowFrame.TitleCommandContent := FNavigationTitleBar;
  end;

  { Menu content is generated from the consolidated [Menu] section. }
  if FMenuDescriptor.Count > 0 then
  begin
    { The burger is a compact command popup, not another document tab strip. }
    FMenuPanel := TArosaRowPanel.Create;
    FMenuPanel.Spacing := ArosaCoord(1);
    FMenuPanel.SetConstraintWidth(asmFixed,ArosaCoord(150));
    FMenuPanel.SetConstraintHeight(asmFixed,ArosaCoord(330));
    FMenuPanel.ZOrder := 10010;
    FMenuRootPanel := TArosaColumnPanel.Create;
    FMenuRootPanel.Spacing := ArosaCoord(0);
    FMenuRootPanel.SetConstraintWidth(asmFixed,ArosaCoord(149));
    FMenuSubPanel := TArosaColumnPanel.Create;
    FMenuSubPanel.Spacing := ArosaCoord(0);
    FMenuSubPanel.SetConstraintWidth(asmFixed,ArosaCoord(149));
    FMenuSubPanel.Visible := False;
    FMenuPanel.AddVisual(FMenuRootPanel);
    FMenuPanel.AddVisual(FMenuSubPanel);
    WindowFrame.MenuContent := FMenuPanel;
    WindowFrame.OnMenuOpening := @FrameMenuOpening;
    BuildRootMenu;
  end;

  { Toolbar content exists only when the descriptor declares commands. }
  if FToolbarDescriptor.Count > 0 then
  begin
    FToolbarTabs := TArosaTabControl.Create;
    StyleCommandTabs(FToolbarTabs);
    FToolbarTabs.SetConstraintHeight(asmFixed, ArosaCoord(72));
    FToolbarTabs.ZOrder := 500;
    WindowFrame.ToolbarContent := FToolbarTabs;
    BuildCommandTabs(FToolbarTabs,FToolbarDescriptor,'NAVIGATION');
  end;

  ControllerStage('commands-ready');
  HasDualView := FDescriptor.BoolValue('Capabilities','SplitView',False);
  HasPreview := FDescriptor.BoolValue('Capabilities','Preview',False);
  HasStatus := FDescriptor.BoolValue('Capabilities','Status',False);

  { AFileManager baseline content is always a places pane plus one current
    location pane.  DualView is a separate optional capability and never
    controls whether the places/current-location splitter exists. }
  Main := TArosaColumnPanel.Create;
  Main.Spacing := ArosaCoord(0);
  Main.SetConstraintHeight(asmStar, ArosaCoord(1));
  FPrimaryContentSurface:=FContentConsumer.AddContent(
    'arosa.application.afilemanager.content.files','Files',Main);
  { This is the application's permanent primary surface. The outer generic
    content-consumer tab must never destroy the entire AFileManager client
    tree through its Close tab command. Document/editor/Console tabs are
    managed by FDocumentTabs below. }
  FPrimaryContentSurface.Closable:=False;
  { AFileManager owns exactly one outer ContentConsumer surface.  Its real
    document model is the inner Files / Console / Editor tab host below.
    Showing both tab strips produces two stacked "Files" tabs and makes the
    outer surface look like a document.  Keep the outer surface semantics but
    collapse its header; only FDocumentTabs is user-visible/interactive. }
  if (FContentConsumer<>nil) and (FContentConsumer.Tabs<>nil) then
  begin
    FContentConsumer.Tabs.HeaderHeight:=ArosaCoord(0);
    FContentConsumer.Tabs.OnContextRequest:=nil;
  end;

  FPlacesSplit := TArosaSplitterHost.Create;
  FPlacesSplit.Orientation := aorHorizontal;
  FPlacesSplit.DividerThickness := ArosaCoord(8);
  FPlacesSplit.DividerRole := 'Border';
  FPlacesSplit.MinFirst := ArosaCoord(StrToIntDef(FDescriptor.Value('Panel.Places','MinimumWidth','120'),120));
  FPlacesSplit.MinSecond := ArosaCoord(StrToIntDef(FDescriptor.Value('Panel.CurrentLocation','MinimumWidth','240'),240));
  FPlacesSplit.SetDividerPosition(ArosaCoord(StrToIntDef(FDescriptor.Value('Panel.Places','Width','220'),220)));
  LoadLayout;
  FPlacesSplit.SetConstraintHeight(asmStar, ArosaCoord(1));
  { Reuse the AIDEa port's AROSA document-host pattern: a persistent Files
    page followed by independent editable document pages. }
  FDocumentTabs := TArosaTabControl.Create;
  StyleCommandTabs(FDocumentTabs);
  FDocumentTabs.OnChange:=@DocumentTabChanged;
  FDocumentTabs.OnContextRequest:=@DocumentTabContextRequested;
  FDocumentTabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  FDocumentTabs.AddPage(LocalText('afilemanager_tab_files','Files'),FPlacesSplit);

  { The inner document tab strip owns its own popup. The outer
    TArosaContentConsumerFrame popup refers to the whole primary content
    surface and is intentionally not reused here. }
  FDocumentTabMenu:=TArosaContentTabPopup.Create;
  FDocumentTabMenu.Spacing:=ArosaCoord(1);
  FDocumentTabMenu.SetConstraintWidth(asmFixed,ArosaCoord(150));
  FDocumentTabMenu.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FDocumentTabMenu.Visible:=False;
  FDocumentTabMenu.ZOrder:=10030;
  FDocumentTabCloseButton:=NewButton(FDocumentTabMenu,
    LocalText('arosa_content_tab_close','Close tab'),'Close the selected document or console tab',
    @DocumentTabCloseClick,148);
  FDocumentTabCloseButton.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FWindowFrame.AddVisual(FDocumentTabMenu);
  FActiveEnvironment:='Files';
  Main.AddVisual(FDocumentTabs);

  P := TArosaColumnPanel.Create;
  FPlacesPanel := P;
  P.Spacing := ArosaCoord(4);
  L := TArosaLabel.CreateControl(FTheme, FFonts);
  L.Text := LocalText('afilemanager_places','Places');
  L.FontFamily := FCompactFont.Description.Family;
  L.FontSize := FCompactFont.Description.SizePoints;
  L.SetConstraintHeight(asmFixed, ArosaCoord(21));
  P.AddVisual(L);
  Row := TArosaRowPanel.Create;
  Row.Spacing := ArosaCoord(3);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(22));
  L := TArosaLabel.CreateControl(FTheme,FFonts);
  L.Text := LocalText('afilemanager_filter','Filter:');
  L.FontFamily := FCompactFont.Description.Family;
  L.FontSize := FCompactFont.Description.SizePoints;
  L.SetConstraintWidth(asmFixed,ArosaCoord(58));
  Row.AddVisual(L);
  FPlacesFilter := TArosaTextBox.CreateControl(FTheme, FFonts);
  FPlacesFilter.Hint := LocalText('afilemanager_hint_filter_places','Type text to filter locations while preserving their group path.');
  FPlacesFilter.FontFamily := FCompactFont.Description.Family;
  FPlacesFilter.FontSize := FCompactFont.Description.SizePoints;
  FPlacesFilter.SetConstraintWidth(asmStar,ArosaCoord(1));
  FPlacesFilter.SetConstraintHeight(asmFixed,ArosaCoord(21));
  FPlacesFilter.OnChange := @PlacesFilterChanged;
  Row.AddVisual(FPlacesFilter);
  B := NewButton(Row,'-',LocalText('afilemanager_hint_clear_places_filter','Clear Places filter'),@ClearPlacesFilterClick,24);
  ApplyButtonIcon(B,'WindowIcons','Field.Clear',24);
  B.SetConstraintHeight(asmFixed,ArosaCoord(21));
  P.AddVisual(Row);
  FAssignments := TArosaFilteredTreeView.CreateControl(FTheme, FFonts);
  FAssignments.IconSize:=ArosaCoord(FDescriptor.IntValue('Places','IconSize',24));
  FAssignments.IconBorderVisible:=FDescriptor.BoolValue('Places','IconBorder',False);
  FAssignments.FilterHint := LocalText('afilemanager_hint_filter_places','Type text to filter locations while preserving their group path.');
  FAssignments.FontFamily := FCompactFont.Description.Family;
  FAssignments.FontSize := FCompactFont.Description.SizePoints;
  FAssignments.Hint := LocalText('afilemanager_hint_places','Select a location group or location to open it.');
  FAssignments.OnSelect := @AssignmentActivated;
  { Places context menu is wired after the tree exists; the menu itself is
    built from [PlacesMenu] (or built-in defaults) in BuildPlacesContextMenu. }
  FAssignments.SetConstraintHeight(asmStar, ArosaCoord(1));
  FPlacesDetailSplit:=TArosaSplitterHost.Create;
  FPlacesDetailSplit.Orientation:=aorVertical;
  FPlacesDetailSplit.DividerThickness:=ArosaCoord(6);
  FPlacesDetailSplit.DividerRole:='Border';
  FPlacesDetailSplit.MinFirst:=ArosaCoord(100);
  FPlacesDetailSplit.MinSecond:=ArosaCoord(90);
  FPlacesDetailSplit.SetInitialPercent(FPlacesDetailPercent);
  FPlacesDetailSplit.OnDividerChanged:=@PreviewSplitterChanged;
  FPlacesDetailSplit.SetConstraintHeight(asmStar,ArosaCoord(1));
  FPlacesDetailTabs:=TArosaTabControl.Create;
  StyleCommandTabs(FPlacesDetailTabs);
  FPlacesDetailTabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  FPlacesMetadata:=TArosaMetadataView.CreateControl(FTheme,FFonts);
  FPlacesMetadata.CaptionResolver:=@MetadataCaption;
  FPlacesDetailTabs.AddPage('Properties',FPlacesMetadata);
  EditPanel:=TArosaColumnPanel.Create; EditPanel.Spacing:=ArosaCoord(4);
  B:=NewButton(EditPanel,'Edit network location...', 'Edit the selected network location', @EditSelectedPlace, 170);
  FPlacesDetailTabs.AddPage('Edit',EditPanel);
  FPlacesDetailSplit.SetPanes(FAssignments,FPlacesDetailTabs);
  FPlacesDetailTabs.Visible:=FPlacesDetailVisible;
  P.AddVisual(FPlacesDetailSplit);
  LoadLayout; { restore Places detail visibility/share now that its splitter exists }
  ControllerStage('places-ready');
  BuildPlacesContextMenu;

  FLeftColumn := TArosaColumnPanel.Create;
  FLeftColumn.Spacing := ArosaCoord(3);
  FLeftBrowserColumn := TArosaColumnPanel.Create;
  FLeftBrowserColumn.Spacing := ArosaCoord(3);
  FLeftPreviewSplit := TArosaSplitterHost.Create;
  FLeftPreviewSplit.OnDividerChanged := @PreviewSplitterChanged;
  FLeftTitle := TArosaLabel.CreateControl(FTheme, FFonts);
  FLeftTitle.FontFamily := FCompactFont.Description.Family;
  FLeftTitle.FontSize := FCompactFont.Description.SizePoints;
  FLeftTitle.SetConstraintHeight(asmFixed, ArosaCoord(21));
  FLeftPath := TArosaTextBox.CreateControl(FTheme, FFonts);
  FLeftPath.Hint := LocalText('afilemanager_hint_primary_path','Current location. Enter a path and press Enter.');
  FLeftPath.FontFamily := FFileFont.Description.Family;
  FLeftPath.FontSize := FFileFont.Description.SizePoints;
  FLeftPath.SetConstraintHeight(asmFixed, ArosaCoord(25));
  FLeftCrumbs := TArosaBreadcrumbBar.CreateBar(FTheme, FFonts);
  FLeftCrumbs.Hint := LocalText('afilemanager_hint_breadcrumbs','Click a folder to open it; click the empty area to type a path.');
  FLeftCrumbs.FontFamily := FFileFont.Description.Family;
  FLeftCrumbs.FontSize := FFileFont.Description.SizePoints;
  FLeftCrumbs.SetConstraintHeight(asmFixed, ArosaCoord(25));
  FLeftCrumbs.OnNavigate := @LeftCrumbNavigate;
  FLeftCrumbs.OnEditRequest := @LeftCrumbEdit;
  FLeftPath.OnAccept := @LeftPathEnter;
  FLeftPath.Visible := False;
  FLeftBrowserColumn.AddVisual(FLeftCrumbs);
  FLeftBrowserColumn.AddVisual(FLeftPath);
  Row := TArosaRowPanel.Create;
  Row.Spacing := ArosaCoord(4);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(25));
  L := TArosaLabel.CreateControl(FTheme,FFonts);
  L.Text := LocalText('afilemanager_filter','Filter:');
  L.FontFamily := FCompactFont.Description.Family;
  L.FontSize := FCompactFont.Description.SizePoints;
  L.SetConstraintWidth(asmFixed,ArosaCoord(52));
  Row.AddVisual(L);
  FLeftFilter := TArosaTextBox.CreateControl(FTheme, FFonts);
  FLeftFilter.Hint := LocalText('afilemanager_hint_filter_primary','Type text to filter the current resource collection.');
  FLeftFilter.FontFamily := FFileFont.Description.Family;
  FLeftFilter.FontSize := FFileFont.Description.SizePoints;
  FLeftFilter.SetConstraintWidth(asmFixed,ArosaCoord(150));
  FLeftFilter.SetConstraintHeight(asmFixed, ArosaCoord(23));
  FLeftFilter.OnChange := @LeftFilterChanged;
  Row.AddVisual(FLeftFilter);
  FLeftClearFilter := NewButton(Row,'-',LocalText('afilemanager_hint_clear_filter','Clear filter'),@ClearLeftFilterClick,22);
  ApplyButtonIcon(FLeftClearFilter,'WindowIcons','Field.Clear',22);
  L := TArosaLabel.CreateControl(FTheme,FFonts);
  L.Text := LocalText('afilemanager_search','Search:');
  L.FontFamily := FCompactFont.Description.Family;
  L.FontSize := FCompactFont.Description.SizePoints;
  L.SetConstraintWidth(asmFixed,ArosaCoord(58));
  Row.AddVisual(L);
  FLeftSearch := TArosaTextBox.CreateControl(FTheme, FFonts);
  FLeftSearch.Hint := LocalText('afilemanager_hint_search_primary','AROS/Amiga pattern search, for example #?.pas or (readme|#?.txt).');
  FLeftSearch.FontFamily := FFileFont.Description.Family;
  FLeftSearch.FontSize := FFileFont.Description.SizePoints;
  FLeftSearch.SetConstraintWidth(asmStar,ArosaCoord(1));
  FLeftSearch.SetConstraintHeight(asmFixed,ArosaCoord(23));
  FLeftSearch.OnAccept := @LeftSearchChanged;
  Row.AddVisual(FLeftSearch);
  FLeftClearSearch := NewButton(Row,'-',LocalText('afilemanager_hint_clear_search','Clear search'),@ClearLeftSearchClick,22);
  ApplyButtonIcon(FLeftClearSearch,'WindowIcons','Field.Clear',22);
  FLeftBrowserColumn.AddVisual(Row);
  FLeftColumns := nil;
  FLeftList := TArosaFilteredListView.CreateControl(FTheme, FFonts);
  FLeftList.FontFamily := FFileFont.Description.Family;
  FLeftList.FontSize := FFileFont.Description.SizePoints;
  FLeftList.SelectionMode := alsMultiple;
  FLeftList.OnSelect := @LeftSelected;
  ConfigureDetailsColumns(FLeftList);
  FLeftList.OnSortChanged := @ListSortChanged;
  FLeftList.OnActivate := @LeftActivated;
  FLeftList.OnDragBegin := @ResourceDragBegin;
  FLeftList.OnDragEnd := @ResourceDragEnd;
  FLeftList.OnDragMove := @ResourceDragMove;
  FLeftList.OnDragFinished := @ResourceDragFinished;
  { [DragDrop] Feedback=false in the window descriptor (or its user overlay)
    switches the drag visuals off without touching drag and drop itself. }
  FLeftList.DragFeedback := not SameText(Trim(
    FDescriptor.Value('DragDrop','Feedback','true')),'false');
  FNewFolderIcon := not SameText(Trim(
    FDescriptor.Value('Files','NewFolderIcon','true')),'false');
  FRemoteRole := Trim(FDescriptor.Value('Panes','RemoteRole',AROSA_ROLE_REMOTE));
  if SameText(FRemoteRole,'none') then FRemoteRole:='';
  FLeftList.OnDeleteRequest := @DeleteClick;
  FLeftList.OnShortcut := @ListShortcut;
  FLeftList.OnUndoRequest := @UndoClick;
  FLeftList.OnCopyRequest := @CopyClick;
  FLeftList.OnCutRequest := @CutClick;
  FLeftList.OnPasteRequest := @PasteClick;
  FLeftList.OnPointerDown := @ListPointerDown;
  FLeftList.OnContextMenuOpening := @ListContextMenuOpening;
  if FDescriptor.BoolValue('Capabilities','ContextMenu',False) then
  begin
    FLeftList.OnContextCommand := @ResourceContextCommand;
    FLeftList.OnContextCommandIcon := @ContextCommandIcon;
    FLeftList.OnContextCommandEnabled := @ResourceContextCommandEnabled;
    FLeftList.OnContextCommandShortcut := @ResourceContextCommandShortcut;
    FLeftList.OnDeleteRequest := @DeleteClick;
  FLeftList.OnShortcut := @ListShortcut;
    FLeftList.OnUndoRequest := @UndoClick;
    FLeftList.OnCopyRequest := @CopyClick;
    FLeftList.OnCutRequest := @CutClick;
    FLeftList.OnPasteRequest := @PasteClick;
    ContextDescriptor:=FDescriptor.MenuSection('ContextMenu');
    try
      for CI:=0 to ContextDescriptor.Count-1 do
        ContextDescriptor.ValueFromIndex[CI]:=LocalValue(ContextDescriptor.ValueFromIndex[CI],ContextDescriptor.Names[CI]);
      ComposeResourceContextMenu(ContextDescriptor);
      FListMenuBase.Assign(ContextDescriptor);
      FLeftList.SetContextMenuItems(ContextDescriptor);
    finally ContextDescriptor.Free; end;
  end;
  FLeftList.SetConstraintHeight(asmStar, ArosaCoord(1));
  FLeftBrowserColumn.AddVisual(FLeftList);
  FLeftBrowserColumn.AddVisual(FLeftTitle);
  FLeftPreview := TArosaEditor.CreateControl(FTheme, FFonts);
  FLeftPreview.Clipboard:=FPlatform.Clipboard;
  { Preview stays read-only; document tabs own Save. }
  FLeftPreview.ReadOnly := True;
  FLeftPreview.Multiline := True;
  FLeftPreview.Highlighting := True;
  FLeftPreview.ShowLineNumbers := False;
  FLeftPreview.MenuWordWrap := LocalText('arosa_editor_word_wrap','Word wrap');
  FLeftPreview.MenuLineNumbers := LocalText('arosa_editor_line_numbers','Line numbers');
  FLeftPreview.MenuSearch := LocalText('arosa_editor_search','Find');
  FLeftPreview.MenuReplace := LocalText('arosa_editor_replace','Replace');
  FLeftPreview.OnCommandIcon:=@ContextCommandIcon;
  FLeftPreview.MenuGoToLine := LocalText('arosa_editor_go_to_line','Go to line');
  FLeftPreview.MenuPrevious := LocalText('arosa_editor_previous','Previous');
  FLeftPreview.MenuNext := LocalText('arosa_editor_next','Next');
  FLeftPreview.MenuFromCursor := LocalText('arosa_editor_from_cursor','from cursor');
  FLeftPreview.MenuNoMatches := LocalText('arosa_editor_no_matches','No matches');
  FLeftPreview.MenuHighlighting := LocalText('arosa_editor_highlighting','Highlighting');
  FLeftPreview.MenuCopy := LocalText('arosa_editor_copy','Copy');
  FLeftPreview.MenuSelectAll := LocalText('arosa_editor_select_all','Select all');
  FLeftPreview.Text := LocalText('afilemanager_preview_empty','Preview: no item selected');
  FLeftPreview.ReadOnly := True;
  FLeftPreview.Multiline := True;
  FLeftPreview.FontFamily := FCompactFont.Description.Family;
  FLeftPreview.FontSize := FCompactFont.Description.SizePoints;
  FLeftPreview.SetConstraintHeight(asmStar, ArosaCoord(1));
  FLeftPreview.Visible := True;
  FLeftImagePreview := TArosaImageBox.CreateControl(FTheme, FFonts);
  FLeftImagePreview.StretchMode := aismFit;
  FLeftImagePreview.OnTransform := @ImageTransformRequested;
  FLeftImagePreview.AltText := LocalText('afilemanager_preview_image','Image preview');
  FLeftImagePreview.SetConstraintHeight(asmStar, ArosaCoord(1));
  FLeftImagePreview.Visible := False;
  FLeftPreviewHost := TArosaColumnPanel.Create;
  FLeftPreviewHost.Spacing := ArosaCoord(0);
  FLeftPreviewHost.SetConstraintHeight(asmStar, ArosaCoord(1));
  FLeftPreviewHost.Visible := HasPreview and
    (FDescriptor.BoolValue('Visibility','Preview',False) or
     FDescriptor.BoolValue('Visibility','Metadata',False));
  PreviewTabs := TArosaTabControl.Create;
  StyleCommandTabs(PreviewTabs);
  PreviewTabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  Page := NewPage(PreviewTabs,LocalText('afilemanager_tab_preview','Preview'));
  FPreviewPage := Page;
  FLeftCommandBar := NewCommandBar;
  Page.AddVisual(FLeftCommandBar);
  FLeftAudioHost:=TArosaColumnPanel.Create;
  FLeftAudioHost.Spacing:=ArosaCoord(4);
  FLeftAudioHost.SetConstraintHeight(asmStar,ArosaCoord(1));
  FLeftAudioHost.Visible:=False;
  FLeftAudioSummary:=TArosaLabel.CreateControl(FTheme,FFonts);
  FLeftAudioSummary.Text:='';
  FLeftAudioSummary.FontFamily:=FCompactFont.Description.Family;
  FLeftAudioSummary.FontSize:=FCompactFont.Description.SizePoints;
  FLeftAudioSummary.SetConstraintHeight(asmFixed,ArosaCoord(24));
  FLeftAudioHost.AddVisual(FLeftAudioSummary);
  FLeftAudioTransport:=TArosaRowPanel.Create;
  FLeftAudioTransport.Spacing:=ArosaCoord(4);
  FLeftAudioTransport.SetConstraintHeight(asmFixed,ArosaCoord(30));
  NewButton(FLeftAudioTransport,'<<','Rewind',@AudioRewindClick,36);
  NewButton(FLeftAudioTransport,'>','Play / resume',@AudioPlayClick,36);
  NewButton(FLeftAudioTransport,'||','Pause',@AudioPauseClick,36);
  NewButton(FLeftAudioTransport,'[]','Stop',@AudioStopClick,36);
  NewButton(FLeftAudioTransport,'>>','Fast forward',@AudioForwardClick,36);
  FLeftAudioHost.AddVisual(FLeftAudioTransport);
  FMusicBars := TArosaMusicBars.CreateControl(FTheme,FFonts);
  if FDescriptor<>nil then
  begin
    FMusicBars.LowRole:=FDescriptor.Value('Spectrum','LowRole',AROSA_ROLE_HINT);
    FMusicBars.LowMidRole:=FDescriptor.Value('Spectrum','LowMidRole',AROSA_ROLE_INFORMATION);
    FMusicBars.HighMidRole:=FDescriptor.Value('Spectrum','HighMidRole',AROSA_ROLE_WARNING);
    FMusicBars.HighRole:=FDescriptor.Value('Spectrum','HighRole',AROSA_ROLE_ERROR);
  end;
  FMusicBars.BarCount := 12;
  FMusicBars.SetConstraintHeight(asmStar,ArosaCoord(1));
  FMusicBars.Visible := True;
  FLeftAudioHost.AddVisual(FMusicBars);
  FLeftAudioProgress:=TArosaProgressBar.CreateControl(FTheme,FFonts);
  FLeftAudioProgress.Minimum:=0; FLeftAudioProgress.Maximum:=100;
  FLeftAudioProgress.Position:=0; FLeftAudioProgress.ShowPercentage:=False;
  FLeftAudioProgress.SetConstraintHeight(asmFixed,ArosaCoord(14));
  FLeftAudioHost.AddVisual(FLeftAudioProgress);
  FLeftAudioPlayback:=TArosaLabel.CreateControl(FTheme,FFonts);
  FLeftAudioPlayback.Text:='';
  FLeftAudioPlayback.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  FLeftAudioPlayback.FontFamily:=FCompactFont.Description.Family;
  FLeftAudioPlayback.FontSize:=FCompactFont.Description.SizePoints;
  FLeftAudioPlayback.SetConstraintHeight(asmFixed,ArosaCoord(24));
  FLeftAudioHost.AddVisual(FLeftAudioPlayback);
  Page.AddVisual(FLeftAudioHost);
  Page.AddVisual(FLeftPreview);
  Page.AddVisual(FLeftImagePreview);
  Page := NewPage(PreviewTabs,LocalText('afilemanager_tab_metadata','Metadata'));
  { The canonical metadata view lives in the SAME tab control as Preview.
    (It was previously placed in the operations tab control; that Metadata tab
    has been removed and the view moved here, per the agreed layout.) }
  FMetadataView := TArosaMetadataView.CreateControl(FTheme,FFonts);
  FMetadataView.SetConstraintHeight(asmStar,ArosaCoord(1));
  FMetadataView.CaptionResolver := @MetadataCaption;
  FMetadataView.OnContextMenuOpening := @MetadataContextMenuOpening;
  FMetadataView.OnContextCommand := @MetadataContextCommand;
  FMetadataView.OnContextCommandEnabled := @MetadataContextCommandEnabled;
  FMetadataView.OnContextCommandIcon := @ContextCommandIcon;
  ContextDescriptor:=TStringList.Create;
  try
    ContextDescriptor.NameValueSeparator:='=';
    ContextDescriptor.Add('Resource.EditPermissions='+
      LocalText('afilemanager_action_edit_permissions','Edit permissions'));
    FMetadataView.SetContextMenuItems(ContextDescriptor);
  finally
    ContextDescriptor.Free;
  end;
  Page.AddVisual(FMetadataView);
  FMetadataPage := Page;
  FMetadataTabs := PreviewTabs;
  PreviewTabs.OnChange:=@PreviewTabsChanged;
  FLeftPreviewHost.AddVisual(PreviewTabs);
  FLeftPreviewTitle := TArosaLabel.CreateControl(FTheme,FFonts);
  FLeftPreviewTitle.Text := LocalText('afilemanager_preview_none','No preview selection');
  FLeftPreviewTitle.FontFamily := FCompactFont.Description.Family;
  FLeftPreviewTitle.FontSize := FCompactFont.Description.SizePoints;
  FLeftPreviewTitle.SetConstraintHeight(asmFixed,ArosaCoord(21));
  FLeftPreviewHost.AddVisual(FLeftPreviewTitle);
  UpdatePanelTabVisibility;

  ApplyPreviewLayout(0,FWindowFrame.PreviewPlacement);

  FRightColumn := nil;
  FRightBrowserColumn := nil; FRightPreviewSplit := nil;
  FRightTitle := nil;
  FRightPath := nil;
  FRightFilter := nil; FRightSearch := nil; FRightColumns := nil;
  FRightList := nil;
  FRightPreview := nil;
  FDualViewSplit := nil;
  ControllerStage('primary-view-ready');
  if HasDualView then
  begin
    FRightColumn := TArosaColumnPanel.Create;
    FRightColumn.Spacing := ArosaCoord(3);
    FRightBrowserColumn := TArosaColumnPanel.Create;
    FRightBrowserColumn.Spacing := ArosaCoord(3);
    { 0.7.13.0.0: surface bar - one button per file manager, + and x }
    FSurfaceBar := TArosaRowPanel.Create;
    FSurfaceBar.Spacing := ArosaCoord(2);
    FSurfaceBar.SetConstraintHeight(asmFixed, ArosaCoord(24));
    FRightBrowserColumn.AddVisual(FSurfaceBar);
    FSurfaces := TList.Create;
    FActiveSurface := 0;
    FSurfaceCounter := 1;
    FSurfaces.Add(TAFMSurface.Create);
    TAFMSurface(FSurfaces[0]).History := FRightNavigationHistory;
    TAFMSurface(FSurfaces[0]).Selected := -1;
    FRightPreviewSplit := TArosaSplitterHost.Create;
    FRightPreviewSplit.OnDividerChanged := @PreviewSplitterChanged;
    FRightTitle := TArosaLabel.CreateControl(FTheme, FFonts);
    FRightTitle.FontFamily := FCompactFont.Description.Family;
    FRightTitle.FontSize := FCompactFont.Description.SizePoints;
    FRightTitle.SetConstraintHeight(asmFixed, ArosaCoord(21));
    FRightPath := TArosaTextBox.CreateControl(FTheme, FFonts);
    FRightPath.Hint := LocalText('afilemanager_hint_secondary_path','Secondary location. Enter a path and press Enter.');
    FRightPath.FontFamily := FFileFont.Description.Family;
    FRightPath.FontSize := FFileFont.Description.SizePoints;
    FRightPath.SetConstraintHeight(asmFixed, ArosaCoord(25));
    FRightCrumbs := TArosaBreadcrumbBar.CreateBar(FTheme, FFonts);
    FRightCrumbs.Hint := LocalText('afilemanager_hint_breadcrumbs','Click a folder to open it; click the empty area to type a path.');
    FRightCrumbs.FontFamily := FFileFont.Description.Family;
    FRightCrumbs.FontSize := FFileFont.Description.SizePoints;
    FRightCrumbs.SetConstraintHeight(asmFixed, ArosaCoord(25));
    FRightCrumbs.OnNavigate := @RightCrumbNavigate;
    FRightCrumbs.OnEditRequest := @RightCrumbEdit;
    FRightPath.OnAccept := @RightPathEnter;
    FRightPath.Visible := False;
    FRightBrowserColumn.AddVisual(FRightCrumbs);
    FRightBrowserColumn.AddVisual(FRightPath);
    Row := TArosaRowPanel.Create;
    Row.Spacing := ArosaCoord(4);
    Row.SetConstraintHeight(asmFixed,ArosaCoord(25));
    L := TArosaLabel.CreateControl(FTheme,FFonts);
    L.Text := LocalText('afilemanager_filter','Filter:');
    L.FontFamily := FCompactFont.Description.Family;
    L.FontSize := FCompactFont.Description.SizePoints;
    L.SetConstraintWidth(asmFixed,ArosaCoord(52));
    Row.AddVisual(L);
    FRightFilter := TArosaTextBox.CreateControl(FTheme, FFonts);
    FRightFilter.Hint := LocalText('afilemanager_hint_filter_secondary','Type text to filter the secondary resource collection.');
    FRightFilter.FontFamily := FFileFont.Description.Family;
    FRightFilter.FontSize := FFileFont.Description.SizePoints;
    FRightFilter.SetConstraintWidth(asmFixed,ArosaCoord(150));
    FRightFilter.SetConstraintHeight(asmFixed, ArosaCoord(23));
    FRightFilter.OnChange := @RightFilterChanged;
    Row.AddVisual(FRightFilter);
    FRightClearFilter := NewButton(Row,'-',LocalText('afilemanager_hint_clear_filter','Clear filter'),@ClearRightFilterClick,22);
  ApplyButtonIcon(FRightClearFilter,'WindowIcons','Field.Clear',22);
    L := TArosaLabel.CreateControl(FTheme,FFonts);
    L.Text := LocalText('afilemanager_search','Search:');
    L.FontFamily := FCompactFont.Description.Family;
    L.FontSize := FCompactFont.Description.SizePoints;
    L.SetConstraintWidth(asmFixed,ArosaCoord(58));
    Row.AddVisual(L);
    FRightSearch := TArosaTextBox.CreateControl(FTheme, FFonts);
    FRightSearch.Hint := LocalText('afilemanager_hint_search_secondary','AROS/Amiga pattern search, for example #?.pas or (readme|#?.txt).');
    FRightSearch.FontFamily := FFileFont.Description.Family;
    FRightSearch.FontSize := FFileFont.Description.SizePoints;
    FRightSearch.SetConstraintWidth(asmStar,ArosaCoord(1));
    FRightSearch.SetConstraintHeight(asmFixed,ArosaCoord(23));
    FRightSearch.OnAccept := @RightSearchChanged;
    Row.AddVisual(FRightSearch);
    FRightClearSearch := NewButton(Row,'-',LocalText('afilemanager_hint_clear_search','Clear search'),@ClearRightSearchClick,22);
  ApplyButtonIcon(FRightClearSearch,'WindowIcons','Field.Clear',22);
    FRightBrowserColumn.AddVisual(Row);
    FRightColumns := nil;
    FRightList := TArosaFilteredListView.CreateControl(FTheme, FFonts);
    FRightList.FontFamily := FFileFont.Description.Family;
    FRightList.FontSize := FFileFont.Description.SizePoints;
    FRightList.SelectionMode := alsMultiple;
    FRightList.OnSelect := @RightSelected;
    ConfigureDetailsColumns(FRightList);
    FRightList.OnSortChanged := @ListSortChanged;
    FRightList.OnActivate := @RightActivated;
    FRightList.OnDragBegin := @ResourceDragBegin;
    FRightList.OnDragEnd := @ResourceDragEnd;
    FRightList.OnDragMove := @ResourceDragMove;
    FRightList.OnDragFinished := @ResourceDragFinished;
    FRightList.DragFeedback := FLeftList.DragFeedback;
    FRightList.OnDeleteRequest := @DeleteClick;
    FRightList.OnShortcut := @ListShortcut;
    FRightList.OnUndoRequest := @UndoClick;
    FRightList.OnCopyRequest := @CopyClick;
    FRightList.OnCutRequest := @CutClick;
    FRightList.OnPasteRequest := @PasteClick;
    FRightList.OnPointerDown := @ListPointerDown;
  FRightList.OnContextMenuOpening := @ListContextMenuOpening;
    if FDescriptor.BoolValue('Capabilities','ContextMenu',False) then
    begin
      FRightList.OnContextCommand := @ResourceContextCommand;
      FRightList.OnContextCommandIcon := @ContextCommandIcon;
      FRightList.OnContextCommandEnabled := @ResourceContextCommandEnabled;
      FRightList.OnContextCommandShortcut := @ResourceContextCommandShortcut;
      FRightList.OnDeleteRequest := @DeleteClick;
    FRightList.OnShortcut := @ListShortcut;
      FRightList.OnUndoRequest := @UndoClick;
      FRightList.OnCopyRequest := @CopyClick;
      FRightList.OnCutRequest := @CutClick;
      FRightList.OnPasteRequest := @PasteClick;
      ContextDescriptor:=FDescriptor.MenuSection('ContextMenu');
      try
        for CI:=0 to ContextDescriptor.Count-1 do
          ContextDescriptor.ValueFromIndex[CI]:=LocalValue(ContextDescriptor.ValueFromIndex[CI],ContextDescriptor.Names[CI]);
        ComposeResourceContextMenu(ContextDescriptor);
        FRightList.SetContextMenuItems(ContextDescriptor);
      finally ContextDescriptor.Free; end;
    end;
    FRightList.SetConstraintHeight(asmStar, ArosaCoord(1));
    FRightBrowserColumn.AddVisual(FRightList);
    FRightBrowserColumn.AddVisual(FRightTitle);
    FRightPreview := TArosaEditor.CreateControl(FTheme, FFonts);
    FRightPreview.Clipboard:=FPlatform.Clipboard;
    { Preview stays read-only; document tabs own Save. }
  FRightPreview.ReadOnly := True;
  FRightPreview.Multiline := True;
  FRightPreview.Highlighting := True;
  FRightPreview.ShowLineNumbers := False;
  FRightPreview.MenuWordWrap := LocalText('arosa_editor_word_wrap','Word wrap');
  FRightPreview.MenuLineNumbers := LocalText('arosa_editor_line_numbers','Line numbers');
  FRightPreview.MenuSearch := LocalText('arosa_editor_search','Search');
  FRightPreview.MenuGoToLine := LocalText('arosa_editor_go_to_line','Go to line');
  FRightPreview.MenuPrevious := LocalText('arosa_editor_previous','Previous');
  FRightPreview.MenuNext := LocalText('arosa_editor_next','Next');
  FRightPreview.MenuFromCursor := LocalText('arosa_editor_from_cursor','from cursor');
  FRightPreview.MenuNoMatches := LocalText('arosa_editor_no_matches','No matches');
  FRightPreview.MenuHighlighting := LocalText('arosa_editor_highlighting','Highlighting');
  FRightPreview.MenuCopy := LocalText('arosa_editor_copy','Copy');
  FRightPreview.MenuSelectAll := LocalText('arosa_editor_select_all','Select all');
    FRightPreview.Text := LocalText('afilemanager_preview_empty','Preview: no item selected');
    FRightPreview.ReadOnly := True;
    FRightPreview.Multiline := True;
    FRightPreview.FontFamily := FCompactFont.Description.Family;
    FRightPreview.FontSize := FCompactFont.Description.SizePoints;
    FRightPreview.SetConstraintHeight(asmStar, ArosaCoord(1));
    FRightPreview.Visible := True;
    FRightImagePreview := TArosaImageBox.CreateControl(FTheme, FFonts);
    FRightImagePreview.StretchMode := aismFit;
    FRightImagePreview.OnTransform := @ImageTransformRequested;
    FRightImagePreview.AltText := LocalText('afilemanager_preview_image','Image preview');
    FRightImagePreview.SetConstraintHeight(asmStar, ArosaCoord(1));
    FRightImagePreview.Visible := False;
    FRightPreviewHost := TArosaColumnPanel.Create;
    FRightPreviewHost.Spacing := ArosaCoord(0);
    FRightPreviewHost.SetConstraintHeight(asmStar, ArosaCoord(1));
    FRightPreviewHost.Visible := FLeftPreviewHost.Visible;
    PreviewTabs := TArosaTabControl.Create;
    StyleCommandTabs(PreviewTabs);
    PreviewTabs.SetConstraintHeight(asmStar,ArosaCoord(1));
    Page := NewPage(PreviewTabs,LocalText('afilemanager_tab_preview','Preview'));
    FRightPreviewPage := Page;
    FRightCommandBar := NewCommandBar;
    Page.AddVisual(FRightCommandBar);
    FRightAudioHost:=TArosaColumnPanel.Create;
    FRightAudioHost.Spacing:=ArosaCoord(4);
    FRightAudioHost.SetConstraintHeight(asmStar,ArosaCoord(1));
    FRightAudioHost.Visible:=False;
    FRightAudioSummary:=TArosaLabel.CreateControl(FTheme,FFonts);
    FRightAudioSummary.Text:='';
    FRightAudioSummary.FontFamily:=FCompactFont.Description.Family;
    FRightAudioSummary.FontSize:=FCompactFont.Description.SizePoints;
    FRightAudioSummary.SetConstraintHeight(asmFixed,ArosaCoord(24));
    FRightAudioHost.AddVisual(FRightAudioSummary);
    FRightAudioTransport:=TArosaRowPanel.Create;
    FRightAudioTransport.Spacing:=ArosaCoord(4);
    FRightAudioTransport.SetConstraintHeight(asmFixed,ArosaCoord(30));
    NewButton(FRightAudioTransport,'<<','Rewind',@AudioRewindClick,36);
    NewButton(FRightAudioTransport,'>','Play / resume',@AudioPlayClick,36);
    NewButton(FRightAudioTransport,'||','Pause',@AudioPauseClick,36);
    NewButton(FRightAudioTransport,'[]','Stop',@AudioStopClick,36);
    NewButton(FRightAudioTransport,'>>','Fast forward',@AudioForwardClick,36);
    FRightAudioHost.AddVisual(FRightAudioTransport);
    FRightMusicBars := TArosaMusicBars.CreateControl(FTheme,FFonts);
    if FDescriptor<>nil then
    begin
      FRightMusicBars.LowRole:=FDescriptor.Value('Spectrum','LowRole',AROSA_ROLE_HINT);
      FRightMusicBars.LowMidRole:=FDescriptor.Value('Spectrum','LowMidRole',AROSA_ROLE_INFORMATION);
      FRightMusicBars.HighMidRole:=FDescriptor.Value('Spectrum','HighMidRole',AROSA_ROLE_WARNING);
      FRightMusicBars.HighRole:=FDescriptor.Value('Spectrum','HighRole',AROSA_ROLE_ERROR);
    end;
    FRightMusicBars.BarCount := 12;
    FRightMusicBars.SetConstraintHeight(asmStar,ArosaCoord(1));
    FRightMusicBars.Visible := True;
    FRightAudioHost.AddVisual(FRightMusicBars);
    FRightAudioProgress:=TArosaProgressBar.CreateControl(FTheme,FFonts);
    FRightAudioProgress.Minimum:=0; FRightAudioProgress.Maximum:=100;
    FRightAudioProgress.Position:=0; FRightAudioProgress.ShowPercentage:=False;
    FRightAudioProgress.SetConstraintHeight(asmFixed,ArosaCoord(14));
    FRightAudioHost.AddVisual(FRightAudioProgress);
    FRightAudioPlayback:=TArosaLabel.CreateControl(FTheme,FFonts);
    FRightAudioPlayback.Text:='';
    FRightAudioPlayback.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
    FRightAudioPlayback.FontFamily:=FCompactFont.Description.Family;
    FRightAudioPlayback.FontSize:=FCompactFont.Description.SizePoints;
    FRightAudioPlayback.SetConstraintHeight(asmFixed,ArosaCoord(24));
    FRightAudioHost.AddVisual(FRightAudioPlayback);
    Page.AddVisual(FRightAudioHost);
    Page.AddVisual(FRightPreview);
    Page.AddVisual(FRightImagePreview);
    Page := NewPage(PreviewTabs,LocalText('afilemanager_tab_metadata','Metadata'));
    FRightMetadataPage := Page;
    FRightMetadataView := TArosaMetadataView.CreateControl(FTheme,FFonts);
    FRightMetadataView.SetConstraintHeight(asmStar,ArosaCoord(1));
    FRightMetadataView.CaptionResolver := @MetadataCaption;
    FRightMetadataView.OnContextMenuOpening := @MetadataContextMenuOpening;
    FRightMetadataView.OnContextCommand := @MetadataContextCommand;
    FRightMetadataView.OnContextCommandEnabled := @MetadataContextCommandEnabled;
    FRightMetadataView.OnContextCommandIcon := @ContextCommandIcon;
    ContextDescriptor:=TStringList.Create;
    try
      ContextDescriptor.NameValueSeparator:='=';
      ContextDescriptor.Add('Resource.EditPermissions='+
        LocalText('afilemanager_action_edit_permissions','Edit permissions'));
      FRightMetadataView.SetContextMenuItems(ContextDescriptor);
    finally
      ContextDescriptor.Free;
    end;
    Page.AddVisual(FRightMetadataView);
    FRightMetadataTabs := PreviewTabs;
    PreviewTabs.OnChange:=@PreviewTabsChanged;
    FRightPreviewHost.AddVisual(PreviewTabs);
    FRightPreviewTitle := TArosaLabel.CreateControl(FTheme,FFonts);
    FRightPreviewTitle.Text := LocalText('afilemanager_preview_none','No preview selection');
    FRightPreviewTitle.FontFamily := FCompactFont.Description.Family;
    FRightPreviewTitle.FontSize := FCompactFont.Description.SizePoints;
    FRightPreviewTitle.SetConstraintHeight(asmFixed,ArosaCoord(21));
    FRightPreviewHost.AddVisual(FRightPreviewTitle);
    UpdatePanelTabVisibility;

    ApplyPreviewLayout(1,FWindowFrame.PreviewPlacement);
    FDualViewSplit := TArosaSplitterHost.Create;
    FDualViewSplit.Orientation := aorHorizontal;
    FDualViewSplit.DividerThickness := ArosaCoord(10);
    FDualViewSplit.MinFirst := ArosaCoord(180);
    FDualViewSplit.MinSecond := ArosaCoord(180);
    FDualViewSplit.SetInitialPercent(StrToIntDef(FDescriptor.Value('SplitView','PrimaryPercent','50'),50));
    FDualViewSplit.SetPanes(FLeftColumn,FRightColumn);
    FViewsHost := FDualViewSplit;
  end
  else
    FViewsHost := FLeftColumn;

  FPlacesSplit.SetPanes(P,FViewsHost);
  ArosaTrace('WINDOW','surface=places visible=TRUE splitter=TRUE');
  ArosaTrace('WINDOW','surface=current-location visible=TRUE');
  ArosaTrace('WINDOW','surface=secondary-location visible='+BoolToStr(HasDualView,True));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}

  ControllerStage('views-ready');
  { Operations is the generic window operation surface.  The old
    [FilePanel] name remains readable for older descriptors. }
  OperationDescriptor := FDescriptor.Section('Operations');
  if OperationDescriptor.Count=0 then
  begin
    OperationDescriptor.Free;
    OperationDescriptor := FDescriptor.Section('FilePanel');
  end;
  try
    if OperationDescriptor.Count > 0 then
    begin
      FOperationTabs := TArosaTabControl.Create;
      StyleCommandTabs(FOperationTabs);
      FOperationTabs.SetConstraintHeight(asmFixed, ArosaCoord(190));
      FOperationTabs.ZOrder := 500;
      WindowFrame.FilePanelContent := FOperationTabs;
      BuildCommandTabs(FOperationTabs, OperationDescriptor, 'OPERATIONS');
      { 0.7.8.0.0: Operations remains one shared command surface.  A dynamic
        Console page is inserted beside Commands and shown only while one or
        more console documents are open. }
    end;
  finally
    OperationDescriptor.Free;
  end;

  FDeleteDialog := nil;
  FStatus := nil; FStatusRow:=nil; FTransferCancelButton:=nil; FTransferProgressDialog:=nil;
  if HasStatus then
  begin
    FStatusRow:=TArosaRowPanel.Create;
    FStatusRow.Spacing:=ArosaCoord(4);
    FStatusRow.SetConstraintHeight(asmFixed,ArosaCoord(23));
    FStatus := TArosaLabel.CreateControl(FTheme, FFonts);
    FStatus.Text := LocalText('afilemanager_status_ready','Ready');
    FStatus.FontFamily := FCompactFont.Description.Family;
    FStatus.FontSize := FCompactFont.Description.SizePoints;
    FStatus.SetConstraintWidth(asmStar,ArosaCoord(1));
    FStatus.SetConstraintHeight(asmFixed, ArosaCoord(21));
    FStatusRow.AddVisual(FStatus);
    FTransferCancelButton:=TArosaButton.CreateControl(FTheme,FFonts);
    FTransferCancelButton.Caption:='Cancel transfer';
    FTransferCancelButton.Hint:='Cancel the active background file transfer';
    FTransferCancelButton.OnClick:=@CancelTransferClick;
    FTransferCancelButton.SetConstraintWidth(asmFixed,ArosaCoord(118));
    FTransferCancelButton.SetConstraintHeight(asmFixed,ArosaCoord(21));
    FTransferCancelButton.Visible:=False;
    FStatusRow.AddVisual(FTransferCancelButton);
    WindowFrame.StatusContent := FStatusRow;
  end;

  FWindowFrame.OnCloseRequest := @WindowCloseRequested;
  FWindowFrame.OnToolbarChanged := @WindowToolbarChanged;
  FWindowFrame.OnFilePanelChanged := @WindowFilePanelChanged;
  FWindowFrame.OnSplitViewChanged := @WindowSplitViewChanged;
  FWindowFrame.OnPreviewChanged := @WindowPreviewChanged;
  { Re-apply descriptor visibility after the optional surfaces have been
    attached.  ApplyDescriptor runs before ToolbarContent/FilePanelContent
    exist, so this is the authoritative initial-state convergence point. }
  if FDescriptor.BoolValue('Visibility','Toolbar',False) <> FWindowFrame.ToolbarVisible then
    FWindowFrame.ToggleToolbar;
  if FDescriptor.BoolValue('Visibility','Operations',False) <> FWindowFrame.FilePanelVisible then
    FWindowFrame.ToggleFilePanel;
  WindowToolbarChanged(FWindowFrame);
  WindowFilePanelChanged(FWindowFrame);
  WindowSplitViewChanged(FWindowFrame);
  WindowPreviewChanged(FWindowFrame);
  ArosaTrace('WINDOW','initial visibility toolbar='+BoolToStr(FWindowFrame.ToolbarVisible,True)+
    ' operations='+BoolToStr(FWindowFrame.FilePanelVisible,True)+
    ' split='+BoolToStr(FWindowFrame.SplitView,True));
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
  { Practical defaults requested for the file manager.  These are window
    capabilities now, not one-off file-manager layout flags. }

  ControllerStage('dialogs-begin');
  { Portable modal confirmation surface. Added last so it is the topmost
    retained visual and intercepts input while visible. }
  FDeleteDialog := TArosaConfirmationDialog.CreateControl(FTheme,FFonts);
  FDeleteDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDeleteDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FDeleteDialog.ZOrder := 20000;
  FDeleteDialog.OnConfirm := @ConfirmDeleteClick;
  FDeleteDialog.OnCancel := @CancelDeleteClick;
  FInformationDialog := TArosaInformationDialog.CreateControl(FTheme,FFonts);
  FInformationDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FInformationDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FInformationDialog.ZOrder := 20500;
  FPermissionDialog := TArosaPermissionDialog.CreatePermissionDialog(
    FTheme,FFonts,FPermissionService,FLocalization);
  FPermissionDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FPermissionDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FPermissionDialog.ZOrder := 22500;
  FPermissionDialog.OnChanged := @PermissionChanged;
  FPermissionDialog.SetClipboard(FPlatform.Clipboard);
  FWindowFrame.AddVisual(FPermissionDialog);
  FArchiveDialog := TArosaArchiveCreateDialog.CreateControl(FTheme,FFonts);
  FArchiveDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FArchiveDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FArchiveDialog.ZOrder := 21000;
  FArchiveDialog.OnCreate := @ArchiveDialogCreate;
  FArchiveDialog.OnCancel := @ArchiveDialogCancel;
  FArchiveDialog.OnBrowseLocation := @ArchiveBrowseLocation;
  FArchiveDialog.SetClipboard(FPlatform.Clipboard);
  FWindowFrame.AddVisual(FArchiveDialog);

  FLocationPicker:=TArosaLocationPicker.CreateControl(FTheme,FFonts);
  FLocationPicker.SetConstraintWidth(asmStar,ArosaCoord(1));
  FLocationPicker.SetConstraintHeight(asmStar,ArosaCoord(1));
  FLocationPicker.ZOrder:=21200;
  FLocationPicker.OnList:=@LocationPickerList;
  FLocationPicker.OnParent:=@LocationPickerParent;
  FLocationPicker.OnAccept:=@LocationPicked;
  FLocationPicker.OnCancel:=@LocationPickerCancelled;
  FLocationPicker.SetClipboard(FPlatform.Clipboard);
  FWindowFrame.AddVisual(FLocationPicker);
  { Keep the modal surface inside the retained AROSA window tree.  Adding it
    as a sibling of the window frame caused the host form to paint only the
    dim overlay on AROS and made the actual dialog panel disappear. }
  FWindowFrame.AddVisual(FDeleteDialog);
  FWindowFrame.AddVisual(FInformationDialog);
  FArchiveOverwriteDialog:=TArosaConfirmationDialog.CreateControl(FTheme,FFonts);
  FArchiveOverwriteDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FArchiveOverwriteDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FArchiveOverwriteDialog.ZOrder:=21500;
  FArchiveOverwriteDialog.OnConfirm:=@ConfirmArchiveOverwrite;
  FArchiveOverwriteDialog.OnCancel:=@CancelArchiveOverwrite;
  FWindowFrame.AddVisual(FArchiveOverwriteDialog);
  FOperationRequester:=TArosaOperationRequester.CreateControl(FTheme,FFonts);
  FOperationRequester.SetConstraintWidth(asmStar,ArosaCoord(1));
  FOperationRequester.SetConstraintHeight(asmStar,ArosaCoord(1));
  FOperationRequester.ZOrder:=21600;
  FOperationRequester.OnDecision:=@ResourceConflictDecided;
  FWindowFrame.AddVisual(FOperationRequester);
  FTransferProgressDialog:=TArosaProgressDialog.CreateControl(FTheme,FFonts);
  FTransferProgressDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FTransferProgressDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FTransferProgressDialog.ZOrder:=21700;
  FTransferProgressDialog.OnPause:=@PauseTransferClick;
  FTransferProgressDialog.OnResume:=@ResumeTransferClick;
  FTransferProgressDialog.OnCancel:=@CancelTransferClick;
  FWindowFrame.AddVisual(FTransferProgressDialog);
  FNetworkDialog:=TArosaNetworkLocationDialog.CreateControl(FTheme,FFonts);
  FNetworkDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FNetworkDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FNetworkDialog.ZOrder:=21800;
  FNetworkDialog.OnAdd:=@NetworkLocationAdded;
  FNetworkDialog.OnCancel:=@NetworkLocationCancelled;
  FNetworkDialog.OnTestServer:=@NetworkLocationTestServer;
  FNetworkDialog.OnTestAccess:=@NetworkLocationTestAccess;
  FNetworkDialog.SetClipboard(FPlatform.Clipboard);
  FWindowFrame.AddVisual(FNetworkDialog);
  FSaveChangesDialog:=TArosaSaveChangesDialog.CreateControl(FTheme,FFonts);
  FSaveChangesDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FSaveChangesDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FSaveChangesDialog.ZOrder:=22000;
  FSaveChangesDialog.OnChoice:=@SaveChoiceMade;
  FWindowFrame.AddVisual(FSaveChangesDialog);

  { Application name-entry dialog: create/rename must never borrow the
    navigation path field as an editor.  It is a dedicated retained dialog
    using the standard AROSA text box/caret/selection behaviour. }
  FNameDialog:=TAFileManagerNameDialog.CreateNameDialog(FTheme,FFonts,FPlatform.Clipboard);
  FNameDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FNameDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FNameDialog.ZOrder:=22900;
  FNameDialog.OnAccept:=@NameDialogAccepted;
  FWindowFrame.AddVisual(FNameDialog);

  { Workspace Properties is distinct from the generic name-entry dialog.
    Keep the workspace id stable while allowing all workspace policy and
    screen settings to be edited together. }
  FWorkspacePropertiesDialog:=
    TAFileManagerWorkspacePropertiesDialog.CreateWorkspaceProperties(
      FTheme,FFonts,FPlatform.Clipboard,FLocalization);
  FWorkspacePropertiesDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FWorkspacePropertiesDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FWorkspacePropertiesDialog.ZOrder:=22950;
  FWorkspacePropertiesDialog.OnApply:=@WorkspacePropertiesApplied;
  FWorkspacePropertiesDialog.OnBrowseBackground:=@WorkspaceBackgroundBrowse;
  FWindowFrame.AddVisual(FWorkspacePropertiesDialog);

  FWorkspaceModulesDialog:=
    TAFileManagerWorkspaceModulesDialog.CreateWorkspaceModules(
      FTheme,FFonts,FPlatform.Clipboard,FLocalization);
  FWorkspaceModulesDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FWorkspaceModulesDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FWorkspaceModulesDialog.ZOrder:=22960;
  FWorkspaceModulesDialog.OnChange:=@WorkspaceModuleChanged;
  FWorkspaceModulesDialog.OnQueryPlacement:=@ModulePlacement;
  FWorkspaceModulesDialog.OnPlacement:=@ModulePlacementChanged;
  FWindowFrame.AddVisual(FWorkspaceModulesDialog);

  { Standard AROSA Open requester hosted as an application-modal surface.
    It deliberately has no AFileManager burger/toolbars/operations panel. }
  FBackgroundFileDialog:=TAFileManagerOpenFileDialog.CreateOpenFileDialog(
    FTheme,FFonts,FPlatform.Clipboard,FImageLoader);
  FBackgroundFileDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FBackgroundFileDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FBackgroundFileDialog.ZOrder:=22960;
  FBackgroundFileDialog.SetLister(@StandardDialogList);
  FBackgroundFileDialog.SetRowDecorator(@FileDialogDecorateRow);
  FBackgroundFileDialog.SetIconResolver(@FileDialogResolveIcon);
  FBackgroundFileDialog.SetPreviewPlacement(afppRight);
  ConfigureStandardOpenDialogLocations;
  FBackgroundFileDialog.OnAcceptPath:=@WorkspaceBackgroundSelected;
  FWindowFrame.AddVisual(FBackgroundFileDialog);

  ControllerStage('configuration-dialog-begin');
  { 0.7.14.0.0 application dialogs. }
  FConfigurationDialog:=TAFileManagerConfigurationDialog.CreateConfiguration(
    FTheme,FFonts,FPlatform.Clipboard,FLocalization);
  FConfigurationDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FConfigurationDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FConfigurationDialog.ZOrder:=23000;
  FConfigurationDialog.OnApply:=@ConfigurationApply;
  FConfigurationDialog.SetAvailableFonts(FFontService);
  PopulateConfigurationChoices;
  FWindowFrame.AddVisual(FConfigurationDialog);
  { Info is intentionally lazy-created in InfoClick.  Keeping the large
    transparent logo out of the retained tree at startup prevents hidden
    image repaint activity on AROS. }
  FInfoDialog:=nil;

  ControllerStage('assignments-begin');
  PopulateAssignments;
  ControllerStage('assignments-end');
  { Apply descriptor-declared initial presentation before the first directory
    enumeration so the first paint already matches the canonical window. }
  ApplyFileViewGeometry(0);
  ApplyFileViewGeometry(1);

  { The descriptor owns the initial location. "Desktop" resolves through
    the Desktop provider configuration; when no explicit desktop resource is
    configured, Downloads is the safe portable desktop-area fallback. }
  InitialLeft:=Trim(FDescriptor.Value('CurrentLocation','InitialLocation','Desktop'));
  if SameText(InitialLeft,'Desktop') then
  begin
    InitialLeft:=Trim(FDescriptor.Value('Locations.Desktop','Desktop',''));
    if InitialLeft='' then InitialLeft:='arosa://desktop';
  end;
  if InitialLeft='' then InitialLeft:='SYS:';
  FLeftCurrent := '';
  FRightCurrent := '';
  FActiveView := 0;
  { The framework default is the AROSA dark theme.  Only the light override
    needs an explicit transition here; doing it before navigation avoids a
    second directory enumeration merely to repaint the initial rows. }
  if SameText(FActiveThemeId,'Light') then ApplyTheme(FLightTheme);
  ControllerStage('initial-left-navigation-begin');
  NavigateView(0, InitialLeft);
  ControllerStage('initial-left-navigation-end');
  if FRightList<>nil then
  begin
    InitialRight:=Trim(FDescriptor.Value('SecondaryLocation','InitialLocation','Current'));
    if SameText(InitialRight,'Current') or (InitialRight='') then InitialRight:=FLeftCurrent;
    ControllerStage('initial-right-navigation-begin');
    NavigateView(1, InitialRight);
    ControllerStage('initial-right-navigation-end');
  end;
  SetActiveView(0);
  FContext.SetLocations(FLeftCurrent, FRightCurrent);
  ControllerStage('complete');
end;


function TAFileManagerController.ResourceDragBegin(ASender: TArosaControl;
  AIndex: Integer; const ARootPosition: TArosaPoint;
  const AModifiers: TArosaModifiers; out APayload: TArosaDragPayload): Boolean;
var L: TArosaFilteredListView; I,View: Integer; Items: TStringList;
begin
  Result:=False; APayload:=nil;
  if ASender=FRightList then View:=1 else View:=0;
  L:=ViewList(View); if L=nil then Exit;
  { 0.10.6.2: picking up an unselected item carries THAT item.  Only a
    modifier (Ctrl/Amiga/Shift) adds it to the existing selection; a plain
    drag used to carry the old selection along with it. }
  if (AIndex>=0) and not L.IsItemSelected(AIndex) then
  begin
    if not ((amControl in AModifiers) or (amAmiga in AModifiers) or
            (amShift in AModifiers)) then
      L.ClearSelection;
    L.SelectItem(AIndex);
  end;
  FPendingDropItems.Clear;
  APayload:=TArosaDragPayload.Create;
  APayload.SourceIdentity:='arosa.application.afilemanager.pane.'+IntToStr(View);
  APayload.AllowedOperations:=[atoCopy,atoMove];
  if amControl in AModifiers then APayload.PreferredOperation:=atoCopy
  else APayload.PreferredOperation:=atoMove;
  Items:=TStringList.Create;
  try
    CollectSelectedPaths(View,Items);
    for I:=0 to Items.Count-1 do APayload.AddFile(Items[I]);
  finally
    Items.Free;
  end;
  Result:=APayload.Count>0;
  if not Result then
    FreeAndNil(APayload)
  else
  begin
    FDragFeedbackKey:='';
    { Do not change retained UI state from the drag-begin callback.  This
      callback runs inside a captured mouse-move dispatch.  Status.Text used
      to invalidate/layout the form here, which on AROS could force painting
      while the captured input transaction was still unwinding. }
    LogMessage('[AROSA:DRAG] begin view='+IntToStr(View)+
      ' resources='+IntToStr(APayload.Count)+
      ' source='+APayload.SourceIdentity);
  end;
end;

{ Which pane, and which row of it, is under ARootPosition, and where a drop
  there would put things.  The ONE answer shared by the feedback shown while
  dragging and by the drop itself, so what is highlighted is what happens.

  AAllowProbe = False is the pointer-move case: nothing here may then touch
  a disk or a server, so "is this row a folder" comes from what the row
  already knows. }
function TAFileManagerController.ResolveDropTarget(ASender: TArosaControl;
  const ARootPosition: TArosaPoint; AAllowProbe: Boolean;
  out ATargetView, ATargetRow: Integer; out ADestination: string): Boolean;
var
  Target: TArosaFilteredListView;
  Local: TArosaPoint;
  SourceView: Integer;
  P, TargetReason: string;
  R: TArosaListRow;
  IsFolder: Boolean;

  function BrowserContains(ABrowser: TArosaVisual): Boolean;
  var Q: TArosaPoint;
  begin
    Result:=False;
    if ABrowser=nil then Exit;
    Q:=ABrowser.RootToLocal(ARootPosition);
    Result:=ArosaRectContains(
      ArosaRectXYWH(0,0,ArosaRectWidth(ABrowser.Bounds),
        ArosaRectHeight(ABrowser.Bounds)),Q);
  end;

begin
  Result:=False;
  ATargetView:=0; ATargetRow:=-1; ADestination:='';
  TargetReason:='none';
  if ASender=FRightList then SourceView:=1 else SourceView:=0;
  Target:=nil;
  { Prefer the pane opposite the drag source.  Some retained layout hosts can
    temporarily report overlapping child bounds while splitters are moving;
    checking the source pane first therefore misclassified a cross-pane drop
    as a drop back onto the source directory. }
  if ASender=FLeftList then
  begin
    if (FRightList<>nil) and BrowserContains(FRightList) then
      begin Target:=FRightList; ATargetView:=1; TargetReason:='right-list'; end;
    if (Target=nil) and (FLeftList<>nil) and BrowserContains(FLeftList) then
      begin Target:=FLeftList; ATargetView:=0; TargetReason:='left-list'; end;
  end
  else
  begin
    if (FLeftList<>nil) and BrowserContains(FLeftList) then
      begin Target:=FLeftList; ATargetView:=0; TargetReason:='left-list'; end;
    if (Target=nil) and (FRightList<>nil) and BrowserContains(FRightList) then
      begin Target:=FRightList; ATargetView:=1; TargetReason:='right-list'; end;
  end;

  { A drop anywhere in a pane's browser surface targets that pane's open
    directory.  Browser-column fallback MUST use the same opposite-pane-first
    rule as the list hit test above.  The previous unconditional left-then-
    right order could classify a left-to-right drop as left-pane when retained
    layout bounds temporarily overlapped, producing the false "already here"
    result before the transfer planner was ever called. }
  if Target=nil then
  begin
    if SourceView=0 then
    begin
      if (FRightList<>nil) and BrowserContains(FRightBrowserColumn) then
        begin Target:=FRightList; ATargetView:=1; TargetReason:='right-browser'; end;
      if (Target=nil) and BrowserContains(FLeftBrowserColumn) then
        begin Target:=FLeftList; ATargetView:=0; TargetReason:='left-browser'; end;
    end
    else
    begin
      if BrowserContains(FLeftBrowserColumn) then
        begin Target:=FLeftList; ATargetView:=0; TargetReason:='left-browser'; end;
      if (Target=nil) and (FRightList<>nil) and BrowserContains(FRightBrowserColumn) then
        begin Target:=FRightList; ATargetView:=1; TargetReason:='right-browser'; end;
    end;
  end;

  if Target=nil then
  begin
    if AAllowProbe and DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'drop.hit-test result=none source-pane='+IntToStr(SourceView+1)+
        ' root='+IntToStr(ArosaCoordWhole(ARootPosition.X))+','+
        IntToStr(ArosaCoordWhole(ARootPosition.Y)));
    Exit;
  end;

  Result:=True;
  ADestination:=ViewCurrent(ATargetView);

  if AAllowProbe and DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'drop.hit-test result='+TargetReason+
      ' source-pane='+IntToStr(SourceView+1)+
      ' target-pane='+IntToStr(ATargetView+1)+
      ' left-location='+ViewCurrent(0)+
      ' right-location='+ViewCurrent(1)+
      ' destination='+ADestination+
      ' root='+IntToStr(ArosaCoordWhole(ARootPosition.X))+','+
      IntToStr(ArosaCoordWhole(ARootPosition.Y)));

  { 0.10.6.2: the target is ALWAYS a folder, never a file.
      * over a folder item: that folder;
      * over a file item, or empty space: the folder the pane shows (which
        is the volume itself at a volume root).
    In the source pane the whole row of a folder counts.  In the other pane
    only its name (icon, type, name columns; the whole cell in icon views):
    a drop over the Size/Date columns of the other pane means "here", and
    retargeting it to whatever folder row the pointer crossed surprised. }
  Local:=Target.RootToLocal(ARootPosition);
  ATargetRow:=Target.ItemAtPosition(Local);
  if ATargetRow<0 then Exit;
  if ATargetView<>SourceView then
  begin
    P:=Target.ColumnIdAtPosition(Local);
    if (P<>'') and not (SameText(P,'resource.name') or SameText(P,'resource.type') or
       SameText(P,'resource.thumbnail')) then
    begin
      ATargetRow:=-1;
      Exit;
    end;
  end;
  P:=SelectedPath(ATargetView,ATargetRow);
  R:=Target.VisibleRowsView[ATargetRow];
  if (R<>nil) and ((R.UserFlags and AFM_ROW_FOLDER)<>0) then IsFolder:=True
  else if (R<>nil) and ((R.UserFlags and AFM_ROW_FILE)<>0) then IsFolder:=False
  else IsFolder:=AAllowProbe and (FLocations<>nil) and FLocations.IsDirectory(P);
  { a carried row is not a place to drop its own selection into; a folder
    selected in the OTHER pane is not carried and is a valid target }
  if IsFolder and (P<>'') and
     not ((ATargetView=SourceView) and Target.IsItemSelected(ATargetRow)) then
  begin
    ADestination:=P;
    if AAllowProbe and DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'drop.row-target pane='+IntToStr(ATargetView+1)+
        ' row='+IntToStr(ATargetRow)+
        ' destination='+ADestination);
  end
  else
    ATargetRow:=-1;
end;

{ What a drop does (0.10.6.2).  Modifiers decide first: Ctrl = copy,
  Shift = move.  Without one the [FileOperations] defaults apply: within one
  volume DragSameVolume (Move), across volumes DragOtherVolume (Copy); either
  may be Ask, which opens a Move / Copy / Cancel menu at the drop.  Remote
  locations always copy (a move would need the provider to delete). }
function TAFileManagerController.DropOperationFor(APayload: TArosaDragPayload;
  const ADestination: string; const AModifiers: TArosaModifiers;
  out AAsk: Boolean): TArosaTransferOperation;
var SV, DV: TArosaVolumeInfo; Source: string; Remote: Boolean;
begin
  AAsk:=False;
  if (APayload=nil) or (APayload.Count=0) then Exit(atoMove);
  { Provider URIs must never reach GetVolumeInfo. }
  Remote:=IsProviderLocation(APayload[0].Text) or IsProviderLocation(ADestination);
  Source:=LowerCase(Trim(APayload[0].Text));
  if Remote then
  begin
    FDragVolumeDest:='';
    FDragVolumeCrosses:=False;
  end
  { exec: and internal: are AROSA invocation targets, not DOS names.  Asking
    dos.library which volume "exec:" is on would open an "insert volume"
    requester - in the middle of a drag, now that this runs while hovering.
    The answer it would eventually give is "not another volume". }
  else if (Pos('exec:',Source)=1) or (Pos('internal:',Source)=1) then
  begin
    FDragVolumeDest:='';
    FDragVolumeCrosses:=False;
  end
  { The volume answer is remembered per destination: this is asked on every
    pointer move. }
  else if not SameText(FDragVolumeDest,ADestination) then
  begin
    FDragVolumeDest:=ADestination;
    FDragVolumeCrosses:=FFiles.GetVolumeInfo(APayload[0].Text,SV) and
      FFiles.GetVolumeInfo(ADestination,DV) and
      (not SameText(SV.RootPath,DV.RootPath));
  end;
  Result:=AfmDropOperation(amControl in AModifiers,amShift in AModifiers,Remote,
    FDragVolumeCrosses,FDragSameVolume,FDragOtherVolume,AAsk);
end;

{ A folder cannot go into itself or into a folder below it. }
function TAFileManagerController.DropIntoItself(APayload: TArosaDragPayload;
  const ADestination: string): Boolean;
var
  I: Integer;
  Dest: string;
begin
  Result:=False;
  if APayload=nil then Exit;
  Dest:=FLocations.Normalize(ADestination);
  for I:=0 to APayload.Count-1 do
    if (APayload[I].Kind=atkFile) and
       AfmPathInside(FLocations.Normalize(APayload[I].Text),Dest) then
      Exit(True);
end;

{ The selected items of a pane, in the order they were selected; an item
  deselected again is not in it. }
procedure TAFileManagerController.CollectSelectedPaths(AView: Integer; AItems: TStrings);
var
  L: TArosaFilteredListView;
  Sel: TArosaListIndexArray;
  I: Integer;
  P: string;
begin
  L:=ViewList(AView);
  if (L=nil) or (AItems=nil) then Exit;
  Sel:=L.SelectedIndices;
  for I:=0 to High(Sel) do
  begin
    P:=SelectedPath(AView,Sel[I]);
    if (P<>'') and (ExtractFileName(P)<>'..') then AItems.Add(P);
  end;
end;

{ The Move / Copy / Cancel menu of a drop that asks. }
function TAFileManagerController.TryDropMenuCommand(const ACommand: string): Boolean;
var Op: TArosaTransferOperation;
begin
  Result:=SameText(ACommand,'Drop.Move') or SameText(ACommand,'Drop.Copy') or
    SameText(ACommand,'Drop.Cancel');
  if not Result then Exit;
  if SameText(ACommand,'Drop.Cancel') or (FPendingDropItems.Count=0) then
  begin
    FPendingDropItems.Clear;
    SetStatus(LocalText('afilemanager_status_drop_cancelled','Drop cancelled'));
    Exit;
  end;
  if SameText(ACommand,'Drop.Copy') then Op:=atoCopy else Op:=atoMove;
  DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,'drag.ask chosen operation='+
    ArosaTransferOperationName(Op)+' items='+IntToStr(FPendingDropItems.Count)+
    ' destination='+FPendingDropDestination);
  BeginResourceOperation('transfer',FPendingDropItems,FPendingDropDestination,Op,
    FPendingDropView);
  FPendingDropItems.Clear;
end;

procedure TAFileManagerController.ResourceDragMove(ASender: TArosaControl;
  APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
  const AModifiers: TArosaModifiers);
var
  Source, TargetList, OtherList: TArosaFilteredListView;
  TargetView, TargetRow, I, N: Integer;
  Destination, DestKey, Caption, Where, FeedbackKey: string;
  Op: TArosaTransferOperation;
  SamePlace, Ask: Boolean;
begin
  if (APayload=nil) or not (ASender is TArosaFilteredListView) then Exit;
  Source:=TArosaFilteredListView(ASender);

  { The folders the carried items are in are worked out once per drag. }
  if not FDragParentsReady then
  begin
    FDragSourceParents.Clear;
    for I:=0 to APayload.Count-1 do
      if APayload[I].Kind=atkFile then
        FDragSourceParents.Add(FLocations.Normalize(ParentPath(
          FLocations.Normalize(APayload[I].Text))));
    FDragParentsReady:=True;
  end;
  N:=FDragSourceParents.Count;

  if not ResolveDropTarget(ASender,ARootPosition,False,TargetView,TargetRow,
       Destination) then
  begin
    FeedbackKey:='none';
    if FDragFeedbackKey<>FeedbackKey then
    begin
      FDragFeedbackKey:=FeedbackKey;
      if FLeftList<>nil then FLeftList.SetDropHighlight(aldhNone);
      if FRightList<>nil then FRightList.SetDropHighlight(aldhNone);
      Source.DragCaption:=SysUtils.Format(LocalText('afilemanager_drag_nowhere',
        '%d item(s) - not a place to drop'),[N]);
    end;
    Exit;
  end;

  TargetList:=ViewList(TargetView);
  if TargetList=FLeftList then OtherList:=FRightList else OtherList:=FLeftList;

  { Dropping things where they already are does nothing (see the drop). }
  DestKey:=FLocations.Normalize(Destination);
  SamePlace:=N>0;
  for I:=0 to N-1 do
    if not SameText(FDragSourceParents[I],DestKey) then
    begin
      SamePlace:=False;
      Break;
    end;

  if SamePlace then
  begin
    FeedbackKey:='same|'+IntToStr(TargetView)+'|'+DestKey;
    if FDragFeedbackKey<>FeedbackKey then
    begin
      FDragFeedbackKey:=FeedbackKey;
      if OtherList<>nil then OtherList.SetDropHighlight(aldhNone);
      TargetList.SetDropHighlight(aldhNone);
      Source.DragCaption:=SysUtils.Format(LocalText('afilemanager_drag_same_place',
        '%d item(s) - already here'),[N]);

      { Log a spatial decision only when it CHANGES.  The old code wrote the
        same trace record on every mouse-move tick, which made targeted TRACE
        itself part of the drag latency. }
      if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
        DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
          'drag.feedback same-location=true target-pane='+IntToStr(TargetView+1)+
          ' destination='+Destination+
          ' normalized-destination='+DestKey+
          ' source-parents='+FDragSourceParents.CommaText);
    end;
    Exit;
  end;

  { 0.10.6.2: a folder never goes into itself or below itself }
  if DropIntoItself(APayload,Destination) then
  begin
    FeedbackKey:='into-itself|'+IntToStr(TargetView)+'|'+DestKey;
    if FDragFeedbackKey<>FeedbackKey then
    begin
      FDragFeedbackKey:=FeedbackKey;
      if OtherList<>nil then OtherList.SetDropHighlight(aldhNone);
      TargetList.SetDropHighlight(aldhNone);
      Source.DragCaption:=SysUtils.Format(LocalText('afilemanager_drag_into_itself',
        '%d item(s) - a folder cannot go into itself'),[N]);
    end;
    Exit;
  end;

  Op:=DropOperationFor(APayload,Destination,AModifiers,Ask);
  FeedbackKey:='target|'+IntToStr(TargetView)+'|'+IntToStr(TargetRow)+'|'+
    DestKey+'|'+ArosaTransferOperationName(Op)+'|'+BoolToStr(Ask,'ask','');

  { Retained drag visuals are state, not animation.  Re-applying the same
    highlight/caption every pointer tick only invalidates and lays out the UI
    again. }
  if FDragFeedbackKey=FeedbackKey then Exit;
  FDragFeedbackKey:=FeedbackKey;

  if OtherList<>nil then OtherList.SetDropHighlight(aldhNone);
  if TargetRow>=0 then TargetList.SetDropHighlight(aldhRow,TargetRow)
  else TargetList.SetDropHighlight(aldhList);

  if Ask then Caption:=LocalText('afilemanager_drag_ask','Move or copy')
  else if Op=atoCopy then Caption:=LocalText('afilemanager_drag_copy','Copy')
  else Caption:=LocalText('afilemanager_drag_move','Move');
  Where:=Destination;
  if Length(Where)>48 then Where:='...'+Copy(Where,Length(Where)-44,45);
  Source.DragCaption:=SysUtils.Format(LocalText('afilemanager_drag_caption',
    '%s %d item(s) to %s'),[Caption,N,Where]);

  if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'drag.feedback target-pane='+IntToStr(TargetView+1)+
      ' target-row='+IntToStr(TargetRow)+
      ' destination='+Destination+
      ' operation='+ArosaTransferOperationName(Op));
end;

procedure TAFileManagerController.ResourceDragFinished(ASender: TArosaControl);
begin
  if FLeftList<>nil then FLeftList.SetDropHighlight(aldhNone);
  if FRightList<>nil then FRightList.SetDropHighlight(aldhNone);
  FDragParentsReady:=False;
  FDragSourceParents.Clear;
  FDragVolumeDest:='';
  FDragFeedbackKey:='';
  if ASender=nil then ;
end;

procedure TAFileManagerController.ResourceDragEnd(ASender: TArosaControl;
  AIndex: Integer; APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
  const AModifiers: TArosaModifiers);
var
  SourceView,TargetView,TargetIndex,I: Integer;
  Destination,P,Parent: string; Items, Menu: TStringList; Op: TArosaTransferOperation; TI: TArosaTransferItem;
  Ask: Boolean;
  TargetList: TArosaFilteredListView;
begin
  if APayload=nil then Exit;
  if ASender=FRightList then SourceView:=1 else SourceView:=0;
  LogMessage('[AROSA:DRAG] end enter resources='+IntToStr(APayload.Count)+
    ' root='+IntToStr(ArosaCoordWhole(ARootPosition.X))+','+
    IntToStr(ArosaCoordWhole(ARootPosition.Y)));
  if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'drag.end begin source-pane='+IntToStr(SourceView+1)+
      ' resources='+IntToStr(APayload.Count)+
      ' root='+IntToStr(ArosaCoordWhole(ARootPosition.X))+','+
      IntToStr(ArosaCoordWhole(ARootPosition.Y)));

  if not ResolveDropTarget(ASender,ARootPosition,True,TargetView,TargetIndex,
       Destination) then
  begin
    if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'drag.end cancelled reason=no-destination-pane');
    SetStatus('Drag cancelled: no destination pane');
    APayload.Free;
    Exit;
  end;
  LogMessage('Drop target pane='+IntToStr(TargetView+1)+
    ' source-pane='+IntToStr(SourceView+1)+
    ' destination='+Destination+
    ' resources='+IntToStr(APayload.Count));

  { 0.10.6.2: a folder never goes into itself or below itself }
  if DropIntoItself(APayload,Destination) then
  begin
    SetStatus(LocalText('afilemanager_status_drop_into_itself',
      'Drop refused: a folder cannot be moved or copied into itself'));
    APayload.Free;
    Exit;
  end;

  Op:=DropOperationFor(APayload,Destination,AModifiers,Ask);
  if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
    DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
      'drag.operation ask='+BoolToStr(Ask,True)+' source-pane='+IntToStr(SourceView+1)+
      ' target-pane='+IntToStr(TargetView+1)+
      ' target-row='+IntToStr(TargetIndex)+
      ' destination='+Destination+
      ' operation='+ArosaTransferOperationName(Op)+
      ' control='+BoolToStr(amControl in AModifiers,True)+
      ' shift='+BoolToStr(amShift in AModifiers,True));

  Items:=TStringList.Create;
  try
    Destination:=FLocations.Normalize(Destination);
    if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'drag.destination normalized='+Destination);

    for I:=0 to APayload.Count-1 do
    begin
      TI:=APayload[I];
      if TI.Kind<>atkFile then
      begin
        if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
          DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
            'drag.item index='+IntToStr(I)+' accepted=false reason=not-file');
        Continue;
      end;
      P:=FLocations.Normalize(TI.Text);
      Parent:=FLocations.Normalize(ParentPath(P));

      if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
        DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
          'drag.item index='+IntToStr(I)+
          ' source='+TI.Text+
          ' normalized='+P+
          ' parent='+Parent+
          ' destination='+Destination+
          ' same-path='+BoolToStr(SameText(P,Destination),True)+
          ' same-parent='+BoolToStr(SameText(Parent,Destination),True));

      { Drag/drop is spatial relocation, not "duplicate here".  Dropping a
        resource back into its own containing directory (or onto itself)
        must be a no-op.  Explicit Copy/Paste remains the mechanism that can
        create a same-location copy.  This also avoids pointless remote STAT
        and transfer traffic on provider locations. }
      if AfmDropIsSamePlace(P,Parent,Destination) then
      begin
        DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
          'drag.item accepted=false reason=same-location source='+P+
          ' destination='+Destination);
        Continue;
      end;
      Items.Add(TI.Text);
    end;

    if Items.Count=0 then
    begin
      if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
        DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
          'drag.dispatch suppressed reason=no-transferable-items');
      SetStatus(LocalText('afilemanager_status_drag_same_location',
        'Drag ignored: resource is already in this location'));
      Exit;
    end;

    { 0.10.6.2: [FileOperations] Drag... = Ask - the Move / Copy / Cancel
      menu opens at the drop; the choice arrives as Drop.Move / Drop.Copy /
      Drop.Cancel (TryDropMenuCommand) }
    if Ask then
    begin
      FPendingDropItems.Assign(Items);
      FPendingDropDestination:=Destination;
      FPendingDropView:=TargetView;
      TargetList:=ViewList(TargetView);
      Menu:=TStringList.Create;
      try
        Menu.Add('Drop.Move='+SysUtils.Format(LocalText('afilemanager_drop_move_here',
          'Move %d item(s) here'),[Items.Count]));
        Menu.Add('Drop.Copy='+SysUtils.Format(LocalText('afilemanager_drop_copy_here',
          'Copy %d item(s) here'),[Items.Count]));
        Menu.Add('Separator.Drop=-');
        Menu.Add('Drop.Cancel='+LocalText('afilemanager_drop_cancel','Cancel'));
        if TargetList<>nil then
          TargetList.ShowCommandMenu(Menu,TargetList.RootToLocal(ARootPosition));
      finally
        Menu.Free;
      end;
      Exit;
    end;

    { Planned, conflicts decided, then run.  Drag/drop deliberately enters the
      same resource-operation planner as Copy/Paste so overwrite policy cannot
      be bypassed by the spatial gesture. }
    if DiagnosticComponentEnabled(AFM_DIAG_DRAGDROP,amsTrace) then
      DiagnosticComponentTrace(AFM_DIAG_DRAGDROP,
        'drag.dispatch kind=transfer items='+IntToStr(Items.Count)+
        ' destination='+Destination+
        ' operation='+ArosaTransferOperationName(Op)+
        ' target-pane='+IntToStr(TargetView+1));
    BeginResourceOperation('transfer',Items,Destination,Op,TargetView);
  finally
    Items.Free;
    APayload.Free;
  end;
  if AIndex<0 then ;
end;

procedure TAFileManagerController.ImageTransformRequested(ASender: TArosaControl;
  ATransform: TArosaImageTransform);
var
  ViewIndex: Integer;
  OldResource, NewResource: TArosaImageResource;
  Target: TArosaImageBox;
  Err: string;
begin
  if ASender = FLeftImagePreview then ViewIndex := 0
  else if ASender = FRightImagePreview then ViewIndex := 1
  else Exit;
  if ViewIndex = 0 then
  begin
    OldResource := FLeftImageResource;
    Target := FLeftImagePreview;
  end
  else
  begin
    OldResource := FRightImageResource;
    Target := FRightImagePreview;
  end;
  NewResource := nil;
  if (FImageTransforms = nil) or
     not FImageTransforms.TryTransform(OldResource, ATransform, NewResource, Err) then
  begin
    SetStatus(LocalText('afilemanager_image_transform_failed',
      'Image transform failed: ') + Err);
    Exit;
  end;
  if ViewIndex = 0 then FLeftImageResource := NewResource
  else FRightImageResource := NewResource;
  Target.Bitmap := NewResource.Bitmap;
  Target.SourceRect := ArosaRectXYWH(0, 0, NewResource.Width, NewResource.Height);
  Target.StretchMode := aismFit;
  Target.ZoomPercent := 100;
  if OldResource <> nil then OldResource.Free;
  Target.InvalidateLayout;
  Target.InvalidatePaint;
  SetStatus(LocalText('afilemanager_image_transformed', 'Image transformed'));
end;

procedure TAFileManagerController.ConfigureDocumentEditor(AEditor: TArosaEditor);
begin
  AEditor.Clipboard := FPlatform.Clipboard;
  AEditor.OnSaveRequest := @SaveInternalEdit;
  AEditor.OnCloseRequest := @EditorCloseRequested;
  AEditor.OnChange := @DocumentChanged;
  AEditor.OnCommandFocusRequest := @EditorCommandFocus;
  AEditor.ReadOnly := False;
  AEditor.Multiline := True;
  { Horizontal scrolling is the default; only an explicit Word wrap command
    may enable wrapping.  The document editor fills its tab width. }
  AEditor.WordWrap := False;
  AEditor.SetConstraintWidth(asmStar,ArosaCoord(1));
  AEditor.Highlighting := True;
  AEditor.ShowLineNumbers := True;
  AEditor.MenuWordWrap := LocalText('arosa_editor_word_wrap','Word wrap');
  AEditor.MenuLineNumbers := LocalText('arosa_editor_line_numbers','Line numbers');
  AEditor.MenuSearch := LocalText('arosa_editor_search','Find');
  AEditor.MenuReplace := LocalText('arosa_editor_replace','Replace');
  AEditor.MenuGoToLine := LocalText('arosa_editor_go_to_line','Go to line');
  AEditor.MenuPrevious := LocalText('arosa_editor_previous','Previous');
  AEditor.MenuNext := LocalText('arosa_editor_next','Next');
  AEditor.MenuFromCursor := LocalText('arosa_editor_from_cursor','from cursor');
  AEditor.MenuNoMatches := LocalText('arosa_editor_no_matches','No matches');
  AEditor.MenuHighlighting := LocalText('arosa_editor_highlighting','Highlighting');
  AEditor.MenuCopy := LocalText('arosa_editor_copy','Copy');
  AEditor.MenuCut := LocalText('arosa_editor_cut','Cut');
  AEditor.MenuPaste := LocalText('arosa_editor_paste','Paste');
  { The document toolbar belongs to the document surface, not inside the
    editor control. Keeping it outside the editor prevents the toolbar from
    being clipped/rearranged when the editor is hosted by a rendition
    splitter. }
  AEditor.ShowDocumentToolbar := False;
  AEditor.ShowStatusBar := True;
  AEditor.ToolbarSaveHint:=LocalText('afilemanager_hint_editor_save','Save this document');
  AEditor.ToolbarCloseHint:=LocalText('afilemanager_hint_editor_close','Close this document');
  AEditor.ToolbarFindHint:=LocalText('afilemanager_hint_editor_find','Find text (Ctrl+F)');
  AEditor.ToolbarReplaceHint:=LocalText('afilemanager_hint_editor_replace','Find and replace text (Ctrl+H)');
  AEditor.ToolbarGoToLineHint:=LocalText('afilemanager_hint_editor_goto','Go to a line (Ctrl+G)');
  AEditor.ToolbarRenditionHint:=LocalText('afilemanager_hint_editor_rendition','Show or hide document rendition');
  AEditor.OnToggleRenditionRequest:=@ToggleDocumentRendition;
  AEditor.OnCommandIcon:=@ContextCommandIcon;
  AEditor.MenuSelectAll := LocalText('arosa_editor_select_all','Select all');
  AEditor.FontFamily := FCompactFont.Description.Family;
  AEditor.FontSize := FCompactFont.Description.SizePoints;
  AEditor.SetConstraintHeight(asmStar,ArosaCoord(1));
end;

{ Language id for comment/uncomment and future highlighting (0.5.110.44). }
function EditorLanguageForPath(const APath: string): string;
var E: string;
begin
  E:=LowerCase(ExtractFileExt(APath));
  if (E='.pas') or (E='.pp') or (E='.inc') or (E='.lpr') or (E='.dpr') then Result:='pascal'
  else if (E='.c') or (E='.h') or (E='.cpp') or (E='.hpp') or (E='.cc') then Result:='c'
  else if (E='.js') or (E='.java') or (E='.cs') or (E='.go') or (E='.rs') then Result:='c'
  else if (E='.py') then Result:='python'
  else if (E='.sh') or (E='.bash') or (E='.conf') or (E='.cfg') or (E='.yml') or (E='.yaml') then Result:='shell'
  else if (E='.mk') or (LowerCase(ExtractFileName(APath))='makefile') then Result:='make'
  else if (E='.sql') then Result:='sql'
  else if (E='.lua') then Result:='lua'
  else if (E='.ini') or (E='.window') or (E='.asm') or (E='.s') then Result:='ini'
  else if (E='.rexx') or (E='.rx') then Result:='c'
  else if (E='') then Result:='amigados'   { AmigaDOS scripts usually have no extension }
  else Result:='';
end;

procedure TAFileManagerController.ReleaseDocumentRendition(
  ADoc: TAFileManagerDocument);
begin
  if ADoc=nil then Exit;
  if ADoc.RenditionPresentation<>nil then
    ReleasePresentation(ADoc.RenditionPresentation);
  if ADoc.RenditionText<>nil then
  begin
    if (ADoc.RenditionText.ParentVisual is TArosaView) then
      TArosaView(ADoc.RenditionText.ParentVisual).RemoveVisual(ADoc.RenditionText);
    FreeAndNil(ADoc.RenditionText);
  end;
end;

procedure TAFileManagerController.RefreshDocumentRendition(
  ADoc: TAFileManagerDocument);
var
  Pres: TArosaPresentation;
  ContentDesc: TArosaContentDescriptor;
  E: string;
begin
  if (ADoc=nil) or (ADoc.RenditionHost=nil) then Exit;
  ReleaseDocumentRendition(ADoc);
  Pres:=nil;
  E:='';
  FillChar(ContentDesc,SizeOf(ContentDesc),0);

  if (FPresentationService<>nil) and
     FPresentationService.CreatePresentationForLocation(
       ADoc.Path,apmDocument,True,Pres,ContentDesc,E) and
     (Pres<>nil) and not (Pres is TArosaProbePresentation) and
     (Pres.Control<>nil) then
  begin
    Pres.OnMessage:=@PresentationMessage;
    Pres.Control.SetConstraintWidth(asmStar,ArosaCoord(1));
    Pres.Control.SetConstraintHeight(asmStar,ArosaCoord(1));
    ADoc.RenditionHost.AddVisual(Pres.Control);
    if Pres.Load(E) then
      ADoc.RenditionPresentation:=Pres
    else
    begin
      ADoc.RenditionHost.RemoveVisual(Pres.Control);
      Pres.Close;
      Pres.Free;
      Pres:=nil;
    end;
  end
  else if Pres<>nil then
  begin
    Pres.Close;
    Pres.Free;
    Pres:=nil;
  end;

  if ADoc.RenditionPresentation=nil then
  begin
    ADoc.RenditionText:=TArosaEditor.CreateControl(FTheme,FFonts);
    ADoc.RenditionText.ReadOnly:=True;
    ADoc.RenditionText.Multiline:=True;
    ADoc.RenditionText.WordWrap:=True;
    ADoc.RenditionText.Highlighting:=True;
    ADoc.RenditionText.ShowLineNumbers:=False;
    ADoc.RenditionText.ShowDocumentToolbar:=False;
    ADoc.RenditionText.ShowStatusBar:=False;
    ADoc.RenditionText.Language:=EditorLanguageForPath(ADoc.Path);
    ADoc.RenditionText.FontFamily:=FCompactFont.Description.Family;
    ADoc.RenditionText.FontSize:=FCompactFont.Description.SizePoints;
    ADoc.RenditionText.SetConstraintWidth(asmStar,ArosaCoord(1));
    ADoc.RenditionText.SetConstraintHeight(asmStar,ArosaCoord(1));
    if ADoc.Editor<>nil then
      ADoc.RenditionText.Text:=ADoc.Editor.Text
    else
      ADoc.RenditionText.Text:=ADoc.OriginalText;
    ADoc.RenditionHost.AddVisual(ADoc.RenditionText);
  end;
  ADoc.RenditionHost.InvalidateLayout;
  ADoc.RenditionHost.InvalidatePaint;
end;

function TAFileManagerController.SaveDocument(ADoc: TAFileManagerDocument): Boolean;
begin
  Result:=False;
  if (ADoc=nil) or (ADoc.Editor=nil) then Exit;
  if ADoc.Editor.Text=ADoc.OriginalText then Exit(True);
  { SafeSaveText writes a temp copy, reads it back byte for byte, and only
    then replaces the original (which is restored on any failure). }
  if (FFiles<>nil) and FFiles.SafeSaveText(ADoc.Path,ADoc.Editor.Text) then
  begin
    ADoc.OriginalText:=ADoc.Editor.Text;
    FDocumentTabs.SetPageTitle(ADoc.TabIndex,ExtractFileName(ADoc.Path));
    RefreshDocumentRendition(ADoc);
    SetStatus('Saved and verified: '+ADoc.Path+' ('+IntToStr(Length(ADoc.OriginalText))+' bytes)');
    UpdateWorkspacePendingWork;
    Result:=True;
  end
  else SetStatus('Save failed: '+ADoc.Path+' (the previous file is kept whenever the platform allows)');
end;


procedure TAFileManagerController.ToggleDocumentRendition(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  if FDocuments=nil then Exit;
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.Editor<>ASender then Continue;
    Doc.RenditionVisible:=not Doc.RenditionVisible;
    if Doc.RenditionSplit<>nil then
    begin
      if Doc.RenditionVisible then
      begin
        Doc.RenditionSplit.SetPanes(Doc.Editor,Doc.RenditionHost);
        Doc.RenditionSplit.SetPercent(50);
      end
      else
        Doc.RenditionSplit.SetPanes(Doc.Editor,nil);
      Doc.RenditionSplit.InvalidateLayout;
      Doc.RenditionSplit.InvalidatePaint;
    end;
    Exit;
  end;
end;

procedure TAFileManagerController.DocumentChanged(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument; Caption: string;
begin
  if FDocuments=nil then Exit;
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.Editor<>ASender then Continue;
    Caption:=ExtractFileName(Doc.Path);
    if Doc.Editor.Text<>Doc.OriginalText then Caption:=Caption+' *';
    FDocumentTabs.SetPageTitle(Doc.TabIndex,Caption);
    if Doc.RenditionText<>nil then
      Doc.RenditionText.Text:=Doc.Editor.Text;
    UpdateWorkspacePendingWork;
    Exit;
  end;
end;

procedure TAFileManagerController.SaveInternalEdit(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  if FDocuments=nil then Exit;
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.Editor=ASender then
    begin SaveDocument(Doc); Exit; end;
  end;
end;

procedure TAFileManagerController.DocumentSaveClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if (Doc.SaveButton=ASender) then
    begin SaveDocument(Doc); Exit; end;
  end;
end;

procedure TAFileManagerController.DocumentCloseClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if (Doc.CloseButton=ASender) then
    begin RequestCloseDocument(Doc); Exit; end;
  end;
end;

procedure TAFileManagerController.DocumentFindClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.FindButton=ASender then
    begin
      if Doc.Editor<>nil then Doc.Editor.ShowSearch;
      Exit;
    end;
  end;
end;

procedure TAFileManagerController.DocumentReplaceClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.ReplaceButton=ASender then
    begin
      if Doc.Editor<>nil then Doc.Editor.ShowReplace;
      Exit;
    end;
  end;
end;

procedure TAFileManagerController.DocumentGoToLineClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.GoToLineButton=ASender then
    begin
      if Doc.Editor<>nil then Doc.Editor.ShowGoToLine;
      Exit;
    end;
  end;
end;

procedure TAFileManagerController.DocumentRenditionClick(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.RenditionButton=ASender then
    begin
      ToggleDocumentRendition(Doc.Editor);
      Exit;
    end;
  end;
end;

procedure TAFileManagerController.EditorCloseRequested(ASender: TArosaControl);
var I: Integer; Doc: TAFileManagerDocument;
begin
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.Editor=ASender then
    begin RequestCloseDocument(Doc); Exit; end;
  end;
end;

procedure TAFileManagerController.EditorCommandFocus(ASender: TArosaControl);
begin
  if (ASender is TArosaEditor) and (FNativeHost<>nil) then
    FNativeHost.FocusControl(TArosaEditor(ASender).CommandInput);
end;

procedure TAFileManagerController.QueueCloseDocument(ADoc: TAFileManagerDocument);
begin
  if ADoc=nil then Exit;
  FDeferredCloseDocument:=ADoc;
  { Removal happens in the event loop's idle phase, after the originating
    Save/Close button or editor keyboard event has returned. }
end;

procedure TAFileManagerController.DocumentCloseIdle(var AMoreWorkPending: Boolean);
var Doc: TAFileManagerDocument;
begin
  if FDeferredCloseDocument=nil then Exit;
  Doc:=FDeferredCloseDocument;
  FDeferredCloseDocument:=nil;
  { Complete the deferred removal once. Requeueing here kept the pointer
    permanently non-nil, so neither document nor application could close. }
  FinishCloseDocument(Doc);
  if FClosingApplication then ContinueApplicationClose;
  AMoreWorkPending:=FDeferredCloseDocument<>nil;
end;

procedure TAFileManagerController.FinishCloseDocument(ADoc: TAFileManagerDocument);
var I, Removed: Integer;
begin
  if ADoc=nil then Exit;
  Removed:=ADoc.TabIndex;
  if FNativeHost<>nil then FNativeHost.FocusControl(nil);
  FDocuments.Remove(ADoc);
  { Presentation/session objects outlive their controls, so detach them before
    RemovePage frees the retained page visual tree. }
  ReleaseDocumentRendition(ADoc);
  FDocumentTabs.RemovePage(Removed);
  for I:=0 to FConsoles.Count-1 do
    if TAFileManagerConsoleDocument(FConsoles[I]).TabIndex>Removed then
      Dec(TAFileManagerConsoleDocument(FConsoles[I]).TabIndex);
  for I:=0 to FDocuments.Count-1 do
    if TAFileManagerDocument(FDocuments[I]).TabIndex>Removed then
      Dec(TAFileManagerDocument(FDocuments[I]).TabIndex);
  ADoc.Free;
  UpdateWorkspacePendingWork;
  if FDocumentTabs.SelectedIndex=0 then SetStatus('Files');
end;

procedure TAFileManagerController.RequestCloseDocument(ADoc: TAFileManagerDocument);
begin
  if (ADoc=nil) or (FPendingCloseDocument<>nil) or
     (FDeferredCloseDocument<>nil) then Exit;
  if ADoc.Editor.Text=ADoc.OriginalText then
  begin QueueCloseDocument(ADoc); Exit; end;
  FPendingCloseDocument:=ADoc;
  FDocumentTabs.SelectedIndex:=ADoc.TabIndex;
  FSaveChangesDialog.ShowForDocument(ExtractFileName(ADoc.Path));
end;

procedure TAFileManagerController.SaveChoiceMade(ASender: TArosaControl;
  AChoice: TArosaSaveChoice);
var Doc: TAFileManagerDocument;
begin
  Doc:=FPendingCloseDocument;
  FPendingCloseDocument:=nil;
  if Doc=nil then Exit;
  if AChoice=ascCancel then
  begin FClosingApplication:=False; Exit; end;
  if (AChoice=ascSave) and not SaveDocument(Doc) then
  begin FClosingApplication:=False; Exit; end;
  QueueCloseDocument(Doc);
end;

procedure TAFileManagerController.ContinueApplicationClose;
var
  I: Integer;
  Doc: TAFileManagerDocument;
  WorkspacePrototype: TAFileManagerWorkspacePrototype;
begin
  if not FClosingApplication or (FDeferredCloseDocument<>nil) then Exit;
  for I:=FDocuments.Count-1 downto 0 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if Doc.Editor.Text<>Doc.OriginalText then
    begin RequestCloseDocument(Doc); Exit; end;
  end;
  UpdateWorkspacePendingWork;
  if FWorkspaceSessionMode then
  begin
    FClosingApplication:=False;
    if Assigned(FWorkspaceSessionClose) then FWorkspaceSessionClose();
    Exit;
  end;

  { The primary controller owns all workspace prototypes.  A request to exit
    the primary AFileManager is therefore a PROCESS exit, not merely a request
    to hide its primary window.  Keeping a hidden controller alive left the
    AROS shell redirection handle (for example logs/events.log) open after the
    visible windows had disappeared.  Close every child workspace while we are
    safely in the application's idle phase, then terminate the event loop. }
  if FWorkspacePrototypes<>nil then
    for I:=FWorkspacePrototypes.Count-1 downto 0 do
    begin
      WorkspacePrototype:=
        TAFileManagerWorkspacePrototype(FWorkspacePrototypes[I]);
      if (WorkspacePrototype<>nil) and WorkspacePrototype.IsOpen then
      begin
        Diagnostic('APP-CLOSE closing workspace '+WorkspacePrototype.WorkspaceId);
        WorkspacePrototype.Close;
      end;
    end;

  { Diagnostics are already detached from filesystem persistence. Hand the
    final records to the broker if it is available, but never wait for the
    logger or a file. }
  StopInstanceDiagnostics;
  {$IFNDEF AROS}
  try Flush(Output); except end;
  {$ENDIF}

  if (FNativeHost<>nil) and (not FNativeHost.Closed) then
    FNativeHost.Close;

  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) then
    FNativeHost.Application.Loop.Terminate;
end;

procedure TAFileManagerController.ApplicationCloseIdle(var AMoreWorkPending: Boolean);
begin
  Diagnostic('APP-CLOSE idle begin');
  if FApplicationCloseIdleAttached and (FNativeHost<>nil) and
     (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@ApplicationCloseIdle);
    FApplicationCloseIdleAttached:=False;
  end;
  FApplicationCloseQueued:=False;
  { Secondary native hosts must be closed while the application/event loop is
    still alive.  Doing this in idle avoids destroying an AROS window while
    its close/button event is still being dispatched.  Popped-out application
    frames are secondary native windows too: leaving them alive until the
    controller destructor runs after the loop has returned can leave native
    callbacks/input bindings pointing at an application that is already
    shutting down (AROS illegal-instruction failure on process close). }
  if FHelpSystem<>nil then FHelpSystem.CloseForApplicationExit;
  while (FConsoles<>nil) and (FConsoles.Count>0) do
  begin
    Diagnostic('APP-CLOSE closing console frame id='+
      IntToStr(TAFileManagerConsoleDocument(FConsoles[FConsoles.Count-1]).Id));
    CloseConsoleDocumentNow(
      TAFileManagerConsoleDocument(FConsoles[FConsoles.Count-1]));
  end;
  ContinueApplicationClose;
  AMoreWorkPending:=False;
  Diagnostic('APP-CLOSE idle end');
end;

procedure TAFileManagerController.RequestApplicationClose;
begin
  if FPendingCloseDocument<>nil then Exit;
  FClosingApplication:=True;
  Diagnostic('APP-CLOSE requested');
  if FExternalTransferActive then
  begin
    { The transfer owns only its job-file snapshot and runs in another
      AmigaDOS Process. It must never hold the AFileManager UI/process open.
      Detach the UI-side poller and allow the worker to finish or time out on
      its own. Do NOT delete the job file here: the new process may not have
      consumed it yet. }
    Diagnostic('APP-CLOSE detaching active external transfer job='+FExternalTransferJobPath);
    FExternalTransferActive:=False;
    if FTransferIdleAttached and (FNativeHost<>nil) and
       (FNativeHost.Application<>nil) and
       (FNativeHost.Application.Loop<>nil) then
      FNativeHost.Application.Loop.RemoveIdleHandler(@TransferIdle);
    FTransferIdleAttached:=False;
  end;
  if FTransferJob<>nil then
  begin
    FTransferJob.RequestCancel;
    if FTransferCancelButton<>nil then FTransferCancelButton.Enabled:=False;
    SetStatus('Cancelling the active transfer before closing AFileManager...');
    Exit;
  end;
  if FApplicationCloseQueued then Exit;
  FApplicationCloseQueued:=True;
  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.AddIdleHandler(@ApplicationCloseIdle);
    FApplicationCloseIdleAttached:=True;
  end
  else
  begin
    FApplicationCloseQueued:=False;
    ContinueApplicationClose;
  end;
end;

procedure TAFileManagerController.BeginInternalEdit(const APath: string);
var I: Integer; Doc: TAFileManagerDocument; Content: string;
    Page: TArosaTabPage; Column: TArosaColumnPanel;

  function NewDocumentButton(const ACaption, AHint, ACommand: string;
    AClick: TArosaClickEvent): TArosaButton;
  var Img: TArosaPlatformHandle; Src: TArosaRect;
  begin
    Result:=TArosaButton.CreateControl(FTheme,FFonts);
    Result.Caption:=ACaption;
    Result.Hint:=AHint;
    Result.ContextTitle:=ACaption;
    Result.OnClick:=AClick;
    Result.SetConstraintHeight(asmFixed,ArosaCoord(30));
    if ContextCommandIcon(Result,ACommand,Img,Src) and (Img<>ArosaNilHandle) then
    begin
      Result.Image:=Img;
      Result.ImageSourceRect:=Src;
      Result.Caption:='';
      Result.SetConstraintWidth(asmFixed,ArosaCoord(36));
    end
    else
      Result.SetConstraintWidth(asmFixed,ArosaCoord(82));
    Doc.Toolbar.AddVisual(Result);
  end;

begin
  if APath='' then Exit;
  if IsProviderLocation(APath) then
  begin
    SetStatus('Editing remote resources is not yet exposed by Location Service: '+APath);
    Exit;
  end;
  if (FPaths=nil) or FPaths.IsDirectory(APath) or (FDocumentTabs=nil) then Exit;
  { Activating an already-open document retains its unsaved text. }
  for I:=0 to FDocuments.Count-1 do
  begin
    Doc:=TAFileManagerDocument(FDocuments[I]);
    if SameText(Doc.Path,APath) then
    begin
      FDocumentTabs.SelectedIndex:=Doc.TabIndex;
      SetStatus('Editing: '+APath);
      Exit;
    end;
  end;
  if (FFiles=nil) or not FFiles.ReadAllText(APath,Content) then
  begin
    SetStatus('Unable to read file for editing: '+APath);
    Exit;
  end;
  Doc:=TAFileManagerDocument.Create;
  Doc.Path:=APath;
  Doc.OriginalText:=Content;
  Page:=TArosaTabPage.Create;
  Page.Caption:=ExtractFileName(APath);
  Page.SetConstraintHeight(asmStar,ArosaCoord(1));
  Doc.Editor:=TArosaEditor.CreateControl(FTheme,FFonts);
  ConfigureDocumentEditor(Doc.Editor);
  Doc.Editor.Language:=EditorLanguageForPath(APath);
  Doc.Editor.Text:=Content;
  Doc.Page:=Page;
  Column:=TArosaColumnPanel.Create;
  Column.SetConstraintWidth(asmStar,ArosaCoord(1));
  Column.SetConstraintHeight(asmStar,ArosaCoord(1));

  { Document toolbar: a sibling of the editor/rendition splitter. This is the
    stable composition boundary for Save, Close, Find, Replace, Go to line
    and Rendition; the editor itself no longer owns this application chrome. }
  Doc.Toolbar:=TArosaRowPanel.Create;
  Doc.Toolbar.Spacing:=ArosaCoord(4);
  Doc.Toolbar.SetConstraintWidth(asmStar,ArosaCoord(1));
  Doc.Toolbar.SetConstraintHeight(asmFixed,ArosaCoord(34));
  Doc.SaveButton:=NewDocumentButton('Save',
    LocalText('afilemanager_hint_editor_save','Save this document'),
    'Editor.Save',@DocumentSaveClick);
  Doc.CloseButton:=NewDocumentButton('Close',
    LocalText('afilemanager_hint_editor_close','Close this document'),
    'Editor.Close',@DocumentCloseClick);
  Doc.FindButton:=NewDocumentButton('Find',
    LocalText('afilemanager_hint_editor_find','Find text (Ctrl+F)'),
    'Search.Find',@DocumentFindClick);
  Doc.ReplaceButton:=NewDocumentButton('Replace',
    LocalText('afilemanager_hint_editor_replace','Find and replace text (Ctrl+H)'),
    'Search.Replace',@DocumentReplaceClick);
  Doc.GoToLineButton:=NewDocumentButton('Go to line',
    LocalText('afilemanager_hint_editor_goto','Go to a line (Ctrl+G)'),
    'Search.GoToLine',@DocumentGoToLineClick);
  Doc.RenditionButton:=NewDocumentButton('Rendition',
    LocalText('afilemanager_hint_editor_rendition','Show or hide document rendition'),
    'View.Rendition',@DocumentRenditionClick);
  Column.AddVisual(Doc.Toolbar);

  Doc.RenditionHost:=TArosaColumnPanel.Create;
  Doc.RenditionHost.SetConstraintWidth(asmStar,ArosaCoord(1));
  Doc.RenditionHost.SetConstraintHeight(asmStar,ArosaCoord(1));

  Doc.RenditionSplit:=TArosaSplitterHost.Create;
  Doc.RenditionSplit.SetConstraintWidth(asmStar,ArosaCoord(1));
  Doc.RenditionSplit.SetConstraintHeight(asmStar,ArosaCoord(1));
  Doc.RenditionVisible:=FEditorRenditionVisible;
  if Doc.RenditionVisible then
    Doc.RenditionSplit.SetPanes(Doc.Editor,Doc.RenditionHost)
  else
    Doc.RenditionSplit.SetPanes(Doc.Editor,nil);
  Doc.RenditionSplit.SetInitialPercent(50);

  Column.AddVisual(Doc.RenditionSplit);
  Page.AddVisual(Column);
  RefreshDocumentRendition(Doc);
  Doc.TabIndex:=FDocumentTabs.AddTabPage(Page);
  FDocuments.Add(Doc);
  FDocumentTabs.SelectedIndex:=Doc.TabIndex;
  SetStatus('Editing: '+APath+' (Ctrl+S to save)');
end;

function TAFileManagerController.SelectedRowIsDirectory(AView, AIndex: Integer): Boolean;
var
  L: TArosaFilteredListView;
  R: TArosaListRow;
begin
  Result:=False;
  L:=ViewList(AView);
  if (L=nil) or (AIndex<0) or (AIndex>=L.ItemCount) then Exit;
  R:=L.VisibleRowsView[AIndex];
  if R=nil then Exit;
  Result:=SameText(Copy(R.Text,1,3),'DIR');
end;

function TAFileManagerController.PreviewPageActive(AView: Integer): Boolean;
var Tabs: TArosaTabControl;
begin
  Result:=False;
  if not FPreviewVisible then Exit;
  if AView=0 then Tabs:=FMetadataTabs else Tabs:=FRightMetadataTabs;
  { Preview is page 0; when Metadata is the selected page, selecting files must
    never parse/layout/render HTML in the background. }
  Result:=(Tabs=nil) or (Tabs.SelectedIndex=0);
end;

procedure TAFileManagerController.UpdateSelectionMetadata(AView: Integer);
var L: TArosaFilteredListView; P: string;
begin
  if not FMetadataVisible then Exit;
  L:=ViewList(AView);
  if (L=nil) or (L.SelectedIndex<0) then
  begin
    if AView=0 then begin if FMetadataView<>nil then FMetadataView.ClearMetadata; end
    else begin if FRightMetadataView<>nil then FRightMetadataView.ClearMetadata; end;
    Exit;
  end;
  P:=SelectedPath(AView,L.SelectedIndex);
  if (P='') or (Pos('exec:',LowerCase(Trim(P)))=1) or
     (Pos('internal:',LowerCase(Trim(P)))=1) then Exit;
  ShowProperties(AView,P);
end;

procedure TAFileManagerController.PreviewTabsChanged(ASender: TObject; AIndex: Integer);
var V: Integer;
begin
  if ASender=FRightMetadataTabs then V:=1 else V:=0;
  if AIndex=0 then QueuePreview(V)
  else
  begin
    FPendingPreviewActive[V]:=False;
    FPendingPreviewPath[V]:='';
    UpdateSelectionMetadata(V);
  end;
end;

procedure TAFileManagerController.QueuePreview(AView: Integer);
var
  L: TArosaFilteredListView;
  P: string;
begin
  if (AView<0) or (AView>1) then Exit;
  L:=ViewList(AView);

  { Selection and Metadata must stay cheap.  A full presentation is queued
    only when the Preview page is actually active.  This prevents HTML parsing
    and layout from running merely because the user selected a file while
    inspecting Metadata. }
  if not PreviewPageActive(AView) then
  begin
    FPendingPreviewActive[AView]:=False;
    FPendingPreviewPath[AView]:='';
    UpdateSelectionMetadata(AView);
    Exit;
  end;

  if (L=nil) or (L.SelectedIndex<0) then
  begin
    FPendingPreviewActive[AView]:=False;
    FPendingPreviewPath[AView]:='';
    if FDisplayedPreviewPath[AView]<>'' then
      UpdatePreview(AView);
    Exit;
  end;

  P:=SelectedPath(AView,L.SelectedIndex);

  { Workspace/application invocation targets are semantic resources, not
    AmigaDOS paths. Selecting one must never feed "exec:" or "internal:"
    into preview/metadata file probes: DOS otherwise interprets the scheme as
    a volume name and opens the blocking "Please insert volume exec" requester.
    Activation remains handled by ActivateItem. }
  if (Pos('exec:',LowerCase(Trim(P)))=1) or
     (Pos('internal:',LowerCase(Trim(P)))=1) then
  begin
    FPendingPreviewActive[AView]:=False;
    FPendingPreviewPath[AView]:='';
    FDisplayedPreviewPath[AView]:=P;
    if AView=0 then
    begin
      if FLeftPreview<>nil then FLeftPreview.Text:=
        LocalText('afilemanager_preview_application_module','Application module - double click to open');
    end
    else if FRightPreview<>nil then FRightPreview.Text:=
      LocalText('afilemanager_preview_application_module','Application module - double click to open');
    Exit;
  end;

  { A selection callback is part of the input path.  Never parse/render a file
    presentation synchronously from it.  Since the HTML/font work became more
    accurate, doing that made list selection appear frozen: each click could
    tear down and rebuild an HTML presentation before the next input event.

    Directories are metadata-only and remain immediate. }
  if SelectedRowIsDirectory(AView,L.SelectedIndex) then
  begin
    FPendingPreviewActive[AView]:=False;
    FPendingPreviewPath[AView]:='';
    if not SameText(FDisplayedPreviewPath[AView],P) then
      UpdatePreview(AView);
    Exit;
  end;

  { Re-selecting the already displayed resource must not destroy/recreate its
    presentation.  The runtime log showed repeated PREVIEW/PRESENTATION work
    for the same path. }
  if SameText(FDisplayedPreviewPath[AView],P) then
  begin
    FPendingPreviewActive[AView]:=False;
    FPendingPreviewPath[AView]:='';
    Exit;
  end;

  { Debounce *all* file previews.  Local files use a short delay; remote files
    use a longer delay in PreviewIdle.  Fast list navigation therefore updates
    selection immediately and only previews the item on which the user settles. }
  FPendingPreviewPath[AView]:=P;
  FPendingPreviewTick[AView]:=GetTickCount64;
  FPendingPreviewActive[AView]:=True;

  if AView=0 then
  begin
    if FLeftPreview<>nil then
      FLeftPreview.Text:=LocalText('afilemanager_preview_pending','Preview pending: ')+ExtractFileName(P);
  end
  else if FRightPreview<>nil then
    FRightPreview.Text:=LocalText('afilemanager_preview_pending','Preview pending: ')+ExtractFileName(P);
end;

procedure TAFileManagerController.PreviewIdle(var AMoreWorkPending: Boolean);
const
  LocalPreviewDelayMs = 160;
  RemotePreviewDelayMs = 350;
var
  V, NavView: Integer;
  DelayMs: QWord;
  L: TArosaFilteredListView;
  P, NavPath: string;
begin
  { Logging is drained only from idle. Neither process nor per-instance logs
    retain an open file handle between pumps. }
  Arosa.Services.Diagnostics.DiagnosticPump;
  FlushInstanceDiagnostics(False);

  { 0.8.6.5: the default workspace has a taskbar too, on the default screen.
    A workspace on its own screen is given its bar by that screen; a second
    AFileManager started from a workspace brings none. }
  if (not FTaskbarTried) and (not FWorkspaceSessionMode) and
     (FNativeHost<>nil) and (not FNativeHost.Closed) then
  begin
    FTaskbarTried:=True;
    try
      if not StartedFromWorkspace then
        OpenTaskbar(ArosaNilHandle,LocalText('afilemanager_workspace_default','AROSA'));
    except
      on E: Exception do
      begin
        { 0.8.6.6: a taskbar that cannot open must not cost the file manager
          its idle turn - navigation and program starts are carried out here }
        Diagnostic('TASKBAR failed: '+E.ClassName+': '+E.Message);
        try CloseTaskbar; except end;
      end;
    end;
  end;
  { volumes that come and go }
  if not FVolumesFailed then
    try
      PollVolumes;
    except
      on E: Exception do
      begin
        FVolumesFailed:=True;
        Diagnostic('VOLUME watch stopped: '+E.ClassName+': '+E.Message);
      end;
    end;
  { 0.8.6.6: a module or a placement changed in another window }
  if FSeenMembershipGeneration<>GWorkspaceMembershipGeneration then
    try
      SyncWorkspaceMembership;
    except
      on E: Exception do
        Diagnostic('WORKSPACE sync failed: '+E.ClassName+': '+E.Message);
    end;

  { Application/module activation is deferred too. Never run C:Run from the
    retained list MouseDown/activate callback. }
  if FPendingExecLaunch then
  begin
    P:=FPendingExecTarget;
    FPendingExecLaunch:=False;
    FPendingExecTarget:='';
    if (P<>'') and (FShellService<>nil) then
    begin
      FLastExecLaunchTarget:=P;
      FLastExecLaunchTick:=GetTickCount64;
      if FShellService.LaunchIndependentArgs(P,WorkspaceLaunchArguments) then
        SetStatus(LocalText('afilemanager_opened','Opened')+': '+P)
      else
        SetStatus(LocalText('afilemanager_open_failed','Could not open')+': '+P);
    end;
    FPendingExecWorkspace:='';
    AMoreWorkPending:=True;
    Exit;
  end;

  { Navigation requested by list activation OR breadcrumb activation is
    intentionally executed from idle. The originating input callback has now
    returned to the event loop, so NavigateView may safely rebuild retained
    list rows and breadcrumb segments. }
  if FPendingNavigateActive then
  begin
    NavView:=FPendingNavigateView;
    NavPath:=FPendingNavigatePath;
    FPendingNavigateActive:=False;
    FPendingNavigatePath:='';
    if ArosaTraceEnabled then
      ArosaTrace('FILEMANAGER','NAV-DEFERRED view='+IntToStr(NavView)+
        ' path='+NavPath);
    NavigateView(NavView,NavPath);
    AMoreWorkPending:=True;
    Exit;
  end;

  for V:=0 to 1 do
  begin
    if not FPendingPreviewActive[V] then Continue;
    if IsProviderLocation(FPendingPreviewPath[V]) then
      DelayMs:=RemotePreviewDelayMs
    else
      DelayMs:=LocalPreviewDelayMs;
    if GetTickCount64-FPendingPreviewTick[V] < DelayMs then Continue;

    L:=ViewList(V);
    if (L=nil) or (L.SelectedIndex<0) then
    begin
      FPendingPreviewActive[V]:=False;
      FPendingPreviewPath[V]:='';
      Continue;
    end;

    P:=SelectedPath(V,L.SelectedIndex);
    if P<>FPendingPreviewPath[V] then
    begin
      FPendingPreviewPath[V]:=P;
      FPendingPreviewTick[V]:=GetTickCount64;
      Continue;
    end;

    FPendingPreviewActive[V]:=False;
    FPendingPreviewPath[V]:='';
    { 0.8.6.3: already shown (something else brought the preview up while
      this request waited): it is not torn down and built a second time }
    if PreviewPageActive(V) and SameText(FDisplayedPreviewPath[V],P) and
       (((V=0) and (FLeftPresentation<>nil)) or ((V=1) and (FRightPresentation<>nil))) then Continue;
    if PreviewPageActive(V) then UpdatePreview(V)
    else UpdateSelectionMetadata(V);
  end;
  UpdateAudioPlaybackTelemetry;
  if AMoreWorkPending then ;
end;

procedure TAFileManagerController.UpdatePreview(AView: Integer);
{ 0.8.6.3: replacing what a pane shows changes the form in a dozen places
  (the old presentation out, the new one in, the command bar rebound);
  the form is laid out once for all of it. }
begin
  if FNativeHost<>nil then FNativeHost.BeginLayoutBatch;
  try
    UpdatePreviewNow(AView);
  finally
    if FNativeHost<>nil then FNativeHost.EndLayoutBatch;
  end;
end;

procedure TAFileManagerController.UpdatePreviewNow(AView: Integer);
var
  L: TArosaFilteredListView;
  P, OriginalP, TextValue, LoadError: string;
  TextTarget: TArosaEditor;
  ImageTarget: TArosaImageBox;
  ImageResource, OldResource: TArosaImageResource;
  Metadata: TArosaResourceMetadata;
  MetadataTarget: TArosaMetadataView;
  PreviewKind: TArosaPreviewKind;
  Pres: TArosaPresentation;
  PresPage: TArosaTabPage;
  ContentDesc: TArosaContentDescriptor;
  PresError: string;
  RemoteSize, RemoteLimit: Int64;
  AudioInfo: TArosaAudioProbeInfo;
  AudioError, PlaybackText: string;
  AudioBars: TArosaMusicBars;
  AudioHost: TArosaColumnPanel;
  AudioSummary, AudioPlayback: TArosaLabel;
  SpectrumValues: array[0..AROSA_AUDIO_SPECTRUM_BANDS-1] of Double;
  SI: Integer;
  PhaseTick: QWord;
begin
  { Full preview work is forbidden while Metadata is the active page.  This is
    a hard lifecycle boundary: callers cannot accidentally parse HTML, decode
    images or materialise remote content from selection/metadata paths. }
  if not PreviewPageActive(AView) then
  begin
    UpdateSelectionMetadata(AView);
    Exit;
  end;
  L := ViewList(AView);
  if AView=0 then
  begin
    TextTarget:=FLeftPreview;
    ImageTarget:=FLeftImagePreview;
    OldResource:=FLeftImageResource;
    MetadataTarget:=FMetadataView;
    AudioHost:=FLeftAudioHost; AudioSummary:=FLeftAudioSummary; AudioPlayback:=FLeftAudioPlayback;
  end
  else
  begin
    TextTarget:=FRightPreview;
    ImageTarget:=FRightImagePreview;
    OldResource:=FRightImageResource;
    MetadataTarget:=FRightMetadataView;
    AudioHost:=FRightAudioHost; AudioSummary:=FRightAudioSummary; AudioPlayback:=FRightAudioPlayback;
  end;
  if AView=0 then PresPage:=FPreviewPage else PresPage:=FRightPreviewPage;
  if AView=0 then Pres:=FLeftPresentation else Pres:=FRightPresentation;
  if Pres<>nil then
  begin
    if ArosaTraceEnabled then ArosaTrace('PRESENTATION','detach view='+IntToStr(AView));
    if (PresPage<>nil) and (Pres.Control<>nil) then
    begin
      PresPage.RemoveVisual(Pres.Control);
      PresPage.InvalidateLayout;
      PresPage.InvalidatePaint;
    end;
    if ViewCommandBar(AView)<>nil then ViewCommandBar(AView).Unbind;
    Pres.Close; Pres.Free;
    if AView=0 then FLeftPresentation:=nil else FRightPresentation:=nil;
  end;
  { the bar follows what the pane shows; rebound below when applicable }
  if ViewCommandBar(AView)<>nil then ViewCommandBar(AView).Unbind;
  if (L=nil) or (TextTarget=nil) or (ImageTarget=nil) then Exit;
  { Generic textual preview uses the standard AROSA editor surface.
    Enable its semantic highlighting by default; specialised Presentation
    Service providers (HTML, images, AmigaGuide, archive, etc.) replace or
    hide this surface when they own presentation of the content. }
  TextTarget.ReadOnly:=True;
  TextTarget.Multiline:=True;
  TextTarget.Highlighting:=True;
  TextTarget.Language:='auto';

  ImageTarget.Bitmap := ArosaNilHandle;
  ImageTarget.Visible := False;
  if AudioHost<>nil then AudioHost.Visible:=False;
  TextTarget.Visible := True;
  if AView=0 then FLeftImageResource:=nil else FRightImageResource:=nil;
  if OldResource<>nil then
  begin
    ArosaTrace('IMAGE-PREVIEW','release old view='+IntToStr(AView)+
      ' resource='+IntToStr(PtrUInt(OldResource)));
    OldResource.Free;
  end;

  Metadata:=nil;
  if L.SelectedIndex<0 then
  begin
    FDisplayedPreviewPath[AView]:='';
    if AView=0 then begin if FLeftPreviewTitle<>nil then FLeftPreviewTitle.Text:=LocalText('afilemanager_preview_none','No preview selection'); end
    else begin if FRightPreviewTitle<>nil then FRightPreviewTitle.Text:=LocalText('afilemanager_preview_none','No preview selection'); end;
    TextTarget.Text := LocalText('afilemanager_preview_empty','Preview: no item selected');
    if MetadataTarget<>nil then MetadataTarget.ClearMetadata;
    StopCurrentSound;
  end
  else
  begin
    P := SelectedPath(AView, L.SelectedIndex);
    FDisplayedPreviewPath[AView]:=P;
    Diagnostic('PREVIEW selected view='+IntToStr(AView)+
      ' index='+IntToStr(L.SelectedIndex)+' path='+P);
    if AView=0 then begin if FLeftPreviewTitle<>nil then FLeftPreviewTitle.Text:=ExtractFileName(P); end
    else begin if FRightPreviewTitle<>nil then FRightPreviewTitle.Text:=ExtractFileName(P); end;

    { Selecting a provider directory must never try to materialise it as a
      file.  Ask Location Service for the logical item type first and keep the
      preview on metadata-only content for directories. }
    if IsProviderLocation(P) and SelectedRowIsDirectory(AView,L.SelectedIndex) then
    begin
      TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P;
      if MetadataTarget<>nil then
      begin
        Metadata:=TArosaResourceMetadata.Create;
        Metadata.AddAttribute('resource.name','arosa_metadata_name','general',ExtractFileName(P),10);
        Metadata.AddAttribute('resource.location','arosa_metadata_location','general',P,20);
        Metadata.AddAttribute('resource.kind','Type','general','Directory',30);
        MetadataTarget.SetMetadata(Metadata);
        Metadata:=nil;
      end;
      StopCurrentSound;
      Exit;
    end;

    { 0.7.5.10: a remote file is previewed when the user selects it with the
      preview open (a deliberate act - never on hover, repaint or context
      menu), through the Content Service (bounded, cached, counted).  Above
      [Preview] RemoteAutoLoadKB the preview waits for an explicit "Load
      preview".  Archives are listed in portable code (no external
      archiver), so this no longer starts child programs while browsing. }
    if IsProviderLocation(P) and RemotePreviewDeferred(AView,P,RemoteSize,RemoteLimit) then
    begin
      TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P+LineEnding;
      TextTarget.Text:=TextTarget.Text+
        Format(LocalText('afilemanager_preview_remote_large',
          'Remote file of %d KB - larger than the automatic preview limit of %d KB.'),
          [RemoteSize div 1024,RemoteLimit div 1024])+LineEnding;
      TextTarget.Text:=TextTarget.Text+
        LocalText('afilemanager_preview_remote_large_action','"Load preview" downloads it and shows its preview.');
      if MetadataTarget<>nil then
      begin
        Metadata:=TArosaResourceMetadata.Create;
        Metadata.AddAttribute('resource.name','arosa_metadata_name','general',ExtractFileName(P),10);
        Metadata.AddAttribute('resource.location','arosa_metadata_location','general',P,20);
        Metadata.AddAttribute('resource.size','arosa_metadata_size','general',IntToStr(RemoteSize),30);
        MetadataTarget.SetMetadata(Metadata);
        Metadata:=nil;
      end;
      if (ViewCommandBar(AView)<>nil) and (FLoadPreviewCmd[AView]<>nil) then
        ViewCommandBar(AView).Bind(FLoadPreviewCmd[AView],FLoadPreviewCmd[AView]);
      StopCurrentSound;
      Exit;
    end;

    { Presentation Service now owns the Content -> Resource -> DataTypes
      preparation path. AFileManager supplies only the logical resource
      identity. Provider bytes are materialised through Content Service and
      Location Service, so no scheme:// URI reaches DataTypes or a native
      presentation provider. If no presentation provider accepts the item,
      AContent still supplies the already prepared local representation for
      the generic metadata/text fallback below. }
    OriginalP:=P;
    Pres:=nil; PresError:='';
    FillChar(ContentDesc,SizeOf(ContentDesc),0);
    if FPresentationService<>nil then
    begin
      PhaseTick:=GetTickCount64;
      if FPresentationService.CreatePresentationForLocation(OriginalP,apmPreview,True,
        Pres,ContentDesc,PresError) and (Pres<>nil) then
      begin
        P:=ContentDesc.PhysicalPath;
        Diagnostic('PRESENTATION prepared location='+OriginalP+' path='+P+
          ' cached='+BoolToStr(ContentDesc.Cached,True)+
          ' create-ms='+IntToStr(GetTickCount64-PhaseTick));
        ArosaTrace('PRESENTATION','created view='+IntToStr(AView)+
          ' location='+OriginalP+' path='+P);
        { Load a presentation completely before attaching its control to the live
          visual tree.  HTML LoadHtmlFile invalidates layout/paint; doing that
          after AddVisual allowed a half-loaded HTML view to participate in a
          retained-tree layout pass while PreviewIdle was still running.  On
          AROS that could starve input, leave the old "Preview pending" surface
          visible, and turn subsequent clicks into a backlog of activations. }
        Pres.OnMessage:=@PresentationMessage;
        if (PresPage<>nil) and (Pres.Control<>nil) then
        begin
          Pres.Control.SetConstraintHeight(asmStar,ArosaCoord(1));
          Pres.Control.SetConstraintWidth(asmStar,ArosaCoord(1));
          PhaseTick:=GetTickCount64;
          if not Pres.Load(PresError) then
          begin
            Pres.Close; Pres.Free; Pres:=nil;
            TextTarget.Visible:=True;
            TextTarget.Text:='Presentation load failed: '+PresError;
            PresPage.InvalidateLayout;
            PresPage.InvalidatePaint;
          end
          else
          begin
            Diagnostic('PRESENTATION load-ms='+IntToStr(GetTickCount64-PhaseTick)+
              ' location='+OriginalP);
            { Only a fully loaded presentation enters the visual tree. }
            PresPage.AddVisual(Pres.Control);
            TextTarget.Visible:=False;
            ImageTarget.Visible:=False;
            PresPage.InvalidateLayout;
            PresPage.InvalidatePaint;
            if AView=0 then FLeftPresentation:=Pres else FRightPresentation:=Pres;
            PhaseTick:=GetTickCount64;
            if ViewCommandBar(AView)<>nil then ViewCommandBar(AView).Bind(Pres,Pres);
            Diagnostic('PRESENTATION commandbar-ms='+IntToStr(GetTickCount64-PhaseTick)+
              ' location='+OriginalP);
            if ArosaTraceEnabled then ArosaTrace('PRESENTATION','loaded view='+IntToStr(AView));
            if MetadataTarget<>nil then
            begin
              if FResources.ProbeMetadata(P,Metadata) then
              begin
                if OriginalP<>P then
                  Metadata.AddAttribute('content.location','arosa_metadata_location','general',OriginalP,5);
                MetadataTarget.SetMetadata(Metadata);
                Metadata:=nil;
              end
              else
                MetadataTarget.ClearMetadata;
            end;
            Exit;
          end;
        end;
      end;

      { A false result may simply mean that no specialised provider accepts
        the content. In that case the service has still prepared AContent and
        the generic fallback below can use it. A blank physical path means
        acquisition itself failed, which is terminal for provider resources. }
      if ContentDesc.PhysicalPath<>'' then
      begin
        P:=ContentDesc.PhysicalPath;
        Diagnostic('CONTENT prepared location='+OriginalP+' path='+P+
          ' cached='+BoolToStr(ContentDesc.Cached,True));
      end
      else if IsProviderLocation(OriginalP) then
      begin
        if PresError='' then PresError:='Content could not be prepared';
        TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+OriginalP+
          LineEnding+PresError;
        if MetadataTarget<>nil then
        begin
          Metadata:=TArosaResourceMetadata.Create;
          Metadata.AddAttribute('resource.name','arosa_metadata_name','general',ExtractFileName(OriginalP),10);
          Metadata.AddAttribute('resource.location','arosa_metadata_location','general',OriginalP,20);
          MetadataTarget.SetMetadata(Metadata);
          Metadata:=nil;
        end;
        StopCurrentSound;
        Exit;
      end;
    end
    else if IsProviderLocation(OriginalP) then
    begin
      TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+OriginalP+
        LineEnding+'Presentation Service unavailable';
      StopCurrentSound;
      Exit;
    end;

    if FResources=nil then
    begin
      Diagnostic('PREVIEW resources=nil path='+P);
      TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P;
      if MetadataTarget<>nil then MetadataTarget.ClearMetadata;
    end
    else if not FResources.ProbeMetadata(P,Metadata) then
    begin
      Diagnostic('PREVIEW ProbeMetadata FAILED path='+P);
      TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P;
      if MetadataTarget<>nil then MetadataTarget.ClearMetadata;
    end
    else
    begin
      PreviewKind:=Metadata.PreviewKind;
      Diagnostic('PREVIEW metadata path='+P+
        ' previewkind='+IntToStr(Ord(PreviewKind)));
      if OriginalP<>P then
        Metadata.AddAttribute('content.location','arosa_metadata_location','general',OriginalP,5);
      if MetadataTarget<>nil then begin MetadataTarget.SetMetadata(Metadata); Metadata:=nil; end;
      case PreviewKind of
        apkText:
          begin
            if not FResources.ReadText(P,TextValue) then
            begin
              { 0.5.110.59: say WHY (e.g. locked exclusively by a shell
                redirect).  Metadata above stays available regardless. }
              TextValue:='Unable to read content of '+ExtractFileName(OriginalP)+': '+
                FFiles.ExplainReadFailure(P)+'.';
              SetStatus(TextValue);
              Diagnostic('PREVIEW text-read FAILED path='+P);
            end;
            TextTarget.Text:=TextValue;
          end;
        apkImage:
          begin
            Diagnostic('PREVIEW image-branch path='+P+
              ' loader='+IntToStr(PtrUInt(FImageLoader)));
            ImageResource:=nil; LoadError:='';
            if (FImageLoader<>nil) and FImageLoader.TryLoadFile(P,ImageResource,LoadError) then
            begin
              if AView=0 then FLeftImageResource:=ImageResource else FRightImageResource:=ImageResource;
              ImageTarget.Bitmap:=ImageResource.Bitmap;
              ImageTarget.SourceRect:=ArosaRectXYWH(0,0,ImageResource.Width,ImageResource.Height);
              ImageTarget.AltText:=ExtractFileName(OriginalP)+' ('+IntToStr(ImageResource.Width)+' x '+IntToStr(ImageResource.Height)+')';
              TextTarget.Visible:=False; ImageTarget.Visible:=True;
              if ViewCommandBar(AView)<>nil then ViewCommandBar(AView).Bind(ImageTarget,ImageTarget);
              ImageTarget.InvalidateLayout;
              ImageTarget.InvalidatePaint;
              if PresPage<>nil then
              begin
                PresPage.InvalidateLayout;
                PresPage.InvalidatePaint;
              end;
              Diagnostic('PREVIEW image-load OK path='+P+
                ' size='+IntToStr(ImageResource.Width)+'x'+IntToStr(ImageResource.Height)+
                ' bitmap='+IntToStr(PtrUInt(ImageResource.Bitmap)));
            end
            else
            begin
              Diagnostic('PREVIEW image-load FAILED path='+P+
                ' error='+LoadError);
              TextTarget.Text:=LocalText('afilemanager_preview_image_error','Image preview unavailable: ')+LoadError;
            end;
          end;
        apkMetadata:
          begin
            if IsArchivePath(P) then
            begin
              { Passive browsing must never launch an external archiver.
                A crash in C:unzip used to surface while the user was merely
                selecting a remote ZIP/opening its context menu because the
                delayed preview ran `unzip -l` automatically.  Keep archive
                preview metadata-only; explicit archive commands remain the
                only place native archivers are started. }
              TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+OriginalP+
                LineEnding+'Archive metadata available. Use Expand to inspect or extract its contents.';
            end
            else
              TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P;
          end;
        apkAudio:
          begin
            StopCurrentSound;
            if AView=0 then AudioBars:=FMusicBars else AudioBars:=FRightMusicBars;
            TextTarget.Visible:=False;
            if AudioHost<>nil then AudioHost.Visible:=True;
            if AudioSummary<>nil then AudioSummary.Text:=ExtractFileName(OriginalP);
            if ArosaProbeAudioFile(P,AudioInfo,AudioError) then
            begin
              Diagnostic('PREVIEW audio-probe OK path='+P+' format='+AudioInfo.ContainerName+
                ' rate='+IntToStr(AudioInfo.SampleRate)+' channels='+IntToStr(AudioInfo.Channels)+
                ' spectrum='+BoolToStr(AudioInfo.SpectrumValid,True));
              if AudioSummary<>nil then
              begin
                AudioSummary.Text:=ExtractFileName(OriginalP)+'  |  '+AudioInfo.ContainerName+'  |  '+
                  IntToStr(AudioInfo.Channels)+' ch  |  '+
                  IntToStr(AudioInfo.SampleRate)+' Hz';
                if AudioInfo.BitsPerSample>0 then
                  AudioSummary.Text:=AudioSummary.Text+'  |  '+IntToStr(AudioInfo.BitsPerSample)+' bit';
              end;
              if AudioBars<>nil then
              begin
                if AudioInfo.SpectrumValid then
                begin
                  for SI:=0 to AROSA_AUDIO_SPECTRUM_BANDS-1 do
                    SpectrumValues[SI]:=AudioInfo.Spectrum[SI];
                end
                else
                  for SI:=0 to AROSA_AUDIO_SPECTRUM_BANDS-1 do SpectrumValues[SI]:=0.0;
                AudioBars.SetLevels(SpectrumValues);
                AudioBars.Visible:=True;
                AudioBars.InvalidateLayout;
                AudioBars.InvalidatePaint;
              end;
            end
            else
            begin
              Diagnostic('PREVIEW audio-probe FAILED path='+P+' error='+AudioError);
              if AudioSummary<>nil then AudioSummary.Text:=ExtractFileName(OriginalP)+'  |  '+AudioError;
            end;
            FCurrentSound:=nil;
            if FSoundService<>nil then FCurrentSound:=FSoundService.PlayFile(P);
            FAudioPath:=P;
            FAudioPreviewView:=AView;
            FAudioBasePositionMS:=0;
            FAudioLastTelemetryTick:=0;
            if ArosaProbeAudioFile(P,AudioInfo,AudioError) then
              FAudioDurationMS:=AudioInfo.DurationMS
            else
              FAudioDurationMS:=0;
            if FCurrentSound<>nil then
            begin
              FAudioRunTick:=GetTickCount64;
              PlaybackText:='Playback: running';
            end
            else
            begin
              FAudioRunTick:=0;
              if (FSoundService<>nil) and (FSoundService.ProviderCount=0) then
                PlaybackText:='Playback: no audio output provider registered'
              else PlaybackText:='Playback: unavailable for this format';
            end;
            if AudioPlayback<>nil then AudioPlayback.Text:=PlaybackText;
            UpdateAudioPlaybackTelemetry;
            if AudioHost<>nil then begin AudioHost.InvalidateLayout; AudioHost.InvalidatePaint; end;
          end;
      else
        TextTarget.Text:=LocalText('afilemanager_preview_resource','Preview: ')+P;
      end;
      { Any non-audio selection settles the visualizer. }
      if PreviewKind<>apkAudio then StopCurrentSound;
    end;
  end;
  if Metadata<>nil then Metadata.Free;
  TextTarget.InvalidateLayout; TextTarget.InvalidatePaint;
  ImageTarget.InvalidateLayout; ImageTarget.InvalidatePaint;
end;

procedure TAFileManagerController.WindowPreviewChanged(ASender: TArosaControl);
var
  ShowPreview: Boolean;
begin
  ShowPreview := (FWindowFrame<>nil) and (FWindowFrame.PreviewPlacement<>0);
  if FWindowFrame<>nil then begin
    ApplyPreviewLayout(0,FWindowFrame.PreviewPlacement);
    ApplyPreviewLayout(1,FWindowFrame.PreviewPlacement);
  end;
  UpdatePreview(0);
  UpdatePreview(1);
  if FLeftColumn<>nil then FLeftColumn.InvalidateLayout;
  if FRightColumn<>nil then FRightColumn.InvalidateLayout;
  if FViewsHost<>nil then FViewsHost.InvalidateLayout;
  if ASender=nil then ;
end;

procedure TAFileManagerController.UnbindNativeHost;
begin
  { the taskbar is a window of the same application: it goes first }
  CloseTaskbar;
  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@PreviewIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@DocumentCloseIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@TestAutoCloseIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@ApplicationCloseIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@TransferIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@EnumerationIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@EndpointIdle);
    FNativeHost.Application.Loop.RemoveIdleHandler(@ConsoleExecutionIdle);
    FConsoleExecutionIdleAttached:=False;
    FTransferIdleAttached:=False;
    FEnumerationWorkerIdleAttached:=False;
    FApplicationCloseIdleAttached:=False;
    FApplicationCloseQueued:=False;
    FEndpointIdleAttached:=False;
  end;
  if FNativeHost<>nil then
  begin
    FNativeHost.OnActivate:=nil;
    FNativeHost.OnDeactivate:=nil;
  end;
  FNativeHost:=nil;
end;

procedure TAFileManagerController.DoDispose;
var ConsoleDoc: TAFileManagerConsoleDocument;
begin
  StopInstanceDiagnostics;
  if FWorkspaceStatusSource<>'' then
    ArosaWorkspaceStatus.ClearSource(FWorkspaceStatusSource);
  { 0.7.5.2: the host is freed before the controller, so FNativeHost may
    point at freed memory here - only forget it, never dereference it.
    Idle handlers are removed by UnbindNativeHost, which the program calls
    while the host is alive. }
  FNativeHost:=nil;
  if FTransferJob<>nil then FTransferJob.RequestCancel;
  if FEnumerationWorkerActive then
    ArosaFileEnumerationWorkerCancel(FEnumerationWorkerGeneration);
  FEnumerationWorkerActive:=False;
  FreeAndNil(FWorkerService);
  FreeAndNil(FTaskRunner);
  { An active native task must normally be allowed to report completion before
    shutdown. Application-close disables new transfers; this defensive branch
    avoids double ownership if disposal follows a completed job. }
  FTransferJob:=nil;
  SaveLayout;
  if FDocuments<>nil then
  begin
    while FDocuments.Count>0 do
    begin
      TAFileManagerDocument(FDocuments[FDocuments.Count-1]).Free;
      FDocuments.Delete(FDocuments.Count-1);
    end;
    FreeAndNil(FDocuments);
  end;
  FreeAndNil(FUndoSources);
  FreeAndNil(FUndoDestinations);
  SaveHistory;
  FreeAndNil(FColumnOrder);
  FreeAndNil(FVisibleColumns);
  FreeAndNil(FRecentLocations);
  if FLocationChanges<>nil then FLocationChanges.Unsubscribe(@LocationChanged);
  if FWorkspacePrototypes<>nil then
  begin
    while FWorkspacePrototypes.Count>0 do
    begin
      TObject(FWorkspacePrototypes[FWorkspacePrototypes.Count-1]).Free;
      FWorkspacePrototypes.Delete(FWorkspacePrototypes.Count-1);
    end;
    FreeAndNil(FWorkspacePrototypes);
  end;
  if (FWorkspaceRegistryPersistence<>nil) and (FWorkspaceRegistry<>nil) and
     (FWorkspaceRegistryPath<>'') then
    FWorkspaceRegistryPersistence.SaveRegistry(FWorkspaceRegistry,
      FWorkspaceRegistryPath);
  FWorkspaceModulesDialog:=nil; { owned by the window frame }
  FreeAndNil(FWorkspaceModules);
  FreeAndNil(FWorkspaceRegistryPersistence);
  FreeAndNil(FWorkspaceRegistry);
  FreeAndNil(FWorkspaces);
  FreeAndNil(FLocationChanges);
  FVirtualLocations:=nil; { owned by FLocations provider registry }
  FreeAndNil(FTaskbar);
  FreeAndNil(FVolumes);
  FreeAndNil(FVolumeNotices);
  FreeAndNil(FLauncherService);
  FreeAndNil(FStartMenuService);
  FreeAndNil(FShortcutService);
  FreeAndNil(FFavorites);
  FreeAndNil(FNetworkLocations);
  FreeAndNil(FFontService);
  FreeAndNil(FListMenuBase);
  FreeAndNil(FShortcutBindings);
  FreeAndNil(FRecentFiles);
  if FPlaceIconResources<>nil then
  begin
    while FPlaceIconResources.Count>0 do
    begin
      TArosaImageResource(FPlaceIconResources[FPlaceIconResources.Count-1]).Free;
      FPlaceIconResources.Delete(FPlaceIconResources.Count-1);
    end;
    FreeAndNil(FPlaceIconResources);
  end;
  ClearThumbnailCache(0);
  ClearThumbnailCache(1);
  if FIconCache<>nil then
  begin
    while FIconCache.Count>0 do
    begin
      if FIconCache.Objects[FIconCache.Count-1]<>nil then
        TArosaImageResource(FIconCache.Objects[FIconCache.Count-1]).Free;
      FIconCache.Delete(FIconCache.Count-1);
    end;
    FreeAndNil(FIconCache);
  end;
  if FToolbarIconResources<>nil then
  begin
    while FToolbarIconResources.Count>0 do
    begin
      TArosaImageResource(FToolbarIconResources[FToolbarIconResources.Count-1]).Free;
      FToolbarIconResources.Delete(FToolbarIconResources.Count-1);
    end;
    FreeAndNil(FToolbarIconResources);
  end;
  FLeftNavigationHistory:=nil;
  FRightNavigationHistory:=nil;
  { 0.7.13.0.0: surface records (their history chains belong to the
    history service) }
  if FSurfaces<>nil then
  begin
    while FSurfaces.Count>0 do
    begin
      TAFMSurface(FSurfaces[FSurfaces.Count-1]).Free;
      FSurfaces.Delete(FSurfaces.Count-1);
    end;
    FreeAndNil(FSurfaces);
  end;
  FSurfaceBar:=nil;
  FOperationHistory:=nil;
  if FResourceOperations<>nil then FResourceOperations.ResourceAccess:=nil;
  FResourceOperations:=nil;
  FSearchService:=nil;
  FResourceClipboard:=nil;
  FOperationHistory:=nil;
  FLeftNavigationHistory:=nil;
  FRightNavigationHistory:=nil;
  FHistoryService:=nil;
  { Console visuals are owned by their tab pages; sessions are owned by the
    console-document records.  Tabs are normally freed with the visual tree. }
  if FConsoleCloseIdleAttached and (FNativeHost<>nil) and (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@ConsoleCloseIdle);
    FConsoleCloseIdleAttached:=False;
  end;
  FDeferredCloseConsole:=nil;
  if FConsoles<>nil then
  begin
    while FConsoles.Count>0 do
    begin
      ConsoleDoc:=TAFileManagerConsoleDocument(FConsoles[FConsoles.Count-1]);
      if FApplicationFrames<>nil then
      begin
        if ConsoleDoc.EmbeddedFrame<>nil then
          FApplicationFrames.UnregisterHost(ConsoleDoc.EmbeddedFrame);
        if ConsoleDoc.FloatingFrame<>nil then
          FApplicationFrames.UnregisterHost(ConsoleDoc.FloatingFrame);
        if ConsoleDoc.FrameSession<>nil then
          FApplicationFrames.CloseSession(ConsoleDoc.FrameSession);
      end;
      if (ConsoleDoc.ProcessId<>0) and (FShellService<>nil) then
      begin
        FShellService.CancelShellLine(ConsoleDoc.ProcessId);
        FShellService.ReleaseShellLine(ConsoleDoc.ProcessId);
        ConsoleDoc.ProcessId:=0;
      end;
      ConsoleDoc.FrameSurface:=nil;
      ConsoleDoc.FrameSession:=nil;
      ConsoleDoc.Console:=nil;
      FreeAndNil(ConsoleDoc.FloatingFrame);
      ConsoleDoc.Session.Free;
      ConsoleDoc.Session:=nil;
      ConsoleDoc.Free;
      FConsoles.Delete(FConsoles.Count-1);
    end;
    FreeAndNil(FConsoles);
  end;
  FreeAndNil(FApplicationFrames);
  FConsole := nil; FShellSession := nil;
  FreeAndNil(FARexxService);
  FreeAndNil(FMacroService);
  FreeAndNil(FCommandService);
  FreeAndNil(FCommandTarget);
  FreeAndNil(FPendingDeleteItems);
  FreeAndNil(FCommandHistory);
  FreeAndNil(FHelpSystem);
  FConfigurationDialog:=nil; { owned by the window frame }
  FNameDialog:=nil;          { owned by the window frame }
  FInfoDialog:=nil;          { owned by the window frame }
  FreeAndNil(FWindowDescriptor);
  FreeAndNil(FGadgetDescriptor);
  FreeAndNil(FMenuDescriptor);
  FreeAndNil(FToolbarDescriptor);
  FreeAndNil(FFileDescriptor);
  FCapabilities := nil;
  FreeAndNil(FContext);
  { detach before release (the native image lifetime rule) }
  if FLeftImagePreview<>nil then FLeftImagePreview.Bitmap:=ArosaNilHandle;
  if FRightImagePreview<>nil then FRightImagePreview.Bitmap:=ArosaNilHandle;
  if FLeftImageResource<>nil then
  begin
    FLeftImageResource.Free;
    FLeftImageResource:=nil;
  end;
  if FRightImageResource<>nil then
  begin
    FRightImageResource.Free;
    FRightImageResource:=nil;
  end;
  if FLeftCommandBar<>nil then FLeftCommandBar.Unbind;
  if FRightCommandBar<>nil then FRightCommandBar.Unbind;
  FreeAndNil(FLoadPreviewCmd[0]);
  FreeAndNil(FLoadPreviewCmd[1]);
  { 0.6.1.6: a presentation's control must leave the visual tree BEFORE the
    presentation frees it.  Closing it in place left the page holding a
    freed child, which the form then visited when it was freed - a crash
    on quit with any presentation open (always, since images became
    presentations in 0.6.1.5). }
  ReleasePresentation(FLeftPresentation);
  ReleasePresentation(FRightPresentation);
  FreeAndNil(FPresentationService);
  { Resource metadata providers borrow shell-owned DataTypes, so dispose the
    resource graph before the shell service that owns those dependencies. }
  FreeAndNil(FLocationResourceAccess);
  { 0.7.5.9: what remote browsing cost this session (the evidence for "no
    uncontrolled repeated LIST/STAT/FETCH") }
  if FLocations<>nil then Diagnostic('SERVICES location cache at exit: '+FLocations.CacheStatsText);
  if FContent<>nil then Diagnostic('SERVICES content cache at exit: '+FContent.CacheStatsText);
  FreeAndNil(FContent);
  FreeAndNil(FLocations);
  FreeAndNil(FResources);
  if FSoundService<>nil then FSoundService.StopAll;
  FCurrentSound:=nil;
  FMusicBars:=nil;
  FRightMusicBars:=nil;
  FLocalization:=nil;
  FDataTypes:=nil;
  FSoundService:=nil;
  FreeAndNil(FShellService);
  FMetadataView:=nil; FRightMetadataView:=nil;
  FMetadataPage:=nil; FMetadataTabs:=nil; FRightMetadataTabs:=nil;
  FCommandService:=nil; FCommandTarget:=nil; FMacroService:=nil; FARexxService:=nil; FConsole:=nil;
  FreeAndNil(FImageTransforms);
  FreeAndNil(FImageLoader);
  FreeAndNil(FDescriptor);
  FStatus := nil; FLeftBrowserColumn:=nil; FRightBrowserColumn:=nil; FLeftPreviewSplit:=nil; FRightPreviewSplit:=nil; FOperationTabs := nil; FConsoleOperationsPage:=nil; FConsoleOperationsIndex:=-1;
  FDocumentTabMenuPage:=nil; FDocumentTabCloseButton:=nil; FDocumentTabMenu:=nil;
  FPrimaryContentSurface:=nil; FreeAndNil(FContentConsumer); FWindowFrame := nil; FCompactFont := nil; FFileFont := nil; FToolbarTabs := nil; FMenuPanel := nil; FMenuRootPanel:=nil; FMenuSubPanel:=nil; FPreviewMenuButton := nil;
  FLeftPreviewHost:=nil; FRightPreviewHost:=nil; FLeftImagePreview:=nil; FRightImagePreview:=nil;
  FRightList := nil; FLeftList := nil; FRightPath := nil; FLeftPath := nil;
  FLeftCrumbs := nil; FRightCrumbs := nil;
  FreeAndNil(FPendingItems); FreeAndNil(FConflictSources); FreeAndNil(FConflictDests);
  FreeAndNil(FConflictPlan);
  FreeAndNil(FDragSourceParents);
  FreeAndNil(FPendingDropItems);
  FreeAndNil(FPermissionService);
  FreeAndNil(FMoveToItems);
  FreeAndNil(FThemeLayers);
  FreeAndNil(FOperationErrors);
  FOperationRequester:=nil;  { owned by the window frame }
  FTransferProgressDialog:=nil; { owned by the window frame }
  FRightFilter := nil; FLeftFilter := nil; FPlacesFilter := nil; FRightColumns := nil; FLeftColumns := nil;
  FRightTitle := nil; FLeftTitle := nil; FRightPreviewTitle:=nil; FLeftPreviewTitle:=nil; FNavigationTitleBar:=nil; FRightColumn := nil;
  FRightBrowserColumn := nil; FRightPreviewSplit := nil; FLeftColumn := nil;
  FDualViewSplit := nil; FPlacesSplit := nil; FViewsHost := nil; FPlacesPanel := nil; FAssignments := nil; FForm := nil; FFonts := nil;
  FreeAndNil(FLightTheme);
  FreeAndNil(FDarkTheme);
  FTheme := nil;
  FreeAndNil(FStateDocuments);
  FreeAndNil(FFiles); FreeAndNil(FPaths); FPlatform := nil;
  inherited DoDispose;
end;

procedure TAFileManagerController.LogMessage(const AText: string);
begin
  if not FLoggingEnabled then Exit;
  Diagnostic('FILEMANAGER '+AText);
  ArosaTrace('FILEMANAGER',AText);
end;

procedure TAFileManagerController.SetStatus(const AText: string);
begin
  if FStatus <> nil then begin FStatus.Text := AText; FStatus.InvalidatePaint; end;
  Diagnostic('STATUS: '+AText);
  LogMessage(AText);
end;

function TAFileManagerController.NewButton(AParent: TArosaView;
  const ACaption, AHint: string; AHandler: TArosaClickEvent;
  AWidth: Integer): TArosaButton;
begin
  Result := TArosaButton.CreateControl(FTheme, FFonts);
  Result.Caption := ACaption; Result.Hint := AHint; Result.OnClick := AHandler;
  Result.FontFamily := FCompactFont.Description.Family; Result.FontSize := FCompactFont.Description.SizePoints;
  Result.SetConstraintWidth(asmFixed, ArosaCoord(AWidth));
  Result.SetConstraintHeight(asmFixed, ArosaCoord(28));
  AParent.AddVisual(Result);
end;


procedure TAFileManagerController.NewMenuSeparator(AParent: TArosaView; AWidth: Integer);
var Sep: TArosaMenuSeparator;
begin
  { Never lead with a divider, never stack two. }
  if (AParent=nil) or (AParent.ChildVisualCount=0) then Exit;
  if AParent.ChildVisuals[AParent.ChildVisualCount-1] is TArosaMenuSeparator then Exit;
  Sep:=TArosaMenuSeparator.CreateControl(FTheme,FFonts);
  Sep.SetConstraintWidth(asmFixed,ArosaCoord(AWidth));
  Sep.SetConstraintHeight(asmFixed,ArosaCoord(7));
  AParent.AddVisual(Sep);
end;

function TAFileManagerController.NewMenuItem(AParent: TArosaView;
  const ACaption, AHint: string; AHandler: TArosaClickEvent;
  AWidth: Integer; const ACommand: string): TArosaMenuItem;
var Img: TArosaPlatformHandle; Src: TArosaRect;
begin
  Result := TArosaMenuItem.CreateControl(FTheme, FFonts);
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.FontFamily := FCompactFont.Description.Family;
  Result.FontSize := FCompactFont.Description.SizePoints;
  Result.SetConstraintWidth(asmFixed,ArosaCoord(AWidth));
  Result.SetConstraintHeight(asmFixed,ArosaCoord(16));
  { 0.7.5.3: [MenuIcons] Command=theme:name.  The icon column is kept for
    every item while the descriptor maps any menu icon, so captions align. }
  if IconSpecFor('MenuIcons','Theme')<>'' then
  begin
    Result.ReserveIconColumn:=True;
    Result.SetConstraintWidth(asmFixed,ArosaCoord(AWidth+20));
    if LoadThemeIcon(IconSpecFor('MenuIcons',ACommand),Img,Src) then
    begin
      Result.Image:=Img;
      Result.ImageSourceRect:=Src;
    end;
  end;
  AParent.AddVisual(Result);
end;

function TAFileManagerController.NewPage(ATabs: TArosaTabControl;
  const ACaption: string): TArosaTabPage;
begin
  Result := TFileManagerTabPage.CreateStyled(FTheme, ACaption);
  ATabs.AddTabPage(Result);
end;

procedure TAFileManagerController.LoadHistory;
var L: TStringList; I: Integer; S, Text: string;
begin
  if (FRecentLocations=nil) or (FRecentFiles=nil) then Exit;
  L:=TStringList.Create;
  try
    if not StateRead('history',FHistoryPath,False,Text) then Exit;
    L.Text:=Text;
    for I:=0 to L.Count-1 do
    begin
      S:=L[I];
      if Copy(S,1,2)='L=' then FRecentLocations.Add(Copy(S,3,MaxInt))
      else if Copy(S,1,2)='F=' then FRecentFiles.Add(Copy(S,3,MaxInt));
    end;
  finally L.Free; end;
end;

procedure TAFileManagerController.SaveHistory;
var L: TStringList; I: Integer;
begin
  if (FRecentLocations=nil) or (FRecentFiles=nil) then Exit;
  L:=TStringList.Create;
  try
    for I:=0 to FRecentLocations.Count-1 do L.Add('L='+FRecentLocations[I]);
    for I:=0 to FRecentFiles.Count-1 do L.Add('F='+FRecentFiles[I]);
    StateWrite('history',FHistoryPath,False,L.Text);
  finally L.Free; end;
end;

function TAFileManagerController.StateRead(const ADocument, AFile: string;
  AGlobal: Boolean; out AText: string): Boolean;
begin
  AText:='';
  Result:=False;
  if FFiles=nil then Exit;
  if FStateDocuments=nil then
    FStateDocuments:=TArosaStateDocuments.CreateFor('arosa.application.afilemanager',
      FActiveWorkspaceId,@FFiles.ReadAllText,@FFiles.WriteAllText);
  if AGlobal then FStateDocuments.Workspace:='all'
  else FStateDocuments.Workspace:=FActiveWorkspaceId;
  Result:=FStateDocuments.Read(ADocument,AFile,AText);
  Diagnostic('STATE read document='+ADocument+' workspace='+FStateDocuments.Workspace+
    ' source='+FStateDocuments.LastSource);
end;

function TAFileManagerController.StateWrite(const ADocument, AFile: string;
  AGlobal: Boolean; const AText: string): Boolean;
begin
  Result:=False;
  if FFiles=nil then Exit;
  if FStateDocuments=nil then
    FStateDocuments:=TArosaStateDocuments.CreateFor('arosa.application.afilemanager',
      FActiveWorkspaceId,@FFiles.ReadAllText,@FFiles.WriteAllText);
  if AGlobal then FStateDocuments.Workspace:='all'
  else FStateDocuments.Workspace:=FActiveWorkspaceId;
  Result:=FStateDocuments.Write(ADocument,AFile,AText);
end;

procedure TAFileManagerController.AddRecent(AList: TStringList; const APath: string);
var I: Integer;
begin
  if (AList=nil) or (Trim(APath)='') then Exit;
  I:=AList.IndexOf(APath);
  if I>=0 then AList.Delete(I);
  AList.Insert(0,APath);
  while AList.Count>100 do AList.Delete(AList.Count-1);
  SaveHistory;
  if FVirtualLocations<>nil then RebuildVirtualLocations;
end;

procedure TAFileManagerController.LoadLayout;
var L: TStringList; V: Integer; Text: string;
begin
  if (FPlacesSplit=nil) or (FDescriptor=nil) or
     (not FDescriptor.BoolValue('Layout','PersistentPanelWidths',False)) then Exit;
  L:=TStringList.Create;
  try
    if not StateRead('layout',FLayoutPath,False,Text) then Exit;
    L.Text:=Text;
    V:=StrToIntDef(L.Values['PlacesWidth'],0);
    if V>0 then FPlacesSplit.SetDividerPosition(ArosaCoord(V));
    if FPlacesDetailSplit<>nil then begin
      V:=StrToIntDef(L.Values['PlacesDetailPercent'],FPlacesDetailPercent);
      if (V>=10) and (V<=90) then begin FPlacesDetailPercent:=V; FPlacesDetailSplit.SetPercent(V); end;
      if L.Values['PlacesDetailVisible']<>'' then
        FPlacesDetailVisible:=SameText(L.Values['PlacesDetailVisible'],'true') or (L.Values['PlacesDetailVisible']='1');
      if FPlacesDetailTabs<>nil then FPlacesDetailTabs.Visible:=FPlacesDetailVisible;
    end;
  finally L.Free; end;
end;

procedure TAFileManagerController.SaveLayout;
var L: TStringList;
begin
  if (FPlacesSplit=nil) or (FDescriptor=nil) or
     (not FDescriptor.BoolValue('Layout','PersistentPanelWidths',False)) then Exit;
  L:=TStringList.Create;
  try
    L.Values['PlacesWidth']:=IntToStr(ArosaCoordWhole(FPlacesSplit.DividerPosition));
    L.Values['PlacesDetailPercent']:=IntToStr(FPlacesDetailPercent);
    L.Values['PlacesDetailVisible']:=BoolToStr(FPlacesDetailVisible,True);
    StateWrite('layout',FLayoutPath,False,L.Text);
  finally L.Free; end;
end;

procedure TAFileManagerController.BackClick(ASender: TArosaControl);
var P: string; H: TArosaHistoryChain;
begin
  FCommandHistory.Remember('Navigation.Back');
  if FActiveView=0 then H:=FLeftNavigationHistory else H:=FRightNavigationHistory;
  if (H=nil) or not H.TryMoveBack(P) then begin SetStatus('No previous location'); Exit; end;
  FRestoringHistory:=True;
  try NavigateView(FActiveView,P); finally FRestoringHistory:=False; end;
end;

procedure TAFileManagerController.ForwardClick(ASender: TArosaControl);
var P: string; H: TArosaHistoryChain;
begin
  FCommandHistory.Remember('Navigation.Forward');
  if FActiveView=0 then H:=FLeftNavigationHistory else H:=FRightNavigationHistory;
  if (H=nil) or not H.TryMoveForward(P) then begin SetStatus('No next location'); Exit; end;
  FRestoringHistory:=True;
  try NavigateView(FActiveView,P); finally FRestoringHistory:=False; end;
end;

procedure TAFileManagerController.HomeClick(ASender: TArosaControl);
var P: string;
begin
  FCommandHistory.Remember('Navigation.Home');
  P:=Trim(FDescriptor.Value('Navigation','Home','SYS:'));
  if P='' then P:='SYS:';
  NavigateView(FActiveView,P);
end;

function TAFileManagerController.LocationMaxEntries(const AGroup: string): Integer;
begin
  Result:=FDescriptor.IntValue('Locations.'+AGroup,'MaxEntries',0);
  if Result<0 then Result:=0;
end;

procedure TAFileManagerController.PopulateAssignments;
const
  { Only advertise standard DOS assigns that an AROS installation is expected
    to provide.  The previous static list also exposed development-specific
    Arosa:, ArosaBuild:, ArosaSrc: and ArosaTests: names.  Selecting one when
    it was not actually assigned made dos.library display an Insert Volume
    requester.  Custom/development locations belong in Favorites until the
    platform assignment-catalogue service can enumerate live assigns. }
  AssignNames: array[0..12] of string = ('AROS:', 'C:', 'DEVS:', 'ENV:',
    'ENVARC:', 'FONTS:', 'L:', 'LIBS:', 'PROGDIR:', 'RAM:', 'S:', 'SYS:', 'T:');
var
  I, J, MaxEntries, Added: Integer;
  Root, GroupNode, N, WorkspaceRoot: TArosaTreeNode;
  Groups, Entries, SectionValues: TStringList;
  GroupName, ProviderName, Path, Caption, WorkspaceName: string;
  IconPath, IconError, SemanticIcon: string;
  IconResource: TArosaImageResource;

  procedure AddLocation(AParent: TArosaTreeNode; const ACaption, APath: string);
  var X: TArosaTreeNode;
  begin
    if Trim(APath)='' then Exit;
    if (MaxEntries>0) and (Added>=MaxEntries) then Exit;
    X:=AParent.AddChild(ACaption);
    X.Hint:=APath;
    if IsRemoteLocation(APath) then X.TextRole:=RemoteTextRole;
    Inc(Added);
  end;


  procedure ApplyGroupIcon(ANode: TArosaTreeNode; const AGroup: string);
  begin
    if (ANode=nil) or (FImageLoader=nil) then Exit;
    SemanticIcon:=Trim(FDescriptor.Value('PlacesIcons',AGroup,
      FDescriptor.Value('PlacesIcons','Default','theme:location-group')));
    if SemanticIcon='' then Exit;
    IconPath:=SemanticIcon;
    if Pos('theme:',LowerCase(IconPath))=1 then
    begin
      IconPath:=Copy(IconPath,7,MaxInt);
      { Theme semantic icon convention.  The theme service can later resolve
        the same canonical symbol directly; today the image service probes the
        theme's icons directory without teaching AFileManager a file format. }
      IconPath:=ThemeIconPath(IconPath);
    end;
    IconResource:=nil;
    IconError:='';
    if FImageLoader.TryLoadFile(IconPath,IconResource,IconError) then
    begin
      ANode.Image:=IconResource.Bitmap;
      ANode.ImageSourceRect:=ArosaRectXYWH(0,0,IconResource.Width,IconResource.Height);
      FPlaceIconResources.Add(IconResource);
    end
    else
      ArosaTrace('PLACES-ICON','unavailable group='+AGroup+' icon='+SemanticIcon+
        ' resolved='+IconPath+' error='+IconError);
  end;

begin
  if FAssignments=nil then Exit;
  Root:=FAssignments.RootNode;
  Root.ClearChildren;
  if FPlaceIconResources<>nil then
    while FPlaceIconResources.Count>0 do
    begin
      TArosaImageResource(FPlaceIconResources[FPlaceIconResources.Count-1]).Free;
      FPlaceIconResources.Delete(FPlaceIconResources.Count-1);
    end;
  Groups:=TStringList.Create;
  Entries:=TStringList.Create;
  try
    WorkspaceName:=FActiveWorkspaceId;
    if (FWorkspaces<>nil) and (FWorkspaces.Find(FActiveWorkspaceId)<>nil) then
      WorkspaceName:=FWorkspaces.Find(FActiveWorkspaceId).Name;
    WorkspaceRoot:=Root.AddChild(
      LocalText('afilemanager_workspaces_current','WorkSpaces')+
      ' ('+WorkspaceName+')');
    WorkspaceRoot.Hint:='arosa://workspaces';
    WorkspaceRoot.Expanded:=True;
    ApplyGroupIcon(WorkspaceRoot,'Workspaces');
    if FWorkspaces<>nil then
      for I:=0 to FWorkspaces.Count-1 do
        if (FWorkspaces.Workspace(I)<>nil) and
           (not SameText(FWorkspaces.Workspace(I).Id,FActiveWorkspaceId)) then
        begin
          N:=WorkspaceRoot.AddChild(FWorkspaces.Workspace(I).Name);
          N.Hint:='arosa://workspace/'+FWorkspaces.Workspace(I).Id;
          ApplyGroupIcon(N,'Workspaces');
        end;

    ExtractStrings([','],[' '],PChar(FDescriptor.Value('Locations','Groups','Desktop,Favorites,RecentLocations,RecentFiles,Assigns,Network,Devices')),Groups);
    for I:=0 to Groups.Count-1 do
    begin
      GroupName:=Trim(Groups[I]);
      if GroupName='' then Continue;
      MaxEntries:=LocationMaxEntries(GroupName); { omitted = 0 = unlimited }
      ProviderName:=FDescriptor.Value('Locations.'+GroupName,'Provider',GroupName);
      Added:=0;
      GroupNode:=Root.AddChild(GroupName);
      ApplyGroupIcon(GroupNode,GroupName);
      GroupNode.Expanded:=(CompareText(GroupName,'Desktop')=0) or
        (CompareText(GroupName,'Favorites')=0) or
        (CompareText(GroupName,'Assigns')=0);

      if (CompareText(ProviderName,'Desktop')=0) or (CompareText(ProviderName,'System.UserLocations')=0) then
      begin
        AddLocation(GroupNode,'User Desktop',FDescriptor.Value('Locations.Desktop','Desktop',FDescriptor.Value('Locations','UserDesktop','')));
        AddLocation(GroupNode,'Documents',FDescriptor.Value('Locations.Desktop','Documents',FDescriptor.Value('Locations','UserDocuments','')));
        AddLocation(GroupNode,'Downloads',FDescriptor.Value('Locations.Desktop','Downloads',FDescriptor.Value('Locations','UserDownloads','SYS:Work/Downloads')));
      end
      else if (CompareText(ProviderName,'Favorites')=0) or (CompareText(ProviderName,'AFileManager.Favorites')=0) then
      begin
        { The user's favourites list (seeded from the descriptor once). }
        for J:=0 to FFavorites.Count-1 do
          AddLocation(GroupNode,FFavorites.Names[J],FFavorites.ValueFromIndex[J]);
      end
      else if (CompareText(ProviderName,'RecentLocations')=0) or (CompareText(ProviderName,'AFileManager.RecentLocations')=0) then
        for J:=0 to FRecentLocations.Count-1 do
          AddLocation(GroupNode,FRecentLocations[J],FRecentLocations[J])
      else if (CompareText(ProviderName,'RecentFiles')=0) or (CompareText(ProviderName,'AFileManager.RecentFiles')=0) then
        for J:=0 to FRecentFiles.Count-1 do
          AddLocation(GroupNode,FRecentFiles[J],FRecentFiles[J])
      else if (CompareText(ProviderName,'Assigns')=0) or (CompareText(ProviderName,'System.Assignments')=0) then
        for J:=Low(AssignNames) to High(AssignNames) do
          AddLocation(GroupNode,AssignNames[J],AssignNames[J])
      else if (CompareText(ProviderName,'Network')=0) or (CompareText(ProviderName,'System.NetworkLocations')=0) then
      begin
        { Network Places are logical Location-Service addresses.  The caption
          is only a label; never manufacture an AmigaDOS volume such as HOST:. }
        for J:=0 to FNetworkLocations.Count-1 do
        begin
          Caption:=Trim(FNetworkLocations.Names[J]);
          Path:=Trim(FNetworkLocations.ValueFromIndex[J]);
          { Stored key is stable-id|label.  Only the label is presentation. }
          if Pos('|',Caption)>0 then Caption:=Copy(Caption,Pos('|',Caption)+1,MaxInt);
          if (Caption<>'') and (Path<>'') then AddLocation(GroupNode,Caption,Path);
        end;
      end
      else if (CompareText(ProviderName,'Devices')=0) or (CompareText(ProviderName,'System.Devices')=0) then
      begin
        AddLocation(GroupNode,'RAM:','RAM:');
        AddLocation(GroupNode,'SYS:','SYS:');
      end;

      if (Added=0) and not FDescriptor.BoolValue('Locations.'+GroupName,'ShowEmpty',False) then
      begin
        { Keep the declared group visible for now; a future tree API can remove
          empty nodes without rebuilding the whole tree. }
      end;
    end;
  finally
    Entries.Free;
    Groups.Free;
  end;
  FAssignments.Rebuild;
  if FVirtualLocations<>nil then RebuildVirtualLocations;
end;

function TAFileManagerController.ViewList(AView: Integer): TArosaFilteredListView;
begin if AView = 0 then Result := FLeftList else Result := FRightList; end;
function TAFileManagerController.ViewPathBox(AView: Integer): TArosaTextBox;
begin if AView = 0 then Result := FLeftPath else Result := FRightPath; end;
function TAFileManagerController.ViewCrumbs(AView: Integer): TArosaBreadcrumbBar;
begin if AView = 0 then Result := FLeftCrumbs else Result := FRightCrumbs; end;

procedure TAFileManagerController.SyncCrumbs(AView: Integer);
var C: TArosaBreadcrumbBar;
begin
  C := ViewCrumbs(AView);
  if C <> nil then C.Path := ViewCurrent(AView);
end;

procedure TAFileManagerController.SetPathEditing(AView: Integer; AEditing: Boolean);
var C: TArosaBreadcrumbBar; B: TArosaTextBox;
begin
  C := ViewCrumbs(AView);
  B := ViewPathBox(AView);
  if (C = nil) or (B = nil) then Exit;
  if (B.Visible = AEditing) and (C.Visible = not AEditing) then Exit;
  C.Visible := not AEditing;
  B.Visible := AEditing;
  if not AEditing then SyncCrumbs(AView);
  if C.ParentVisual <> nil then C.ParentVisual.InvalidateLayout;
  C.InvalidatePaint;
  B.InvalidatePaint;
end;

procedure TAFileManagerController.LeftCrumbNavigate(
  ASender: TArosaControl; const APath: string);
begin
  { Breadcrumb navigation runs from TArosaBreadcrumbBar.HandleInput(MouseUp).
    NavigateView rebuilds both the breadcrumb segments and the retained list.
    Doing that while the breadcrumb is still inside its own input callback can
    invalidate the control currently dispatching the event.  Queue it exactly
    like list activation and execute it from PreviewIdle after the callback
    has returned to the application loop. }
  FPendingNavigateActive:=True;
  FPendingNavigateView:=0;
  FPendingNavigatePath:=APath;
  if ArosaTraceEnabled then
    ArosaTrace('FILEMANAGER','CRUMB-NAV-QUEUED view=0 path='+APath);
end;

procedure TAFileManagerController.RightCrumbNavigate(
  ASender: TArosaControl; const APath: string);
begin
  FPendingNavigateActive:=True;
  FPendingNavigateView:=1;
  FPendingNavigatePath:=APath;
  if ArosaTraceEnabled then
    ArosaTrace('FILEMANAGER','CRUMB-NAV-QUEUED view=1 path='+APath);
end;
procedure TAFileManagerController.LeftCrumbEdit(ASender: TArosaControl; const APath: string);
begin
  SetActiveView(0);
  FLeftPath.Text := ViewCurrent(0);
  SetPathEditing(0, True);
  SetStatus(LocalText('afilemanager_status_type_path','Type a location and press Enter.'));
end;
procedure TAFileManagerController.RightCrumbEdit(ASender: TArosaControl; const APath: string);
begin
  SetActiveView(1);
  FRightPath.Text := ViewCurrent(1);
  SetPathEditing(1, True);
  SetStatus(LocalText('afilemanager_status_type_path','Type a location and press Enter.'));
end;

function TAFileManagerController.ViewCurrent(AView: Integer): string;
begin if AView = 0 then Result := FLeftCurrent else Result := FRightCurrent; end;
procedure TAFileManagerController.SetViewCurrent(AView: Integer; const AValue: string);
begin if AView = 0 then FLeftCurrent := AValue else FRightCurrent := AValue; end;

procedure TAFileManagerController.SetActiveView(AView: Integer);
begin
  FPlacesActive := False;
  if (AView<>0) and (FRightList=nil) then AView:=0;
  FActiveView := AView;
  if FLeftTitle<>nil then
  begin
    if AView=0 then FLeftTitle.TextRole:=AROSA_ROLE_ACCENT
    else FLeftTitle.TextRole:=AROSA_ROLE_PRIMARY_TEXT;
    FLeftTitle.InvalidatePaint;
  end;
  if FRightTitle<>nil then
  begin
    if AView=1 then FRightTitle.TextRole:=AROSA_ROLE_ACCENT
    else FRightTitle.TextRole:=AROSA_ROLE_PRIMARY_TEXT;
    FRightTitle.InvalidatePaint;
  end;
  { 0.5.110.14.1: the active pane's LOCATION is drawn in a highlight role
    ([Panes] ActivePathRole, default Error = red) so the selected side is
    obvious at a glance; the inactive side uses normal text. }
  if FLeftPath<>nil then
  begin
    if (AView=0) and (FRightList<>nil) then FLeftPath.TextRole:=ActivePathRole
    else FLeftPath.TextRole:='';
    FLeftPath.InvalidatePaint;
    if FLeftCrumbs<>nil then
    begin
      FLeftCrumbs.TextRole:=FLeftPath.TextRole;
      FLeftCrumbs.InvalidatePaint;
    end;
  end;
  if FRightPath<>nil then
  begin
    if AView=1 then FRightPath.TextRole:=ActivePathRole
    else FRightPath.TextRole:='';
    FRightPath.InvalidatePaint;
    if FRightCrumbs<>nil then
    begin
      FRightCrumbs.TextRole:=FRightPath.TextRole;
      FRightCrumbs.InvalidatePaint;
    end;
  end;
  UpdatePreviewPercentLabel;
  UpdatePaneInfo(0);
  if FRightList<>nil then UpdatePaneInfo(1);
  UpdateViewToolbarState;
end;

function TAFileManagerController.ParentPath(const APath: string): string;
begin
  if FLocations<>nil then Result:=FLocations.Parent(APath)
  else Result:=APath;
end;

procedure TAFileManagerController.NavigateView(AView: Integer;
  const APath: string);
var N: string;
begin
  LogMessage('NAV-BEGIN view='+IntToStr(AView)+' path='+APath);
  {$IFNDEF AROS}Flush(Output);{$ENDIF}
  try
    if FLocations=nil then begin SetStatus('Location service unavailable'); Exit; end;
    N := FLocations.Normalize(APath);
    { Local paths can be preflighted cheaply. A provider URI must be allowed
      to reach Enumerate directly: LIST is the authoritative directory operation
      and must not be blocked by an optional/unsupported STAT preflight. }
    if Pos('://',N)=0 then
    begin
      if not FLocations.Exists(N) then begin SetStatus('Unavailable or not mounted: ' + N); Exit; end;
      if not FLocations.IsDirectory(N) then begin SetStatus('Not a directory: ' + N); Exit; end;
    end;
    { Re-selecting the location already displayed must not enumerate the host
      filesystem again.  Besides being unnecessary I/O, this matters on AROS
      network/host handlers where duplicate requests can expose handler faults. }
    if SameText(FLocations.Normalize(ViewCurrent(AView)),N) then
    begin
      SetActiveView(AView);
      ViewPathBox(AView).Text:=N;
      if FPendingInputKind='' then SetPathEditing(AView,False);
      SetStatus('Location already open: '+N);
      LogMessage('NAV-SAME view='+IntToStr(AView)+' path='+N);
      Exit;
    end;

    { Do not call SetActiveView while the list is being replaced.  A double-click
      is dispatched by the old list row; changing active presentation during
      that callback caused nested title/status invalidation while Clear/NewRow
      was mutating the same retained subtree. }
    FActiveView := AView;
    SetViewCurrent(AView, N);
    ViewPathBox(AView).Text := N;
    SyncCrumbs(AView);
    if FPendingInputKind='' then SetPathEditing(AView, False);
    if not FRestoringHistory then
      if AView=0 then FLeftNavigationHistory.RecordEntry(N)
      else FRightNavigationHistory.RecordEntry(N);
    if AView=1 then RebuildSurfaceBar;
    RefreshView(AView);

    SetActiveView(AView);
    SetStatus('Opened location: ' + N);
    AddRecent(FRecentLocations,N);
    LogMessage('NAV-END view='+IntToStr(AView)+' path='+N);
    {$IFNDEF AROS}Flush(Output);{$ENDIF}
  except
    on E: Exception do begin
      ArosaTrace('FILEMANAGER','NAV-FAIL view='+IntToStr(AView)+' path='+APath+
        ' class='+E.ClassName+' message='+E.Message);
      {$IFNDEF AROS}Flush(Output);{$ENDIF}
      SetStatus('Cannot open ' + APath + ': ' + E.Message);
    end;
  end;
end;

procedure TAFileManagerController.SortEntries(var AEntries: TArosaFileInfoArray);
var
  I, J: Integer;
  T: TArosaFileInfo;

  function ComesBefore(const A, B: TArosaFileInfo): Boolean;
  begin
    if A.Kind<>B.Kind then
      Exit(A.Kind=afekDirectory);
    Result := CompareText(A.Name,B.Name)<0;
  end;

begin
  { Stable-enough insertion sort for directory-sized collections.  It keeps
    directories before files and sorts each group alphabetically. }
  for I := 1 to High(AEntries) do
  begin
    T := AEntries[I];
    J := I-1;
    while (J>=0) and ComesBefore(T,AEntries[J]) do
    begin
      AEntries[J+1] := AEntries[J];
      Dec(J);
    end;
    AEntries[J+1] := T;
  end;
end;

procedure TAFileManagerController.PresentEnumerationEntries(AView: Integer;
  const APath: string; var AEntries: TArosaFileInfoArray; ASyncOther: Boolean);
var
  I, IconX, IconY, OtherView: Integer;
  R: TArosaListRow;
  Text: string;
  List: TArosaFilteredListView;
begin
  List:=ViewList(AView);
  if (List=nil) or List.IsDisposed then Exit;
  SortEntries(AEntries);
  for I := 0 to High(AEntries) do
  begin
    if (not FShowHiddenFiles) and IsHiddenResource(AEntries[I]) then Continue;
    Text := DetailsRow(AEntries[I]);
    R := List.NewRow(Text);
    R.Tags := AEntries[I].FullPath;
    R.SearchText := AEntries[I].Name;
    if AEntries[I].Kind=afekDirectory then R.UserFlags:=AFM_ROW_FOLDER
    else R.UserFlags:=AFM_ROW_FILE;
    if (((AView=0) and (FLeftViewMode=3)) or
        ((AView=1) and (FRightViewMode=3))) and
       (Pos('://',AEntries[I].FullPath)=0) then
    begin
      R.HasSpatialPosition:=ArosaTryGetWorkbenchIconPosition(
        AEntries[I].FullPath,IconX,IconY);
      if R.HasSpatialPosition then
      begin
        R.SpatialX:=IconX;
        R.SpatialY:=IconY;
      end;
    end
    else
      R.HasSpatialPosition:=False;
    PopulateDetailsRow(R,AEntries[I],AView);
  end;
  UpdatePaneInfo(AView);
  SetStatus(LocalText('afilemanager_active_pane','Active pane')+': '+
    IntToStr(AView+1)+' - '+APath);
  SetLength(AEntries,0);

  if ASyncOther then
  begin
    OtherView:=1-AView;
    FSynchronizingLocationRefresh:=True;
    try
      RefreshView(OtherView);
    finally
      FSynchronizingLocationRefresh:=False;
    end;
  end;
end;

function TAFileManagerController.StartEnumerationWorker(AView: Integer;
  const APath: string; ASyncOther: Boolean): Boolean;
begin
  Result:=False;
  {$IFDEF AROS}
  if (FNativeHost=nil) or (FNativeHost.Application=nil) or
     (FNativeHost.Application.Loop=nil) then Exit;

  if FEnumerationWorkerActive then
  begin
    { Navigation supersedes an older enumeration. The old worker is asked to
      stop; the newest request is started as soon as its completion arrives. }
    FEnumerationPending:=True;
    FEnumerationPendingView:=AView;
    FEnumerationPendingPath:=APath;
    FEnumerationPendingSyncOther:=ASyncOther;
    ArosaFileEnumerationWorkerCancel(FEnumerationWorkerGeneration);
    SetStatus('Cancelling previous directory enumeration...');
    Exit(True);
  end;

  Inc(FEnumerationWorkerGeneration);
  if FEnumerationWorkerGeneration<=0 then FEnumerationWorkerGeneration:=1;
  if not ArosaFileEnumerationWorkerStart(APath,FEnumerationWorkerGeneration,
    FEnumerationWorkerTargetCPU) then Exit(False);
  FEnumerationWorkerActive:=True;
  FEnumerationWorkerView:=AView;
  FEnumerationWorkerPath:=APath;
  FEnumerationWorkerSyncOther:=ASyncOther;
  if not FEnumerationWorkerIdleAttached then
  begin
    FNativeHost.Application.Loop.AddIdleHandler(@EnumerationIdle);
    FEnumerationWorkerIdleAttached:=True;
  end;
  SetStatus('Enumerating '+APath+' on worker CPU '+
    IntToStr(FEnumerationWorkerTargetCPU)+'...');
  Diagnostic('ENUM-WORKER start generation='+IntToStr(FEnumerationWorkerGeneration)+
    ' view='+IntToStr(AView)+' cpu='+IntToStr(FEnumerationWorkerTargetCPU)+
    ' path='+APath);
  Result:=True;
  {$ENDIF}
end;

procedure TAFileManagerController.EnumerationIdle(var AMoreWorkPending: Boolean);
var
  Status: TArosaFileEnumerationWorkerStatus;
  Entries: TArosaFileInfoArray;
  CompletedView, PendingView: Integer;
  CompletedPath, PendingPath: string;
  CompletedSync, PendingSync: Boolean;
  CompletedGeneration: LongInt;
begin
  { Waiting on a native worker is not UI work. Never keep the event loop hot. }
  AMoreWorkPending:=False;
  if not FEnumerationWorkerActive then
  begin
    if FEnumerationWorkerIdleAttached and (FNativeHost<>nil) and
       (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) then
      FNativeHost.Application.Loop.RemoveIdleHandler(@EnumerationIdle);
    FEnumerationWorkerIdleAttached:=False;
    Exit;
  end;
  if not ArosaFileEnumerationWorkerPoll(Status) or not Status.Done then Exit;

  CompletedView:=FEnumerationWorkerView;
  CompletedPath:=FEnumerationWorkerPath;
  CompletedSync:=FEnumerationWorkerSyncOther;
  CompletedGeneration:=FEnumerationWorkerGeneration;
  FEnumerationWorkerActive:=False;
  ArosaFileEnumerationWorkerRelease(CompletedGeneration);

  Diagnostic('ENUM-WORKER complete generation='+IntToStr(CompletedGeneration)+
    ' requested='+IntToStr(Status.RequestedCPU)+' first='+IntToStr(Status.FirstCPU)+
    ' last='+IntToStr(Status.LastCPU)+' pin='+IntToStr(Status.PinRC)+
    ' entries='+IntToStr(Status.Count)+' error='+IntToStr(Status.ErrorCode));
  ArosaCompositionTracePublishTopology('AFileManager','FileServices',
    'enum-'+IntToStr(CompletedGeneration),'Enumeration',aceNodeResultAvailable,
    'I/O',Status.RequestedCPU,Status.LastCPU,0.0,
    'first CPU '+IntToStr(Status.FirstCPU)+' / last CPU '+IntToStr(Status.LastCPU)+
    ' / pin rc '+IntToStr(Status.PinRC)+' / entries '+IntToStr(Status.Count),
    'Application','','worker','enum-'+IntToStr(CompletedGeneration));

  if SameText(ViewCurrent(CompletedView),CompletedPath) then
  begin
    Entries:=nil;
    if (Status.ErrorCode=0) and ArosaFileEnumerationWorkerRead(Status,Entries) then
    begin
      PresentEnumerationEntries(CompletedView,CompletedPath,Entries,CompletedSync);
      SetStatus('Listed '+CompletedPath+' using worker CPU '+IntToStr(Status.LastCPU)+
        ' ('+IntToStr(Status.Count)+' item(s))');
    end
    else if Status.ErrorCode<>0 then
      SetStatus('Unable to list: '+CompletedPath+' (worker error '+
        IntToStr(Status.ErrorCode)+')');
  end;

  if FEnumerationPending then
  begin
    PendingView:=FEnumerationPendingView;
    PendingPath:=FEnumerationPendingPath;
    PendingSync:=FEnumerationPendingSyncOther;
    FEnumerationPending:=False;
    FEnumerationPendingPath:='';
    StartEnumerationWorker(PendingView,PendingPath,PendingSync);
  end
  else if FEnumerationWorkerIdleAttached and (FNativeHost<>nil) and
          (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@EnumerationIdle);
    FEnumerationWorkerIdleAttached:=False;
  end;
end;

procedure TAFileManagerController.RefreshView(AView: Integer);
var
  Entries: TArosaFileInfoArray;
  OtherView: Integer;
  List: TArosaFilteredListView;
  Cur, OtherCur: string;
  SyncOther: Boolean;
begin
  SyncOther:=False;
  OtherView:=1-AView;
  if (not FSynchronizingLocationRefresh) and
     ((OtherView=0) or (FRightList<>nil)) then
  begin
    Cur:=ViewCurrent(AView);
    OtherCur:=ViewCurrent(OtherView);
    if FLocations<>nil then
    begin
      Cur:=FLocations.Normalize(Cur);
      OtherCur:=FLocations.Normalize(OtherCur);
    end;
    SyncOther:=SameText(Cur,OtherCur) and (Trim(Cur)<>'');
  end;
  Entries:=nil;
  List:=ViewList(AView);
  if List=nil then Exit;
  if List.IsDisposed then
  begin
    Diagnostic('VIEW refresh of view '+IntToStr(AView)+' found its list released; forgotten');
    if AView=0 then FLeftList:=nil else FRightList:=nil;
    Exit;
  end;
  Cur:=ViewCurrent(AView);
  List.Clear;
  if not SameText(FThumbnailCacheLocation[AView],Cur) then
  begin
    ClearThumbnailCache(AView);
    FThumbnailCacheLocation[AView]:=Cur;
  end;

  { 0.17.14: local DOS enumeration is the first live AFileManager workload
    moved off the UI task. Provider URIs retain their existing provider path. }
  if Pos('://',Cur)=0 then
    if StartEnumerationWorker(AView,Cur,SyncOther) then Exit;

  try
    if (FLocations=nil) or not FLocations.Enumerate(Cur,Entries) then
    begin
      if (FLocations<>nil) and (Pos('://',Cur)>0) then
      begin
        if (FLocations.ProviderByScheme(Copy(Cur,1,Pos('://',Cur)-1))<>nil) and
           (Trim(FLocations.ProviderByScheme(Copy(Cur,1,Pos('://',Cur)-1)).LastError)<>'') then
          SetStatus('Unable to list: '+Cur+' - '+
            FLocations.ProviderByScheme(Copy(Cur,1,Pos('://',Cur)-1)).LastError)
        else
          SetStatus('Unable to list: '+Cur);
      end
      else
        SetStatus('Unable to list: '+Cur);
      Exit;
    end;
    PresentEnumerationEntries(AView,Cur,Entries,SyncOther);
  except
    on E: Exception do SetStatus('List failed for '+Cur+': '+E.Message);
  end;
end;

procedure TAFileManagerController.RefreshBoth;
begin RefreshView(0); if FRightList<>nil then RefreshView(1); SetActiveView(FActiveView); end;

function TAFileManagerController.SelectedPath(AView, AIndex: Integer): string;
var R: TArosaListRow;
begin
  Result := '';
  if ViewList(AView)=nil then Exit;
  R := ViewList(AView).VisibleRowsView[AIndex];
  if R <> nil then Result := R.Tags;
end;

function TAFileManagerController.RunCommand(const AExecutable,
  AArguments, AWorkingDirectory: string; out AOutput: string): Boolean;
var
  WorkingDirectory: string;
begin
  WorkingDirectory:=AWorkingDirectory;
  { A provider URI is a logical resource location, never an AmigaDOS current
    directory.  Passing a scheme:// location as the cwd of a native command
    makes AROS interpret the scheme (for example "atransfer:") as a DOS
    volume and opens the Insert Volume requester.  External preview helpers
    must run with an empty/local working directory; their actual input path is
    already materialised by Content Service before invocation. }
  if IsProviderLocation(WorkingDirectory) then
    WorkingDirectory:='';
  Diagnostic('PROCESS requested executable='+AExecutable+' cwd='+WorkingDirectory);
  if FShellService=nil then begin
    AOutput:='Shell service unavailable'; Diagnostic('PROCESS failed '+AOutput);
    SetStatus(AOutput); Exit(False);
  end;
  Result:=FShellService.RunCommand(AExecutable,AArguments,WorkingDirectory,AOutput);
  if Result then Diagnostic('PROCESS completed executable='+AExecutable)
  else begin
    Diagnostic('PROCESS failed executable='+AExecutable+' detail='+AOutput);
    SetStatus('Command failed: '+AExecutable+' '+AOutput);
  end;
end;

function TAFileManagerController.OpenWebLink(const AAddress: string): Boolean;
begin
  { The preview itself never goes to the network.  ABrowser is a separate
    program with its own process; AFileManager regains its event loop at
    once.  The address is one argument and only ever an http/https one. }
  Result:=False;
  if (FShellService=nil) or (Trim(AAddress)='') then Exit;
  if (Pos('http://',LowerCase(Trim(AAddress)))<>1) and
     (Pos('https://',LowerCase(Trim(AAddress)))<>1) then Exit;
  if (Pos(#10,AAddress)>0) or (Pos(#13,AAddress)>0) or (Pos('"',AAddress)>0) then Exit;
  Result:=FShellService.LaunchIndependentArgs('AROSAApps:ABrowser/ABrowser',
    WorkspaceLaunchArguments+#10+Trim(AAddress));
end;

function TAFileManagerController.OpenAssociatedResource(
  const APath: string): Boolean;
var
  Physical, Err: string;
  C: TArosaContentDescriptor;
begin
  Result:=False;
  Physical:=APath;
  { 0.8.6.4: an AROSA invocation target is not a resource of any file system }
  if ArosaIsInvocationTarget(APath) then Exit;

  { Never hand a provider URI to the native shell/association launcher.
    AROS interprets "scheme:" as a DOS device/volume name, so launching
    atransfer://... directly causes the system "Insert volume atransfer"
    requester. Provider resources must first be materialized by the Content
    Service, then the association opens the local physical copy. }
  if IsProviderLocation(APath) then
  begin
    if FContent=nil then
    begin
      SetStatus(LocalText('afilemanager_remote_open_unavailable',
        'Remote content service is unavailable'));
      Exit;
    end;

    if not FContent.AcquireOriginal(APath,C,Err) then
    begin
      if Err='' then Err:=LocalText('afilemanager_remote_open_failed',
        'Remote resource could not be retrieved');
      SetStatus(Err);
      Diagnostic('ASSOCIATION materialize failed location='+APath+
        ' error='+Err);
      Exit;
    end;

    Physical:=C.PhysicalPath;
    Diagnostic('ASSOCIATION materialized location='+APath+
      ' physical='+Physical);
  end;

  if (FShellService<>nil) and FShellService.Associations.Open(Physical) then
  begin
    if IsProviderLocation(APath) then AddRecent(FRecentFiles,APath)
    else AddRecent(FRecentFiles,Physical);
    SetStatus('Opened: '+APath);
    Result:=True;
  end
  else
  begin
    Diagnostic('ASSOCIATION no action location='+APath+
      ' physical='+Physical);
    SetStatus('No associated action for: '+APath);
  end;
end;

procedure TAFileManagerController.AssignmentActivated(ASender: TArosaControl; AIndex: Integer);
var N: TArosaTreeNode;
begin
  FPlacesActive := True;
  UpdatePreviewPercentLabel;
  N := FAssignments.SelectedNode;
  if (N<>nil) and (Trim(N.Hint)<>'') then
  begin
    ShowPlaceProperties(N.Hint);
    if ActivateWorkspaceLocation(N.Hint) then Exit;
    { A configured non-local Place is itself a navigable location. Do not
      require STAT/IsDirectory before LIST: providers may support directory
      enumeration independently, and the preflight prevented ATransfer LIST
      from ever being attempted. }
    if Pos('://',N.Hint)>0 then
      NavigateView(FActiveView,N.Hint)
    else if (FLocations<>nil) and FLocations.IsDirectory(N.Hint) then
      NavigateView(FActiveView,N.Hint)
    else if (FLocations<>nil) and FLocations.Exists(N.Hint) then
    begin
      if ActivateWorkspaceSelfResource(N.Hint) then
      begin
        SetStatus(LocalText('afilemanager_workspace_session_active',
          'AFileManager is already open in this workspace'));
        Exit;
      end;
      OpenAssociatedResource(N.Hint);
    end
    else
      begin
        if (FLocations<>nil) and (Pos('atransfer://',LowerCase(N.Hint))=1) and
           (FLocations.ProviderByScheme('atransfer')<>nil) and
           (FLocations.ProviderByScheme('atransfer').LastError<>'') then
          SetStatus('Unavailable: '+N.Hint+' - '+FLocations.ProviderByScheme('atransfer').LastError)
        else SetStatus('Unavailable: '+N.Hint);
      end;
  end;
  if AIndex<0 then ;
end;
procedure TAFileManagerController.LeftSelected(ASender: TArosaControl; AIndex: Integer);
begin SetActiveView(0); UpdatePaneInfo(0); QueuePreview(0); end;
procedure TAFileManagerController.RightSelected(ASender: TArosaControl; AIndex: Integer);
begin SetActiveView(1); UpdatePaneInfo(1); QueuePreview(1); end;
procedure TAFileManagerController.LeftActivated(ASender: TArosaControl; AIndex: Integer);
begin ActivateItem(0, AIndex); end;
procedure TAFileManagerController.RightActivated(ASender: TArosaControl; AIndex: Integer);
begin ActivateItem(1, AIndex); end;

procedure TAFileManagerController.ActivateItem(AView, AIndex: Integer);
var P: string;
begin
  { Capture the selected path before any active-view presentation changes.
    The row already carries the authoritative kind returned by Enumerate.
    Do not issue a second provider STAT merely to decide whether activation
    means navigation.  More importantly, never Clear/NewRow the same list
    while its OnActivate callback is still on the input stack: on AROS that
    can leave the retained list/event path wedged with no exception. }
  P := SelectedPath(AView, AIndex);
  if P = '' then Exit;
  FActiveView := AView;

  if Pos('exec:',LowerCase(P))=1 then
  begin
    { Queue application launch to idle and collapse duplicate activation
      delivery from the same native mouse gesture. }
    P:=Copy(P,6,MaxInt);
    if FPendingExecLaunch and SameText(FPendingExecTarget,P) then Exit;
    if SameText(FLastExecLaunchTarget,P) and
       (GetTickCount64-FLastExecLaunchTick<1500) then Exit;
    FPendingExecTarget:=P;
    FPendingExecWorkspace:=FActiveWorkspaceId;
    FPendingExecLaunch:=True;
    SetStatus(LocalText('afilemanager_opening','Opening')+': '+P);
    Exit;
  end;

  { 0.8.6.4: a module that is part of AROSA itself is neither a program nor a
    file.  It must not reach the associations, which would hand "internal:"
    to AmigaDOS as the name of a volume. }
  if Pos('internal:',LowerCase(Trim(P)))=1 then
  begin
    SetStatus(LocalText('afilemanager_module_unavailable',
      'This module is not available yet')+': '+Copy(Trim(P),10,MaxInt));
    Exit;
  end;

  if ActivateWorkspaceLocation(P) then Exit;

  if SelectedRowIsDirectory(AView,AIndex) then
  begin
    FPendingNavigateView:=AView;
    FPendingNavigatePath:=P;
    FPendingNavigateActive:=True;
    if ArosaTraceEnabled then
      ArosaTrace('FILEMANAGER','NAV-QUEUED view='+IntToStr(AView)+
        ' path='+P);
    Exit;
  end;

  SetActiveView(AView);
  if ActivateWorkspaceSelfResource(P) then Exit;

  { A resource already owned by the pane presentation is already "open" for
    AFileManager purposes.  In particular, double-clicking an HTML row must not
    repeatedly fall through to the shell association layer while the HTML
    presentation is active.  The 2026-10-09 trace showed the same index.html
    being dispatched to Associations.Open more than a dozen times while the
    user was trying to recover the UI. }
  if SameText(FDisplayedPreviewPath[AView],P) and
     (((AView=0) and (FLeftPresentation<>nil)) or
      ((AView=1) and (FRightPresentation<>nil))) then
  begin
    SetStatus(LocalText('afilemanager_previewing','Previewing')+': '+P);
    Exit;
  end;

  OpenAssociatedResource(P);
end;

procedure TAFileManagerController.LeftPathEnter(ASender: TArosaControl);
begin
  if FPendingInputKind<>'' then
    CommitNameInput(0)
  else
  begin
    NavigateView(0,FLeftPath.Text);
    { Enter commits the location editor. Breadcrumbs are the normal steady
      state even when navigation reports an unavailable/invalid target. }
    FLeftPath.Text:=ViewCurrent(0);
    SetPathEditing(0,False);
  end;
end;

procedure TAFileManagerController.RightPathEnter(ASender: TArosaControl);
begin
  if FPendingInputKind<>'' then
    CommitNameInput(1)
  else
  begin
    NavigateView(1,FRightPath.Text);
    FRightPath.Text:=ViewCurrent(1);
    SetPathEditing(1,False);
  end;
end;
procedure TAFileManagerController.UpClick(ASender: TArosaControl);
begin
  FCommandHistory.Remember('Navigation.Up'); NavigateView(FActiveView, ParentPath(ViewCurrent(FActiveView))); end;
procedure TAFileManagerController.RefreshClick(ASender: TArosaControl);
begin
  { 0.6.1.2: refresh the pane's CURRENT location.  Navigating to the path
    box text would jump to whatever was being typed in edit mode. }
  FCommandHistory.Remember('Navigation.Refresh');
  if FLocations<>nil then FLocations.Invalidate(ViewCurrent(FActiveView));
  if (FContent<>nil) and IsProviderLocation(ViewCurrent(FActiveView)) then
    FContent.InvalidateTree(ViewCurrent(FActiveView));
  RefreshView(FActiveView);
  SetStatus(LocalText('afilemanager_status_refreshed','Refreshed')+': '+ViewCurrent(FActiveView));
end;
procedure TAFileManagerController.SelectAllClick(ASender: TArosaControl);
begin ViewList(FActiveView).SelectAll; SetStatus(IntToStr(ViewList(FActiveView).SelectedCount) + ' items selected'); end;
procedure TAFileManagerController.ClearSelectionClick(ASender: TArosaControl);
begin ViewList(FActiveView).ClearSelection; SetStatus('Selection cleared'); end;

procedure TAFileManagerController.BeginNameInput(const AKind, ADefaultPath,
  ASource: string);
begin
  FPendingInputKind := AKind;
  FPendingInputSource := ASource;
  FPendingInputView := FActiveView;
  ViewPathBox(FActiveView).Text := ADefaultPath;
  SetPathEditing(FActiveView, True);
  SetStatus('Enter the new name in the location field and press Enter. Escape/cancel by restoring the current path.');
end;

procedure TAFileManagerController.CommitNameInput(AView: Integer);
var P, OldPath: string; Ok: Boolean;
begin
  if (FPendingInputKind='') or (AView<>FPendingInputView) then Exit;
  P := Trim(ViewPathBox(AView).Text);
  OldPath := FPendingInputSource;
  Ok := False;
  { 0.5.110.60: an existing target is reported, never silently reused. }
  if (not SameText(FPendingInputKind,'rename')) and (FLocations<>nil) and FLocations.Exists(P) then
  begin
    SetStatus(FPendingInputKind+' not created: '+NameOperationFailure(FPendingInputKind,OldPath,P));
    FPendingInputKind := '';
    FPendingInputSource := '';
    ViewPathBox(AView).Text := ViewCurrent(AView);
    SetPathEditing(AView, False);
    Exit;
  end;
  if SameText(FPendingInputKind,'folder') then
    Ok := FResourceOperations.CreateFolder(P)
  else if SameText(FPendingInputKind,'file') then
    Ok := FResourceOperations.CreateFile(P)
  else if SameText(FPendingInputKind,'rename') then
    Ok := FResourceOperations.RenameResource(OldPath,P);
  if Ok then
    SetStatus(FPendingInputKind+' completed: '+P)
  else
    SetStatus(FPendingInputKind+' failed: '+P+' - '+NameOperationFailure(FPendingInputKind,OldPath,P));
  FPendingInputKind := '';
  FPendingInputSource := '';
  ViewPathBox(AView).Text := ViewCurrent(AView);
  SetPathEditing(AView, False);
  RefreshView(AView);
end;

procedure TAFileManagerController.CreateFolderClick(ASender: TArosaControl);
begin
  FCommandHistory.Remember('File.CreateFolder');
  if IsProviderLocation(ViewCurrent(FActiveView)) and ((FLocations=nil) or
     not (aracWrite in FLocations.Capabilities(ViewCurrent(FActiveView)))) then
  begin
    SetStatus('Create folder is not supported by this location provider');
    Exit;
  end;
  FPendingInputKind:='folder';
  FPendingInputSource:='';
  FPendingInputView:=FActiveView;
  if FNameDialog=nil then
    SetStatus('Create-folder dialog unavailable')
  else if IsProviderLocation(ViewCurrent(FActiveView)) then
    { remote and virtual locations have no .info icons }
    FNameDialog.ShowName('Create folder','Folder name','New Folder')
  else
    { On an AmigaDOS volume a drawer without "<name>.info" exists but is
      not shown by icon views (Wanderer, Workbench, the desktop in icon
      mode).  Whether the new folder gets one is the user's call. }
    FNameDialog.ShowNameWithOption('Create folder','Folder name','New Folder',
      LocalText('afilemanager_new_folder_icon',
        'Visible on the desktop: create its .info icon'),FNewFolderIcon);
end;

procedure TAFileManagerController.CreateFileClick(ASender: TArosaControl);
begin
  FCommandHistory.Remember('File.CreateFile');
  if IsProviderLocation(ViewCurrent(FActiveView)) and ((FLocations=nil) or
     not (aracWrite in FLocations.Capabilities(ViewCurrent(FActiveView)))) then
  begin
    SetStatus('Create file is not supported by this location provider');
    Exit;
  end;
  FPendingInputKind:='file';
  FPendingInputSource:='';
  FPendingInputView:=FActiveView;
  if FNameDialog<>nil then
    FNameDialog.ShowName('Create file','File name','New File')
  else
    SetStatus('Create-file dialog unavailable');
end;

procedure TAFileManagerController.RenameClick(ASender: TArosaControl);
var I: Integer; P: string;
begin
  FCommandHistory.Remember('File.Rename');
  I := ViewList(FActiveView).SelectedIndex;
  if I<0 then begin SetStatus('Select one resource to rename'); Exit; end;
  P := SelectedPath(FActiveView,I);
  if IsProviderLocation(P) and ((FLocations=nil) or
     not (aracRename in FLocations.Capabilities(P))) then
  begin
    SetStatus('Rename is not supported by this location provider');
    Exit;
  end;
  FPendingInputKind:='rename';
  FPendingInputSource:=P;
  FPendingInputView:=FActiveView;
  if FNameDialog<>nil then
    FNameDialog.ShowName('Rename','New name',FPaths.SplitFileName(P))
  else
    SetStatus('Rename dialog unavailable');
end;

procedure TAFileManagerController.NameDialogAccepted(ASender: TArosaControl; const AValue: string);
var
  Target, Base, IconProblem: string;
  Ok, Reported: Boolean;
  W: TArosaWorkspaceDefinition;
begin
  if FPendingInputKind='' then Exit;

  if SameText(FPendingInputKind,'workspace') then
  begin
    W:=nil;
    if FWorkspaces<>nil then W:=FWorkspaces.CreateWorkspace(Trim(AValue));
    if W=nil then
      SetStatus(LocalText('afilemanager_workspace_create_failed',
        'Workspace name is empty or already exists'))
    else if SaveWorkspacesToUserProfile then
    begin
      RebuildVirtualLocations;
      PublishLocationChanged('arosa://workspaces',almkCreate);
      SetStatus(SysUtils.Format(
        LocalText('afilemanager_workspace_created','Workspace created: %s'),
        [W.Name]));
      RefreshView(FPendingInputView);
    end
    else
    begin
      FWorkspaces.DeleteWorkspace(W.Id);
      SetStatus(LocalText('afilemanager_workspace_save_failed',
        'Workspace could not be saved to the user profile'));
    end;
    FPendingInputKind:='';
    FPendingInputSource:='';
    SetActiveView(FPendingInputView);
    Exit;
  end;

  Base:=ViewCurrent(FPendingInputView);
  if FLocationResourceAccess<>nil then Target:=FLocationResourceAccess.Join(Base,Trim(AValue))
  else Target:=FPaths.Join(Base,Trim(AValue));
  Ok:=False; Reported:=False;
  if SameText(FPendingInputKind,'rename') then
  begin
    if SameText(Target,FPendingInputSource) then Ok:=True
    else if (FLocations<>nil) and FLocations.Exists(Target) then
      begin SetStatus('Rename failed: destination already exists: '+Target); Reported:=True; end
    else
      Ok:=FResourceOperations.RenameResource(FPendingInputSource,Target);
  end
  else if (FLocations<>nil) and FLocations.Exists(Target) then
    begin SetStatus(FPendingInputKind+' not created: destination already exists: '+Target); Reported:=True; end
  else if SameText(FPendingInputKind,'folder') then
  begin
    Ok:=FResourceOperations.CreateFolder(Target);
    if (not IsProviderLocation(Target)) and (ASender=FNameDialog) and
       (FNameDialog<>nil) then
    begin
      { remember the answer whether or not the folder could be made }
      FNewFolderIcon:=FNameDialog.OptionChecked;
      if Ok and FNewFolderIcon then
      begin
        if ArosaCreateDrawerIcon(Target,IconProblem) then
          SetStatus(LocalText('afilemanager_folder_created_icon',
            'Folder created with its icon')+': '+Target)
        else
          SetStatus(LocalText('afilemanager_folder_created_no_icon',
            'Folder created, but its icon was not')+': '+Target+' - '+IconProblem);
        Reported:=True;
      end
      else if Ok then
      begin
        SetStatus(LocalText('afilemanager_folder_created_hidden',
          'Folder created without an icon (not shown in icon views)')+': '+Target);
        Reported:=True;
      end;
    end;
  end
  else if SameText(FPendingInputKind,'file') then
    Ok:=FResourceOperations.CreateFile(Target);

  if Ok and not Reported then SetStatus(FPendingInputKind+' completed: '+Target)
  else if not Reported then
    SetStatus(FPendingInputKind+' failed: '+Target);
  if Ok then
  begin
    if SameText(FPendingInputKind,'rename') then
      PublishLocationChanged(Base,almkRename)
    else
      PublishLocationChanged(Base,almkCreate);
  end;
  FPendingInputKind:='';
  FPendingInputSource:='';
  if not Ok then RefreshView(FPendingInputView);
  SetActiveView(FPendingInputView);
  if ASender=nil then ;
end;

function TAFileManagerController.CopyResourceRecursive(const ASource,
  ADestination: string): Boolean;
var Entries: TArosaFileInfoArray; I: Integer; S,D: string;
begin
  if not FPaths.IsDirectory(ASource) then
    Exit(FFiles.CopyFile(ASource,ADestination,True));
  if not FFiles.CreateDirectoryTree(ADestination) then Exit(False);
  if not FPaths.Enumerate(ASource,Entries) then Exit(False);
  for I:=0 to High(Entries) do
  begin
    if (Entries[I].Name='.') or (Entries[I].Name='..') then Continue;
    S:=FPaths.Join(ASource,Entries[I].Name);
    D:=FPaths.Join(ADestination,Entries[I].Name);
    if not CopyResourceRecursive(S,D) then Exit(False);
  end;
  Result:=True;
end;

function TAFileManagerController.DeleteResourceRecursive(const APath: string): Boolean;
var Entries: TArosaFileInfoArray; I: Integer; P: string;
begin
  if not FPaths.IsDirectory(APath) then Exit(FFiles.DeleteFile(APath));
  if not FPaths.Enumerate(APath,Entries) then Exit(False);
  for I:=0 to High(Entries) do
  begin
    if (Entries[I].Name='.') or (Entries[I].Name='..') then Continue;
    P:=FPaths.Join(APath,Entries[I].Name);
    if not DeleteResourceRecursive(P) then Exit(False);
  end;
  Result:=FFiles.RemoveDirectory(APath);
end;

procedure TAFileManagerController.CopyClick(ASender: TArosaControl);
var I: Integer; L: TArosaFilteredListView; Items: TStringList;
begin
  if ASender=FRightList then FActiveView:=1
  else if ASender=FLeftList then FActiveView:=0;
  FCommandHistory.Remember('File.Copy');
  Items:=TStringList.Create;
  try
    L:=ViewList(FActiveView);
    { 0.10.6.2: the selection list, in the order items were selected }
    CollectSelectedPaths(FActiveView,Items);
    if (Items.Count=0) and (L.SelectedIndex>=0) then
      Items.Add(SelectedPath(FActiveView,L.SelectedIndex));
    if Items.Count>0 then
    begin
      FResourceOperations.CopyToClipboard(Items);
      { Publish interoperable plain-text paths without replacing the resource
        clipboard, which remains authoritative for pane-to-pane file copies. }
      if (FPlatform<>nil) and (FPlatform.Clipboard<>nil) then
        FPlatform.Clipboard.SetText(Items.Text);
      SetStatus('Copied '+IntToStr(Items.Count)+' resource(s) to the AROSA clipboard');
      ArosaTrace('RESOURCE-COPY','count='+IntToStr(Items.Count)+' view='+IntToStr(FActiveView));
      {$IFNDEF AROS}Flush(Output);{$ENDIF}
    end
    else SetStatus('Select one or more resources to copy');
  finally Items.Free; end;
end;

procedure TAFileManagerController.CutClick(ASender: TArosaControl);
var I: Integer; L: TArosaFilteredListView; Items: TStringList; P: string;
begin
  if ASender=FRightList then FActiveView:=1
  else if ASender=FLeftList then FActiveView:=0;
  FCommandHistory.Remember('File.Cut');
  Items:=TStringList.Create;
  try
    L:=ViewList(FActiveView);
    { 0.10.6.2: the selection list, in the order items were selected }
    CollectSelectedPaths(FActiveView,Items);
    if (Items.Count=0) and (L.SelectedIndex>=0) then
      Items.Add(SelectedPath(FActiveView,L.SelectedIndex));
    if Items.Count>0 then
    begin
      for I:=0 to Items.Count-1 do
      begin
        P:=Items[I];
        if IsProviderLocation(P) and ((FLocations=nil) or
           not ((aracMove in FLocations.Capabilities(P)) or
                (aracDelete in FLocations.Capabilities(P)))) then
        begin
          SetStatus('Cut/move is not supported by this location provider');
          Exit;
        end;
      end;
      FResourceOperations.CutToClipboard(Items);
      SetStatus('Cut '+IntToStr(Items.Count)+' resource(s) to the AROSA clipboard');
      ArosaTrace('RESOURCE-CUT','count='+IntToStr(Items.Count)+' view='+IntToStr(FActiveView));
      {$IFNDEF AROS}Flush(Output);{$ENDIF}
    end
    else SetStatus('Select one or more resources to cut');
  finally Items.Free; end;
end;

procedure TAFileManagerController.PasteClick(ASender: TArosaControl);
var Done: Integer; Dest: string;
begin
  if ASender=FRightList then FActiveView:=1
  else if ASender=FLeftList then FActiveView:=0;
  FCommandHistory.Remember('File.Paste');
  Dest:=ViewCurrent(FActiveView);
  if IsProviderLocation(Dest) and ((FLocations=nil) or
     not (aracWrite in FLocations.Capabilities(Dest))) then
  begin
    SetStatus('Paste/write is not supported by this location provider');
    Exit;
  end;
  if (FResourceClipboard=nil) or not FResourceClipboard.HasResources then
  begin
    SetStatus('The resource clipboard is empty');
    ArosaTrace('RESOURCE-PASTE','clipboard-empty view='+IntToStr(FActiveView));
    {$IFNDEF AROS}Flush(Output);{$ENDIF}
    Exit;
  end;
  { 0.5.110.58: planned, conflicts decided, then run; refresh covers the
    destination and (for a cut) the source folders. }
  BeginResourceOperation('paste',nil,ViewCurrent(FActiveView),atoCopy,FActiveView);
end;

procedure TAFileManagerController.ExecutePendingDelete;
var Done, Total, J: Integer; Errors: string;
begin
  Done:=0;
  Total:=FPendingDeleteItems.Count;
  if Total=0 then Exit;
  { 0.5.110.60: report partial results and the reasons; previously a
    partial failure read as plain success ("Moved N"). }
  BeginOperationErrors;
  FResourceOperations.DeleteToTrash(FPendingDeleteItems,Done);
  Errors:=EndOperationErrors;
  for J:=0 to FPendingDeleteItems.Count-1 do
  begin
    if FLocations<>nil then
      PublishLocationChanged(FLocations.Parent(FPendingDeleteItems[J]),almkDelete)
    else
      PublishLocationChanged(ParentPath(FPendingDeleteItems[J]),almkDelete);
  end;
  PublishLocationChanged('arosa://workspace/'+FActiveWorkspaceId+'/trash',almkTrash);
  SetActiveView(FPendingDeleteView);
  if Done=Total then
    SetStatus(SysUtils.Format(LocalText('afilemanager_status_trash_all','Moved %d item(s) to the AROSA trash'),[Done]))
  else if Done>0 then
    SetStatus(SysUtils.Format(LocalText('afilemanager_status_trash_some','Moved %d of %d item(s) to the AROSA trash'),[Done,Total])+Errors)
  else
    SetStatus(LocalText('afilemanager_status_trash_none','Nothing was moved to the trash')+Errors);
  FPendingDeleteItems.Clear;
end;

procedure TAFileManagerController.ConfirmDeleteClick(ASender: TArosaControl);
var W: TArosaWorkspaceDefinition; DeletedId, DeletedName: string;
begin
  if FPendingDeleteWorkspaceId<>'' then
  begin
    DeletedId:=FPendingDeleteWorkspaceId;
    FPendingDeleteWorkspaceId:='';
    W:=nil;
    if FWorkspaces<>nil then W:=FWorkspaces.Find(DeletedId);
    if W<>nil then DeletedName:=W.Name else DeletedName:=DeletedId;
    CloseWorkspacePrototype(DeletedId);
    if (FWorkspaces<>nil) and FWorkspaces.DeleteWorkspace(DeletedId) then
    begin
      if SaveWorkspacesToUserProfile then
      begin
        RebuildVirtualLocations;
        PublishLocationChanged('arosa://workspaces',almkDelete);
        RefreshView(FActiveView);
        SetStatus(SysUtils.Format(
          LocalText('afilemanager_workspace_deleted','Workspace deleted: %s'),
          [DeletedName]));
      end
      else
        SetStatus(LocalText('afilemanager_workspace_save_failed',
          'Workspace could not be saved to the user profile'));
    end;
  end
  else if FPendingTrashRestore then
  begin
    Diagnostic('COMMAND Trash.Restore confirmed');
    ExecuteTrashRestore;
  end
  else if FPendingPermanentTrashDelete then
  begin
    Diagnostic('COMMAND Trash.DeletePermanently confirmed');
    ExecutePermanentTrashDelete;
  end
  else if FPendingEmptyTrash then
  begin
    FPendingEmptyTrash:=False;
    Diagnostic('COMMAND Trash.Empty confirmed');
    EmptyTrash;
  end
  else
  begin
    Diagnostic('COMMAND File.Delete confirmed');
    ExecutePendingDelete;
  end;
  { Deletion refreshes the list model while the modal overlay is being removed.
    Force a full retained-tree repaint so no dimmed or blank frame survives. }
  if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
end;

procedure TAFileManagerController.CancelDeleteClick(ASender: TArosaControl);
begin
  if FPendingDeleteWorkspaceId<>'' then
  begin
    FPendingDeleteWorkspaceId:='';
    SetStatus(LocalText('afilemanager_workspace_delete_cancelled',
      'Workspace deletion cancelled'));
  end
  else if FPendingTrashRestore then
  begin
    FPendingTrashRestore:=False;
    FPendingDeleteItems.Clear;
    Diagnostic('COMMAND Trash.Restore cancelled');
    SetStatus(LocalText('afilemanager_trash_restore_cancelled','Restore cancelled'));
  end
  else if FPendingPermanentTrashDelete then
  begin
    FPendingPermanentTrashDelete:=False;
    FPendingDeleteItems.Clear;
    Diagnostic('COMMAND Trash.DeletePermanently cancelled');
    SetStatus(LocalText('afilemanager_trash_delete_permanently_cancelled',
      'Permanent deletion cancelled'));
  end
  else if FPendingEmptyTrash then
  begin
    FPendingEmptyTrash:=False;
    Diagnostic('COMMAND Trash.Empty cancelled');
    SetStatus(LocalText('afilemanager_trash_empty_cancelled','Empty Trash cancelled'));
  end
  else
  begin
    Diagnostic('COMMAND File.Delete cancelled');
    FPendingDeleteItems.Clear;
    SetStatus('Deletion cancelled');
  end;
  if FForm<>nil then FForm.InvalidatePaint;
end;

procedure TAFileManagerController.DeleteClick(ASender: TArosaControl);
var I: Integer; L: TArosaFilteredListView; NameText: string;
begin
  FCommandHistory.Remember('File.Delete');
  if ASender=FRightList then FActiveView:=1
  else if ASender=FLeftList then FActiveView:=0;
  L:=ViewList(FActiveView);
  if (L=nil) or (L.SelectedCount=0) then
  begin
    SetStatus('Select one or more resources to delete');
    ArosaTrace('RESOURCE-DELETE','no-selection view='+IntToStr(FActiveView));
    {$IFNDEF AROS}Flush(Output);{$ENDIF}
    Exit;
  end;
  FPendingDeleteItems.Clear;
  FPendingDeleteView:=FActiveView;
  CollectSelectedPaths(FActiveView,FPendingDeleteItems);
  for I:=0 to FPendingDeleteItems.Count-1 do
    if IsProviderLocation(FPendingDeleteItems[I]) and ((FLocations=nil) or
       not (aracDelete in FLocations.Capabilities(FPendingDeleteItems[I]))) then
    begin
      SetStatus('Delete is not supported by this location provider');
      FPendingDeleteItems.Clear;
      Exit;
    end;
  if FPendingDeleteItems.Count=1 then NameText:=FLocationResourceAccess.LeafName(FPendingDeleteItems[0])
  else NameText:=IntToStr(FPendingDeleteItems.Count)+' selected resources';
  Diagnostic('COMMAND File.Delete requested count='+IntToStr(FPendingDeleteItems.Count));
  if not FConfirmDeletion then begin
    Diagnostic('COMMAND File.Delete confirmation-disabled');
    ExecutePendingDelete; Exit; end;
  if FDeleteDialog<>nil then
  begin
    FDeleteDialog.ShowConfirmation('Confirm deletion',
      'Move '+NameText+' to the AROSA trash?', 'Delete', 'Cancel');
    SetStatus('Waiting for confirmation: move '+NameText+' to trash');
    Diagnostic('DIALOG delete visible='+BoolToStr(FDeleteDialog.Visible,True));
    if FForm<>nil then begin FForm.InvalidateLayout; FForm.InvalidatePaint; end;
  end
  else
    SetStatus('Confirmation dialog unavailable; nothing was deleted');
end;

procedure TAFileManagerController.ExitClick(ASender: TArosaControl);
begin
  RequestApplicationClose;
end;

procedure TAFileManagerController.ClearUndo;
begin
  FUndoKind := ''; FUndoSources.Clear; FUndoDestinations.Clear;
end;

procedure TAFileManagerController.UndoClick(ASender: TArosaControl);
begin
  FCommandHistory.Remember('History.Undo');
  if not FResourceOperations.CanUndo then begin SetStatus('Nothing to undo'); Exit; end;
  BeginOperationErrors;
  if FResourceOperations.Undo then
  begin RefreshBoth; SetActiveView(FActiveView); SetStatus('Undo completed'+EndOperationErrors); end
  else
  begin
    RefreshBoth;
    SetStatus('Undo failed: the items could not be restored to their previous state'+EndOperationErrors);
  end;
end;

procedure TAFileManagerController.RedoClick(ASender: TArosaControl);
begin
  FCommandHistory.Remember('History.Redo');
  if not FResourceOperations.CanRedo then begin SetStatus('Nothing to redo'); Exit; end;
  BeginOperationErrors;
  if FResourceOperations.Redo then
  begin RefreshBoth; SetActiveView(FActiveView); SetStatus('Redo completed'+EndOperationErrors); end
  else
  begin
    RefreshBoth;
    SetStatus('Redo failed: the operation could not be applied again'+EndOperationErrors);
  end;
end;

procedure TAFileManagerController.ConsoleClick(ASender: TArosaControl);
begin
  { Every explicit Console command creates an independent session. }
  OpenConsoleAt(ViewCurrent(FActiveView));
end;

function TAFileManagerController.ConsoleDocumentForControl(
  AControl: TArosaControl): TAFileManagerConsoleDocument;
var I: Integer; D: TAFileManagerConsoleDocument;
begin
  Result:=nil;
  if FConsoles=nil then Exit;
  for I:=0 to FConsoles.Count-1 do
  begin
    D:=TAFileManagerConsoleDocument(FConsoles[I]);
    if (D.Console=AControl) or (D.CloseButton=AControl) then Exit(D);
  end;
end;


function TAFileManagerController.ConsoleDocumentForCommandSender(
  AControl: TArosaControl): TAFileManagerConsoleDocument;
var
  I: Integer;
  D: TAFileManagerConsoleDocument;
  V: TArosaVisual;
begin
  Result:=nil;
  if (AControl=nil) or (FConsoles=nil) then Exit;

  Result:=ConsoleDocumentForControl(AControl);
  if Result<>nil then Exit;

  { Floating Console toolbar/Operations controls are a separate retained tree.
    Resolve their owning Console from visual ancestry so commands cannot leak
    to whichever tab happens to be active in the AFileManager window. }
  V:=AControl;
  while V<>nil do
  begin
    for I:=0 to FConsoles.Count-1 do
    begin
      D:=TAFileManagerConsoleDocument(FConsoles[I]);
      if (V=D.Console) or (V=D.FloatingToolbarTabs) or
         (V=D.FloatingOperationTabs) or (V=D.EmbeddedFrame) then
        Exit(D);
    end;
    V:=V.ParentVisual;
  end;
end;

function TAFileManagerController.ConsoleCommandDocument(
  AControl: TArosaControl): TAFileManagerConsoleDocument;
begin
  Result:=ConsoleDocumentForCommandSender(AControl);
  if Result=nil then Result:=ActiveConsoleDocument;
end;

function TAFileManagerController.ActiveConsoleDocument: TAFileManagerConsoleDocument;
var I: Integer; D: TAFileManagerConsoleDocument;
begin
  Result:=nil;
  if (FConsoles=nil) or (FDocumentTabs=nil) then Exit;
  for I:=0 to FConsoles.Count-1 do
  begin
    D:=TAFileManagerConsoleDocument(FConsoles[I]);
    if D.TabIndex=FDocumentTabs.SelectedIndex then Exit(D);
  end;
  { The Operations Console tab can remain selected while another document is
    active; in that case operate on the most recently created open console. }
  if FConsoles.Count>0 then Result:=TAFileManagerConsoleDocument(FConsoles[FConsoles.Count-1]);
end;

function TAFileManagerController.AllocateConsoleId: Integer;
var Candidate, I: Integer; Used: Boolean;
begin
  Candidate:=1;
  repeat
    Used:=False;
    if FConsoles<>nil then
      for I:=0 to FConsoles.Count-1 do
        if TAFileManagerConsoleDocument(FConsoles[I]).Id=Candidate then begin Used:=True; Break; end;
    if not Used then Exit(Candidate);
    Inc(Candidate);
  until False;
end;

procedure TAFileManagerController.SetConsoleOperationsVisible(AVisible: Boolean);
var I: Integer;
begin
  if (FConsoleOperationsPage=nil) or (FOperationTabs=nil) then Exit;
  FConsoleOperationsPage.Visible:=AVisible;
  if (not AVisible) and (FOperationTabs.SelectedIndex=FConsoleOperationsIndex) then
  begin
    for I:=0 to FOperationTabs.PageCount-1 do
      if SameText(FOperationTabs.PageTitle(I),LocalText('afilemanager_tab_commands','COMMANDS')) or
         SameText(FOperationTabs.PageTitle(I),'COMMANDS') then
      begin FOperationTabs.SelectedIndex:=I; Break; end;
  end;
  FOperationTabs.InvalidateLayout;
  FOperationTabs.InvalidatePaint;
end;

procedure TAFileManagerController.ConsoleOperationNewClick(ASender: TArosaControl);
var Source: TAFileManagerConsoleDocument;
begin
  { New Console follows the application-frame context that issued it.  A
    floating Console must never create its new sibling back inside the parent
    AFileManager merely because the controller also owns embedded Consoles. }
  Source:=ConsoleDocumentForCommandSender(ASender);
  if Source<>nil then
    Diagnostic('CONSOLE new requested source-id='+IntToStr(Source.Id))
  else
    Diagnostic('CONSOLE new requested source=main');
  OpenConsoleFromSource(Source);
end;

procedure TAFileManagerController.ConsoleOperationClearClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then D.Console.ClearOutput
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleOperationCloseClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if D<>nil then CloseConsoleDocument(D) else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleSearchClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then D.Console.ShowSearch
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleWrapClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then
  begin
    D.Console.ExecuteCommand('View.WordWrap');
    UpdateConsoleToolState;
  end
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleColumnsClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then
  begin
    if D.Console.ColumnCount<=1 then D.Console.ColumnCount:=2
    else D.Console.ColumnCount:=1;
    D.Console.ColumnMode:=D.Console.ColumnCount>1;
    ReflowConsoleColumns(D.Console);
    SetStatus('Console columns: '+IntToStr(D.Console.ColumnCount));
    UpdateConsoleToolState;
  end
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleColumnLessClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then
  begin
    if D.Console.ColumnCount>1 then D.Console.ColumnCount:=D.Console.ColumnCount-1;
    D.Console.ColumnMode:=D.Console.ColumnCount>1;
    ReflowConsoleColumns(D.Console);
    SetStatus('Console columns: '+IntToStr(D.Console.ColumnCount));
    UpdateConsoleToolState;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleColumnMoreClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then
  begin
    if D.Console.ColumnCount<4 then D.Console.ColumnCount:=D.Console.ColumnCount+1;
    D.Console.ColumnMode:=D.Console.ColumnCount>1;
    ReflowConsoleColumns(D.Console);
    SetStatus('Console columns: '+IntToStr(D.Console.ColumnCount));
    UpdateConsoleToolState;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerController.UpdateConsoleToolState;
var
  D: TAFileManagerConsoleDocument;
  Dummy: Integer;
begin
  D:=ActiveConsoleDocument;
  if (D=nil) or (D.Console=nil) then
  begin
    if FConsoleWrapButton<>nil then FConsoleWrapButton.Enabled:=False;
    if FConsoleColumnsButton<>nil then FConsoleColumnsButton.Enabled:=False;
    if FConsoleColumnLessButton<>nil then FConsoleColumnLessButton.Enabled:=False;
    if FConsoleColumnMoreButton<>nil then FConsoleColumnMoreButton.Enabled:=False;
    if FConsoleFontSmallerButton<>nil then
    begin
      FConsoleFontSmallerButton.Visible:=True;
      FConsoleFontSmallerButton.Enabled:=True;
      FConsoleFontSmallerButton.Toggled:=False;
      FConsoleFontSmallerButton.ReadOnlyAppearance:=False;
    end;
    if FConsoleFontLargerButton<>nil then
    begin
      FConsoleFontLargerButton.Visible:=True;
      FConsoleFontLargerButton.Enabled:=True;
      FConsoleFontLargerButton.Toggled:=False;
      FConsoleFontLargerButton.ReadOnlyAppearance:=False;
    end;
    Exit;
  end;

  if FConsoleWrapButton<>nil then
  begin
    FConsoleWrapButton.Enabled:=True;
    FConsoleWrapButton.Toggled:=D.Console.WordWrap;
  end;
  if FConsoleColumnsButton<>nil then
  begin
    FConsoleColumnsButton.Enabled:=True;
    FConsoleColumnsButton.Toggled:=D.Console.ColumnCount>1;
  end;
  if FConsoleColumnLessButton<>nil then
  begin
    FConsoleColumnLessButton.Visible:=True;
    FConsoleColumnLessButton.Enabled:=D.Console.ColumnCount>1;
  end;
  if FConsoleColumnMoreButton<>nil then
  begin
    FConsoleColumnMoreButton.Visible:=True;
    FConsoleColumnMoreButton.Enabled:=D.Console.ColumnCount<4;
  end;
  if FConsoleFontSmallerButton<>nil then
  begin
    FConsoleFontSmallerButton.Visible:=True;
    FConsoleFontSmallerButton.Enabled:=True;
    FConsoleFontSmallerButton.Toggled:=False;
    FConsoleFontSmallerButton.ReadOnlyAppearance:=False;
  end;
  if FConsoleFontLargerButton<>nil then
  begin
    FConsoleFontLargerButton.Visible:=True;
    FConsoleFontLargerButton.Enabled:=True;
    FConsoleFontLargerButton.Toggled:=False;
    FConsoleFontLargerButton.ReadOnlyAppearance:=False;
  end;
end;

procedure TAFileManagerController.FormatConsoleColumns(ALines: TStrings;
  AConsole: TArosaCommandConsole);
var
  I,C,R,Rows,Cols,CellWidth,AvailChars,OutIndex,P: Integer;
  Src,Wrapped: TStringList;
  Line,S,Chunk: string;
begin
  if (ALines=nil) or (AConsole=nil) then Exit;
  Cols:=AConsole.ColumnCount;
  if Cols<=1 then Exit;
  if Cols>4 then Cols:=4;
  AvailChars:=AConsole.VisibleTextColumns;
  if AvailChars<20 then Exit;
  CellWidth:=(AvailChars div Cols)-2;
  if CellWidth<12 then Exit;

  { Preserve all text. Long shell lines are wrapped to the selected column
    width before newspaper-style distribution; nothing is truncated merely
    because the user requested two or three columns. }
  Wrapped:=TStringList.Create;
  Src:=TStringList.Create;
  try
    Src.Assign(ALines);
    for I:=0 to Src.Count-1 do
    begin
      Line:=Src[I];
      if Line='' then begin Wrapped.Add(''); Continue; end;
      P:=1;
      while P<=Length(Line) do
      begin
        Chunk:=Copy(Line,P,CellWidth);
        Wrapped.Add(Chunk);
        Inc(P,CellWidth);
      end;
    end;

    Rows:=(Wrapped.Count+Cols-1) div Cols;
    ALines.Clear;
    for R:=0 to Rows-1 do
    begin
      S:='';
      for C:=0 to Cols-1 do
      begin
        OutIndex:=R+C*Rows;
        if OutIndex<Wrapped.Count then
        begin
          Line:=Wrapped[OutIndex];
          if C<Cols-1 then
            Line:=Line+StringOfChar(' ',CellWidth-Length(Line)+2);
          S:=S+Line;
        end;
      end;
      ALines.Add(TrimRight(S));
    end;
    Diagnostic('CONSOLE columns applied requested='+IntToStr(AConsole.ColumnCount)+
      ' visible-cols='+IntToStr(AvailChars)+' cell='+IntToStr(CellWidth)+
      ' source-lines='+IntToStr(Src.Count)+' display-lines='+IntToStr(ALines.Count));
  finally
    Src.Free;
    Wrapped.Free;
  end;
end;

procedure TAFileManagerController.ReflowConsoleColumns(
  AConsole: TArosaCommandConsole);
var
  Raw,Display: TStringList;
  I: Integer;
begin
  if AConsole=nil then Exit;
  Raw:=TStringList.Create;
  Display:=TStringList.Create;
  try
    for I:=0 to AConsole.RawTranscriptCount-1 do
      Raw.Add(AConsole.RawTranscriptLine(I));
    Display.Assign(Raw);
    if AConsole.ColumnCount>1 then FormatConsoleColumns(Display,AConsole);
    AConsole.ReplaceRenderedTranscript(Display);
    AConsole.FocusInput;
    { Column count changes alter the visual-line geometry, not merely pixels.
      Force the retained layout chain to measure/arrange the editor again. }
    AConsole.InvalidateLayout;
    AConsole.InvalidatePaint;
    if FDocumentTabs<>nil then
    begin
      FDocumentTabs.InvalidateLayout;
      FDocumentTabs.InvalidatePaint;
    end;
    if FForm<>nil then
    begin
      FForm.InvalidateLayout;
      FForm.InvalidatePaint;
    end;
  finally
    Display.Free;
    Raw.Free;
  end;
end;

function TAFileManagerController.ConsoleAdjacentFontSize(
  AConsole: TArosaCommandConsole; ADirection: Integer;
  out ASize: Integer): Boolean;
var
  I,J,P,V,N,Current: Integer;
  Face: TArosaFontFace;
  Token,SizesText: string;
  Sizes: array[0..63] of Integer;
  Found: Boolean;
begin
  Result:=False;
  ASize:=0;
  if AConsole=nil then Exit;
  Current:=AConsole.FontSize;
  N:=0;
  SizesText:='';

  { Bitmap fonts move only between sizes that actually exist in the font
    catalogue. Scalable fonts retain conventional one-point stepping. }
  if FFontService<>nil then
  begin
    if FFontService.IsScalable(AConsole.FontFamily) then
    begin
      ASize:=Current+ADirection;
      if ASize<6 then ASize:=6;
      if ASize>72 then ASize:=72;
      Result:=ASize<>Current;
      Exit;
    end;

    for I:=0 to FFontService.FaceCount-1 do
    begin
      Face:=FFontService.Face(I);
      if SameText(Face.Family,AConsole.FontFamily) and (Face.Sizes<>'') then
      begin
        if SizesText<>'' then SizesText:=SizesText+',';
        SizesText:=SizesText+Face.Sizes;
      end;
    end;
  end;

  while SizesText<>'' do
  begin
    P:=Pos(',',SizesText);
    if P=0 then
    begin
      Token:=Trim(SizesText);
      SizesText:='';
    end
    else
    begin
      Token:=Trim(Copy(SizesText,1,P-1));
      Delete(SizesText,1,P);
    end;

    if TryStrToInt(Token,V) and (V>0) then
    begin
      Found:=False;
      for I:=0 to N-1 do
        if Sizes[I]=V then
        begin
          Found:=True;
          Break;
        end;
      if (not Found) and (N<Length(Sizes)) then
      begin
        Sizes[N]:=V;
        Inc(N);
      end;
    end;
  end;

  for I:=0 to N-2 do
    for J:=I+1 to N-1 do
      if Sizes[J]<Sizes[I] then
      begin
        V:=Sizes[I];
        Sizes[I]:=Sizes[J];
        Sizes[J]:=V;
      end;

  if N=0 then Exit;

  if ADirection<0 then
  begin
    for I:=N-1 downto 0 do
      if Sizes[I]<Current then
      begin
        ASize:=Sizes[I];
        Result:=True;
        Exit;
      end;
  end
  else
  begin
    for I:=0 to N-1 do
      if Sizes[I]>Current then
      begin
        ASize:=Sizes[I];
        Result:=True;
        Exit;
      end;
  end;
end;

procedure TAFileManagerController.ConsoleFontSmallerClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument; S: Integer;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) and ConsoleAdjacentFontSize(D.Console,-1,S) then
  begin
    D.Console.FontSize:=S;
    D.Console.InvalidateLayout;
    D.Console.InvalidatePaint;
    SetStatus('Console font: '+D.Console.FontFamily+' '+IntToStr(S)+' pt');
    UpdateConsoleToolState;
  end
  else SetStatus('No smaller installed size for the active console font');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleFontLargerClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument; S: Integer;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) and ConsoleAdjacentFontSize(D.Console,1,S) then
  begin
    D.Console.FontSize:=S;
    D.Console.InvalidateLayout;
    D.Console.InvalidatePaint;
    SetStatus('Console font: '+D.Console.FontFamily+' '+IntToStr(S)+' pt');
    UpdateConsoleToolState;
  end
  else SetStatus('No larger installed size for the active console font');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleHistoryPreviousClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then D.Console.RecallPrevious
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleHistoryNextClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleCommandDocument(ASender);
  if (D<>nil) and (D.Console<>nil) then D.Console.RecallNext
  else SetStatus('No active console');
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleEnvironmentInfoClick(ASender: TArosaControl);
var D: TAFileManagerConsoleDocument; ShellName: string;
begin
  D:=ConsoleCommandDocument(ASender);
  if D=nil then
  begin
    SetStatus('No active console');
    Exit;
  end;
  case D.Session.Flavour of
    asfAmigaDOS: ShellName:='AmigaDOS';
    asfWindows: ShellName:='Windows';
  else
    ShellName:='POSIX';
  end;
  SetStatus('Console: '+ShellName+'  '+D.Session.Location);
  if ASender=nil then ;
end;

constructor TAFileManagerConsoleFrameSession.CreateForConsole(
  const ASessionId, ATitle: string; AConsole: TArosaCommandConsole);
begin
  inherited CreateSession(ASessionId,'arosa.console','console://'+ASessionId,
    'application/x-arosa-console');
  FConsole:=AConsole;
  FTitle:=ATitle;
end;

function TAFileManagerConsoleFrameSession.CreateSurfaceCore: TArosaApplicationSurface;
var C: TArosaCommandConsole;
begin
  C:=FConsole;
  FConsole:=nil;
  if C=nil then
    raise Exception.Create('Console application session has no console surface');
  Result:=TArosaApplicationSurface.CreateSurface(Self,SessionId+'-surface',
    FTitle,'theme:console',C,[aascEmbed,aascDetach,aascMoveWorkspace]);
end;

function TAFileManagerController.CreateConsoleDocument(
  const ALocation: string): TAFileManagerConsoleDocument;
var Page: TArosaTabPage; Column: TArosaColumnPanel; Toolbar: TArosaRowPanel;
    B: TArosaButton; Err, Caption: string; Mono: TArosaFontDescription;
    Host: IArosaApplicationFrameHost; App: TArosaApplication;
begin
  Result:=nil;
  if (FDocumentTabs=nil) or (FLocations=nil) or (FShellService=nil) then Exit;
  Result:=TAFileManagerConsoleDocument.Create;
  Result.Id:=AllocateConsoleId;
  Caption:=LocalText('afilemanager_tab_console','Console')+' '+IntToStr(Result.Id);
  Page:=TFileManagerTabPage.CreateStyled(FTheme,Caption);
  Page.SetConstraintHeight(asmStar,ArosaCoord(1));
  Result.Page:=Page;

  Column:=TArosaColumnPanel.Create;
  Column.SetConstraintWidth(asmStar,ArosaCoord(1));
  Column.SetConstraintHeight(asmStar,ArosaCoord(1));
  Column.Spacing:=ArosaCoord(0);

  { Console controls belong to the environment toolbar/operations surfaces;
    the document itself is the reusable AROSA editor-backed terminal. }
  Result.CloseButton:=nil;
  Result.Console:=TArosaCommandConsole.CreateControl(FTheme,FFonts);
  Result.Console.SetConstraintHeight(asmStar,ArosaCoord(1));
  Result.Console.OnSubmit:=@ConsoleSubmit;
  Result.Console.OnConsoleCommand:=@ConsoleContextCommand;
  Result.Console.OnConsoleCommandEnabled:=@ConsoleContextCommandEnabled;
  Result.Console.Clipboard:=FPlatform.Clipboard;
  Result.Console.MenuWordWrap:=LocalText('arosa_editor_word_wrap','Word wrap');
  Result.Console.MenuSearch:=LocalText('arosa_editor_search','Find');
  Result.Console.MenuReplace:=LocalText('arosa_editor_replace','Replace');
  Result.Console.OnCommandIcon:=@ContextCommandIcon;
  Result.Console.MenuPrevious:=LocalText('arosa_editor_previous','Previous');
  Result.Console.MenuNext:=LocalText('arosa_editor_next','Next');
  Result.Console.MenuHighlighting:=LocalText('arosa_editor_highlighting','Highlighting');
  Result.Console.MenuCopy:=LocalText('arosa_editor_copy','Copy');
  Result.Console.MenuCut:=LocalText('arosa_editor_cut','Cut');
  Result.Console.MenuPaste:=LocalText('arosa_editor_paste','Paste');
  if FDescriptor<>nil then
  begin
    Result.Console.BackgroundRole:=FDescriptor.Value('ConsolePresentation',
      'BackgroundRole',AROSA_ROLE_EDITOR_BG);
    Result.Console.TextRole:=FDescriptor.Value('ConsolePresentation',
      'TextRole',AROSA_ROLE_PRIMARY_TEXT);
    Result.Console.SearchMatchRole:=FDescriptor.Value('ConsolePresentation',
      'SearchMatchRole',AROSA_ROLE_WARNING);
    Result.Console.SearchCurrentRole:=FDescriptor.Value('ConsolePresentation',
      'SearchCurrentRole',AROSA_ROLE_ACCENT);
    Result.Console.ColumnDividerRole:=FDescriptor.Value('ConsolePresentation',
      'ColumnDividerRole',AROSA_ROLE_BORDER);
  end;
  { Shells use the theme's canonical monospace role, matching the native
    AmigaDOS shell presentation rather than the proportional UI font. }
  Mono:=FTheme.FontFor(afrMonospace);
  Result.Console.FontFamily:=Mono.Family;
  Result.Console.FontSize:=Mono.SizePoints;
  { The console visual is hosted by the Application Frame rather than by the
    tab page directly.  Detach/attach can therefore move this exact editor
    surface without losing transcript, history, caret or shell state. }
  Result.EmbeddedFrame:=TArosaEmbeddedApplicationFrame.CreateFrame(
    'afilemanager.console.'+IntToStr(Result.Id)+'.embedded',FActiveWorkspaceId);
  Result.EmbeddedFrame.SetConstraintWidth(asmStar,ArosaCoord(1));
  Result.EmbeddedFrame.SetConstraintHeight(asmStar,ArosaCoord(1));
  Column.AddVisual(Result.EmbeddedFrame);
  Page.AddVisual(Column);
  { Production consoles are sessions of the application Shell Service.
    The session selects the AmigaDOS adapter on AROS. }
  Result.Session:=TArosaShellSession.Create(FLocations,FShellService);
  if FDescriptor<>nil then
  begin
    Result.Session.TimeoutMs:=FDescriptor.IntValue('Console','TimeoutSeconds',30)*1000;
    Result.Console.MaxLines:=FDescriptor.IntValue('Console','ScrollbackLines',5000);
    Result.Console.WordWrap:=FDescriptor.BoolValue('Console','WordWrap',True);
    Result.Console.Highlighting:=FDescriptor.BoolValue('Console','Highlighting',True);
  end;
  case Result.Session.Flavour of
    asfAmigaDOS: Result.Console.Language:='AmigaDOS';
    asfWindows: Result.Console.Language:='WindowsShell';
  else
    Result.Console.Language:='POSIXShell';
  end;
  if not Result.Session.ChangeLocation(ALocation,Err) then
  begin
    Result.Console.WriteLine('ERROR: '+Err);
    SetStatus('Console could not change location: '+Err);
  end;
  Result.Console.Prompt:=Result.Session.Prompt;

  Result.FrameSession:=TAFileManagerConsoleFrameSession.CreateForConsole(
    'afilemanager-console-'+IntToStr(Result.Id),Caption,Result.Console);
  Result.FrameSurface:=nil;
  Result.FloatingFrame:=nil;
  Result.FloatingToolbarTabs:=nil;
  Result.FloatingOperationTabs:=nil;
  Result.FloatingTheme:=nil;
  Result.ProcessId:=0;
  Result.ProcessOutputLength:=0;
  Result.ProcessErrorLength:=0;
  Result.ProcessStartedAt:=0;
  Result.ProcessTimeoutMs:=Result.Session.TimeoutMs;
  Result.ProcessLine:='';
  if FApplicationFrames=nil then
    raise Exception.Create('Application Frame Service is not available');
  FApplicationFrames.RegisterHost(Result.EmbeddedFrame);
  Host:=Result.EmbeddedFrame;
  try
    Result.FrameSurface:=FApplicationFrames.AdoptSession(Result.FrameSession,Host);
  except
    FApplicationFrames.UnregisterHost(Result.EmbeddedFrame);
    Result.FrameSession:=nil; { AdoptSession owns/frees it on failure. }
    raise;
  end;

  App:=nil;
  if FNativeHost<>nil then App:=FNativeHost.Application;
  if App<>nil then
  begin
    Result.FloatingFrame:=TArosaFloatingApplicationFrame.CreateFrame(App,
      'afilemanager.console.'+IntToStr(Result.Id)+'.floating',FActiveWorkspaceId);
    if FNativeHost<>nil then Result.FloatingFrame.TargetScreen:=FNativeHost.TargetScreen;
    Result.FloatingFrame.InitialBounds:=ArosaRectXYWH(100,80,760,520);
    Result.FloatingFrame.OnCloseRequest:=@ConsoleFrameCloseRequested;
    Result.FloatingFrame.OnActivate:=@ConsoleFrameActivated;
    FApplicationFrames.RegisterHost(Result.FloatingFrame);
  end;

  UpdateConsoleCaption(Result);
  Result.TabIndex:=FDocumentTabs.AddTabPage(Page);
  FConsoles.Add(Result);
  FDocumentTabs.SelectedIndex:=Result.TabIndex;
  if FNativeHost<>nil then FNativeHost.FocusControl(Result.Console);
  FConsole:=Result.Console;
  FShellSession:=Result.Session;
  Diagnostic('CONSOLE document created id='+IntToStr(Result.Id)+' index='+IntToStr(Result.TabIndex));
end;

procedure TAFileManagerController.CloseConsoleDocument(
  ADoc: TAFileManagerConsoleDocument);
begin
  if (ADoc=nil) or (FConsoles=nil) then Exit;
  { A close command can originate inside the Console editor/context-menu event
    dispatch.  Removing the tab at that point frees the sender and its visual
    ancestors while their callback is still on the stack.  Defer destruction
    until the event loop is idle, exactly as secondary-window close does. }
  if FDeferredCloseConsole<>nil then Exit;
  FDeferredCloseConsole:=ADoc;
  if (FNativeHost<>nil) and (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) and
     not FConsoleCloseIdleAttached then
  begin
    FNativeHost.Application.Loop.AddIdleHandler(@ConsoleCloseIdle);
    FConsoleCloseIdleAttached:=True;
  end
  else if (FNativeHost=nil) or (FNativeHost.Application=nil) or (FNativeHost.Application.Loop=nil) then
  begin
    FDeferredCloseConsole:=nil;
    CloseConsoleDocumentNow(ADoc);
  end;
end;

procedure TAFileManagerController.ConsoleCloseIdle(var AMoreWorkPending: Boolean);
var D: TAFileManagerConsoleDocument;
begin
  if FConsoleCloseIdleAttached and (FNativeHost<>nil) and (FNativeHost.Application<>nil) and (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@ConsoleCloseIdle);
    FConsoleCloseIdleAttached:=False;
  end;
  D:=FDeferredCloseConsole;
  FDeferredCloseConsole:=nil;
  if D<>nil then CloseConsoleDocumentNow(D);
  AMoreWorkPending:=False;
end;

procedure TAFileManagerController.CloseConsoleDocumentNow(
  ADoc: TAFileManagerConsoleDocument);
var I, Removed: Integer; NewActive: TAFileManagerConsoleDocument;
begin
  if (ADoc=nil) or (FConsoles=nil) or (FDocumentTabs=nil) then Exit;
  if FConsoles.IndexOf(ADoc)<0 then Exit;
  { Resolve the live tab by page identity. Index 0 is the permanent Files
    page and must never be removed by console teardown. }
  Removed:=-1;
  for I:=1 to FDocumentTabs.ChildVisualCount-1 do
    if FDocumentTabs.ChildVisuals[I]=ADoc.Page then
    begin
      Removed:=I;
      Break;
    end;
  if Removed<=0 then
  begin
    Diagnostic('CONSOLE close refused: console page is not attached');
    Exit;
  end;
  if FNativeHost<>nil then FNativeHost.FocusControl(nil);

  { Clear aliases BEFORE RemovePage: RemovePage fires OnChange synchronously
    and also frees the Console visual owned by the page. }
  if FConsole=ADoc.Console then FConsole:=nil;
  if FShellSession=ADoc.Session then FShellSession:=nil;
  if (ADoc.ProcessId<>0) and (FShellService<>nil) then
  begin
    FShellService.CancelShellLine(ADoc.ProcessId);
    FShellService.ReleaseShellLine(ADoc.ProcessId);
    ADoc.ProcessId:=0;
  end;
  FConsoles.Remove(ADoc);

  { Update surviving indices before the tab host emits OnChange so the
    callback can identify the newly active document with current indices. }
  for I:=0 to FDocuments.Count-1 do
    if TAFileManagerDocument(FDocuments[I]).TabIndex>Removed then
      Dec(TAFileManagerDocument(FDocuments[I]).TabIndex);
  for I:=0 to FConsoles.Count-1 do
    if TAFileManagerConsoleDocument(FConsoles[I]).TabIndex>Removed then
      Dec(TAFileManagerConsoleDocument(FConsoles[I]).TabIndex);

  { Close the application surface, not the session object directly. The
    surface owns the live Console visual and detaches it from its host before
    disposal; CloseSurface closes the session automatically when this is the
    last surface. This prevents a page/host retaining a freed child visual. }
  if FApplicationFrames<>nil then
  begin
    if ADoc.FrameSurface<>nil then
      FApplicationFrames.CloseSurface(ADoc.FrameSurface);
    if ADoc.EmbeddedFrame<>nil then FApplicationFrames.UnregisterHost(ADoc.EmbeddedFrame);
    if ADoc.FloatingFrame<>nil then FApplicationFrames.UnregisterHost(ADoc.FloatingFrame);
  end;
  ADoc.FrameSurface:=nil;
  ADoc.FrameSession:=nil;
  ADoc.Console:=nil;
  { Floating toolbar/operation controls are owned by the floating AROSA
    window-frame visual tree and are released with it. }
  ADoc.FloatingToolbarTabs:=nil;
  ADoc.FloatingOperationTabs:=nil;
  FreeAndNil(ADoc.FloatingFrame);

  FDocumentTabs.RemovePage(Removed);
  ADoc.Page:=nil;
  ADoc.EmbeddedFrame:=nil; { owned/freed by the removed page subtree }
  ADoc.Session.Free;
  ADoc.Session:=nil;
  ADoc.Free;

  NewActive:=ActiveConsoleDocument;
  if NewActive<>nil then
  begin
    FConsole:=NewActive.Console;
    FShellSession:=NewActive.Session;
  end;
  SetStatus('Console closed');
end;

procedure TAFileManagerController.ConsoleCloseClick(ASender: TArosaControl);
begin
  CloseConsoleDocument(ConsoleDocumentForControl(ASender));
end;

procedure TAFileManagerController.ConsoleContextCommand(ASender: TArosaControl;
  const ACommand: string);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleDocumentForControl(ASender);
  if SameText(ACommand,'Console.New') then
    OpenConsoleFromSource(D)
  else if SameText(ACommand,'Console.PopOut') then
    PopOutConsoleDocument(D)
  else if SameText(ACommand,'Console.Embed') then
    EmbedConsoleDocument(D)
  else if SameText(ACommand,'Console.Close') then
    CloseConsoleDocument(D);
end;

function TAFileManagerController.ConsoleContextCommandEnabled(
  ASender: TArosaControl; const ACommand: string): Boolean;
var D: TAFileManagerConsoleDocument; H: IArosaApplicationFrameHost;
begin
  Result:=False;
  D:=ConsoleDocumentForControl(ASender);
  if (D=nil) or (D.FrameSurface=nil) then Exit;
  H:=D.FrameSurface.Host;
  if SameText(ACommand,'Console.PopOut') then
    Result:=(D.FloatingFrame<>nil) and (H<>nil) and
      (H.HostMode=aahEmbedded) and
      (aascDetach in D.FrameSurface.Capabilities)
  else if SameText(ACommand,'Console.Embed') then
    Result:=(D.EmbeddedFrame<>nil) and (H<>nil) and
      (H.HostMode=aahFloating) and
      (aascEmbed in D.FrameSurface.Capabilities);
end;

function TAFileManagerController.ConsoleDocumentForSurface(
  ASurface: TArosaApplicationSurface): TAFileManagerConsoleDocument;
var I: Integer; D: TAFileManagerConsoleDocument;
begin
  Result:=nil;
  if (ASurface=nil) or (FConsoles=nil) then Exit;
  for I:=0 to FConsoles.Count-1 do
  begin
    D:=TAFileManagerConsoleDocument(FConsoles[I]);
    if D.FrameSurface=ASurface then Exit(D);
  end;
end;

procedure TAFileManagerController.EnsureFloatingConsoleChrome(
  ADoc: TAFileManagerConsoleDocument);
var ToolbarDescriptor, OperationsDescriptor: TStringList;
    FloatingWindow: TArosaWindowFrame;
    FrameTheme, SavedTheme: TArosaTheme;

  procedure StyleFloatingTabs(ATabs: TArosaTabControl);
  begin
    if (ATabs=nil) or (FrameTheme=nil) then Exit;
    ATabs.Font:=FFonts.Acquire(FrameTheme.FontFor(afrUI));
    ATabs.HeaderHeight:=ArosaCoord(20);
    ATabs.ActiveBackground:=FrameTheme.ColourFor(AROSA_ROLE_TAB_ACTIVE);
    ATabs.InactiveBackground:=FrameTheme.ColourFor(AROSA_ROLE_TAB_INACTIVE);
    ATabs.ActiveText:=FrameTheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT);
    ATabs.InactiveText:=FrameTheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT);
    ATabs.BorderColour:=FrameTheme.ColourFor(AROSA_ROLE_BORDER);
    ATabs.CornerRadius:=FrameTheme.Metrics.BorderRadius;
    ATabs.InvalidatePaint;
  end;
begin
  if (ADoc=nil) or (ADoc.FloatingFrame=nil) then Exit;
  FloatingWindow:=ADoc.FloatingFrame.WindowFrame;
  if FloatingWindow=nil then Exit;

  { The controller itself is workspace-scoped.  Its live FTheme is therefore
    the authoritative presentation object for this workspace, including any
    configuration/font/colour-layer changes already applied to the visible
    AFileManager window.  Do not reconstruct the theme from Workspace.ThemeId:
    that selects a stock Light/Dark object and loses the exact live workspace
    presentation, which produced mixed Light/Dark floating Console chrome. }
  if ADoc.FloatingTheme=nil then
  begin
    { The visible workspace frame is the presentation authority.  A controller
      may carry a different stock/default theme object while its retained
      window has already been switched to the workspace-specific live theme.
      Capture the actual frame theme first so detached application chrome
      cannot inherit a stale/default Dark theme from controller state. }
    if (FWindowFrame<>nil) and (FWindowFrame.Theme<>nil) then
      ADoc.FloatingTheme:=FWindowFrame.Theme
    else
      ADoc.FloatingTheme:=FTheme;
    if (ADoc.FloatingTheme=nil) and (ADoc.Console<>nil) then
      ADoc.FloatingTheme:=ADoc.Console.Theme;
  end;
  FrameTheme:=ADoc.FloatingTheme;
  { A floating application frame uses exactly the same AROSA window-gadget
    icon policy as the primary AFileManager frame.  The retained frame still
    owns the chrome; we only resolve the standard semantic icon resources. }
  ApplyWindowIconsTo(FloatingWindow);

  { A popped-out Console is a complete AROSA application surface.  Its
    contextual toolbar and Operations surface therefore travel with it rather
    than being left behind in AFileManager.  They are independent command
    surfaces built from the same Console environment descriptors, so the main
    AFileManager window remains free to switch back to the Files environment. }
  { Build floating command surfaces under the captured workspace theme.
    BuildCommandTabs and its helper constructors intentionally use FTheme for
    normal AFileManager surfaces; without this guard a detached Light-workspace
    Console could receive Dark/default group boxes and buttons. }
  SavedTheme:=FTheme;
  FTheme:=FrameTheme;
  try
    if ADoc.FloatingToolbarTabs=nil then
    begin
      ToolbarDescriptor:=EnvironmentSection('Console','Toolbar','Toolbar');
      try
        ADoc.FloatingToolbarTabs:=TArosaTabControl.Create;
        StyleCommandTabs(ADoc.FloatingToolbarTabs);
        ADoc.FloatingToolbarTabs.SetConstraintHeight(asmFixed,ArosaCoord(72));
        BuildCommandTabs(ADoc.FloatingToolbarTabs,ToolbarDescriptor,'NAVIGATION',False);
      finally
        ToolbarDescriptor.Free;
      end;
      FloatingWindow.ToolbarContent:=ADoc.FloatingToolbarTabs;
    end;

    if ADoc.FloatingOperationTabs=nil then
    begin
      OperationsDescriptor:=EnvironmentSection('Console','Operations','Operations');
      try
        ADoc.FloatingOperationTabs:=TArosaTabControl.Create;
        StyleCommandTabs(ADoc.FloatingOperationTabs);
        ADoc.FloatingOperationTabs.SetConstraintHeight(asmFixed,ArosaCoord(190));
        BuildCommandTabs(ADoc.FloatingOperationTabs,OperationsDescriptor,'OPERATIONS',False);
      finally
        OperationsDescriptor.Free;
      end;
      FloatingWindow.FilePanelContent:=ADoc.FloatingOperationTabs;
    end;
  finally
    FTheme:=SavedTheme;
  end;

  if (FWindowFrame<>nil) and
     (FloatingWindow.ToolbarVisible<>FWindowFrame.ToolbarVisible) then
    FloatingWindow.ToggleToolbar;
  if (FWindowFrame<>nil) and
     (FloatingWindow.FilePanelVisible<>FWindowFrame.FilePanelVisible) then
    FloatingWindow.ToggleFilePanel;

  { Apply one immutable-for-this-detach workspace theme to the complete
    floating composition.  TArosaTabControl keeps explicit active/inactive
    colours in addition to its normal Theme reference, so retheming only the
    control tree is insufficient; restyle those tab headers explicitly too. }
  ApplyThemeToTree(FloatingWindow,FrameTheme);
  { ToolbarContent/FilePanelContent are hosted by the application frame as
    auxiliary surfaces and are not guaranteed to be descendants of the main
    content visual in every frame implementation.  Theme them explicitly as
    complete retained subtrees so group boxes/buttons cannot keep the theme
    they were constructed with. }
  if ADoc.FloatingToolbarTabs<>nil then
    ApplyThemeToTree(ADoc.FloatingToolbarTabs,FrameTheme);
  if ADoc.FloatingOperationTabs<>nil then
    ApplyThemeToTree(ADoc.FloatingOperationTabs,FrameTheme);
  StyleFloatingTabs(ADoc.FloatingToolbarTabs);
  StyleFloatingTabs(ADoc.FloatingOperationTabs);
  if ADoc.Console<>nil then ADoc.Console.SetTheme(FrameTheme,FFonts);
  FloatingWindow.InvalidateLayout;
  FloatingWindow.InvalidatePaint;

  UpdateConsoleToolState;
end;

procedure TAFileManagerController.PopOutConsoleDocument(
  ADoc: TAFileManagerConsoleDocument);
var H: IArosaApplicationFrameHost;
begin
  if (ADoc=nil) or (ADoc.FrameSurface=nil) or
     (ADoc.FloatingFrame=nil) or (FApplicationFrames=nil) then Exit;
  { Capture the exact live workspace theme before the surface is detached.
    Detach/activation may change focus and environment state; the floating
    frame must remain bound to the theme that is visibly active in this
    workspace at the moment of Pop out. }
  ADoc.FloatingTheme:=FTheme;
  H:=ADoc.FloatingFrame;
  if FApplicationFrames.MoveSurface(ADoc.FrameSurface,H) then
  begin
    EnsureFloatingConsoleChrome(ADoc);
    ADoc.FloatingFrame.Activate;
    UpdateConsoleCaption(ADoc);
    SetStatus('Console popped out');
  end;
end;

procedure TAFileManagerController.EmbedConsoleDocument(
  ADoc: TAFileManagerConsoleDocument);
var H: IArosaApplicationFrameHost;
begin
  if (ADoc=nil) or (ADoc.FrameSurface=nil) or
     (ADoc.EmbeddedFrame=nil) or (FApplicationFrames=nil) then Exit;
  H:=ADoc.EmbeddedFrame;
  if FApplicationFrames.MoveSurface(ADoc.FrameSurface,H) then
  begin
    UpdateConsoleCaption(ADoc);
    if FDocumentTabs<>nil then FDocumentTabs.SelectedIndex:=ADoc.TabIndex;
    { Rebuild the embedded Console command surfaces so their state pointers
      once again refer to AFileManager's toolbar/Operations controls rather
      than the independent floating copies. }
    FActiveEnvironment:='';
    ActivateEnvironment('Console');
    UpdateConsoleToolState;
    if (FNativeHost<>nil) and (ADoc.Console<>nil) then
      FNativeHost.FocusControl(ADoc.Console);
    { Next detach must capture the then-current owning workspace theme. }
    ADoc.FloatingTheme:=nil;
    SetStatus('Console embedded');
  end;
end;

procedure TAFileManagerController.ConsoleFrameActivated(ASender: TObject;
  ASurface: TArosaApplicationSurface);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleDocumentForSurface(ASurface);
  if D=nil then Exit;
  { Floating command surfaces use the same controller command handlers as an
    embedded Console.  Make this Console the command target whenever its AROSA
    frame becomes active, even if the user had meanwhile selected Files in the
    main AFileManager window. }
  if (FDocumentTabs<>nil) and (FDocumentTabs.SelectedIndex<>D.TabIndex) then
    FDocumentTabs.SelectedIndex:=D.TabIndex;
  FConsole:=D.Console;
  FShellSession:=D.Session;
  ActivateEnvironment('Console');
  UpdateConsoleToolState;
  if ASender=nil then ;
end;

procedure TAFileManagerController.ConsoleFrameCloseRequested(ASender: TObject;
  ASurface: TArosaApplicationSurface);
var D: TAFileManagerConsoleDocument;
begin
  D:=ConsoleDocumentForSurface(ASurface);
  if D<>nil then CloseConsoleDocument(D);
  if ASender=nil then ;
end;

function TAFileManagerController.DefaultConsoleLocation: string;
begin
  {$IFDEF AROS}
  Result:='SYS:';
  if (FLocations<>nil) and FLocations.IsDirectory(Result) then Exit;
  {$ENDIF}
  Result:=GetCurrentDir;
  if (FLocations<>nil) and not FLocations.IsDirectory(Result) then
  begin
    if not IsProviderLocation(ViewCurrent(FActiveView)) then
      Result:=ViewCurrent(FActiveView);
  end;
end;

function TAFileManagerController.ConsoleLocationLabel(
  const ALocation: string): string;
var S, Scheme, Host: string; P, Slash: Integer;
begin
  S:=Trim(ALocation);
  if S='' then Exit('local');
  P:=Pos('://',S);
  if P>0 then
  begin
    Scheme:=Copy(S,1,P-1);
    Host:=Copy(S,P+3,MaxInt);
    Slash:=Pos('/',Host);
    if Slash>0 then Host:=Copy(Host,1,Slash-1);
    if Host<>'' then Result:=Scheme+'@'+Host
    else Result:=Scheme;
    Exit;
  end;
  P:=Pos(':',S);
  if P>1 then
  begin
    Result:=Copy(S,1,P-1);
    Exit;
  end;
  Result:='local';
end;

procedure TAFileManagerController.UpdateConsoleCaption(
  ADoc: TAFileManagerConsoleDocument);
var C: string;
begin
  if (ADoc=nil) or (ADoc.Page=nil) or (ADoc.Session=nil) then Exit;
  C:=LocalText('afilemanager_tab_console','Console')+' '+IntToStr(ADoc.Id)+
    ' @ '+ConsoleLocationLabel(ADoc.Session.Location);
  if (ADoc.FrameSurface<>nil) and (ADoc.FrameSurface.Host<>nil) and
     (ADoc.FrameSurface.Host.HostMode=aahFloating) then
    C:=C+' [pop out]';
  ADoc.Page.Caption:=C;
  if ADoc.FrameSurface<>nil then ADoc.FrameSurface.Title:=C;
  if (ADoc.FloatingFrame<>nil) and (ADoc.FrameSurface<>nil) and
     (ADoc.FrameSurface.Host<>nil) and
     (ADoc.FrameSurface.Host.HostMode=aahFloating) then
    ADoc.FloatingFrame.RefreshTitle;
end;

function TAFileManagerController.HandleConsoleTargetCommand(
  ADoc: TAFileManagerConsoleDocument; const ALine: string): Boolean;
var S, Target: string;
begin
  Result:=False;
  if (ADoc=nil) or (ADoc.Session=nil) then Exit;
  S:=Trim(ALine);
  if not SameText(Copy(S,1,7),'console') then Exit;
  if (Length(S)>7) and not (S[8] in [' ',#9]) then Exit;
  Result:=True;

  S:=Trim(Copy(S,8,MaxInt));
  if S='' then
  begin
    OpenConsoleAt(DefaultConsoleLocation);
    Exit;
  end;

  if S[1]<>'@' then
  begin
    if ADoc.Console<>nil then
      ADoc.Console.WriteLine('Usage: console @<location> | console @here | console @local');
    Exit;
  end;

  Target:=Trim(Copy(S,2,MaxInt));
  if SameText(Target,'here') then
    Target:=ADoc.Session.Location
  else if SameText(Target,'local') then
    Target:=DefaultConsoleLocation;

  if Target='' then
  begin
    if ADoc.Console<>nil then
      ADoc.Console.WriteLine('Console target is empty');
    Exit;
  end;

  { A location can be a local DOS path (SYS:, RAM:, ...) or a provider URI
    such as atransfer://host/path.  Each console owns its own ShellSession and
    therefore its own machine/location independently of every other console. }
  if (FLocations<>nil) and FLocations.IsDirectory(Target) then
    OpenConsoleAt(Target)
  else if ADoc.Console<>nil then
    ADoc.Console.WriteLine('Console target is not available: '+Target);
end;

procedure TAFileManagerController.OpenConsoleAt(const ALocation: string);
var D: TAFileManagerConsoleDocument;
begin
  D:=CreateConsoleDocument(ALocation);
  if D=nil then
  begin
    SetStatus('Console could not be created');
    Exit;
  end;
  if D.Session.Location=ALocation then
    SetStatus(LocalText('afilemanager_console_ready','Console: ')+D.Session.Location);
end;

procedure TAFileManagerController.OpenConsoleFromSource(
  ASource: TAFileManagerConsoleDocument);
var
  H: IArosaApplicationFrameHost;
  D: TAFileManagerConsoleDocument;
  Location: string;
begin
  H:=nil;
  if (ASource<>nil) and (ASource.FrameSurface<>nil) then
    H:=ASource.FrameSurface.Host;

  { Embedded commands keep the established AFileManager behaviour. }
  if (H=nil) or (H.HostMode<>aahFloating) then
  begin
    OpenConsoleAt(DefaultConsoleLocation);
    Exit;
  end;

  { A command issued from a floating Console belongs to the floating
    application context.  Create the sibling at the same live location and
    immediately move it to its own floating AROSA frame before the event loop
    gets a chance to present it as a new parent-window Console tab. }
  Location:=DefaultConsoleLocation;
  if (ASource.Session<>nil) and (Trim(ASource.Session.Location)<>'') then
    Location:=ASource.Session.Location;
  D:=CreateConsoleDocument(Location);
  if D=nil then
  begin
    SetStatus('Console could not be created');
    Exit;
  end;
  Diagnostic('CONSOLE floating sibling created source-id='+
    IntToStr(ASource.Id)+' new-id='+IntToStr(D.Id));
  PopOutConsoleDocument(D);
end;

{ context menu "Open Console Here": the clicked folder, else the pane }
procedure TAFileManagerController.OpenConsoleHereClick(ASender: TArosaControl);
var L: TArosaFilteredListView; P: string;
begin
  if ASender=FRightList then SetActiveView(1) else if ASender=FLeftList then SetActiveView(0);
  P:=ViewCurrent(FActiveView);
  L:=ViewList(FActiveView);
  if (L<>nil) and (L.SelectedCount=1) and (L.SelectedIndex>=0) and
     (FLocations<>nil) and FLocations.IsDirectory(SelectedPath(FActiveView,L.SelectedIndex)) then
    P:=SelectedPath(FActiveView,L.SelectedIndex);
  OpenConsoleAt(P);
end;

{ every line that is not an AFileManager command id }
procedure TAFileManagerController.EnsureConsoleExecutionIdle;
begin
  if FConsoleExecutionIdleAttached then Exit;
  if (FNativeHost=nil) or (FNativeHost.Application=nil) or
     (FNativeHost.Application.Loop=nil) then Exit;
  FNativeHost.Application.Loop.AddIdleHandler(@ConsoleExecutionIdle);
  FConsoleExecutionIdleAttached:=True;
end;

procedure TAFileManagerController.FinishConsoleExecution(
  ADoc: TAFileManagerConsoleDocument; const AOutput, AError: string;
  AExitCode: LongInt);
var Delta: string;
begin
  if ADoc=nil then Exit;
  if (ADoc.Console<>nil) and (Length(AOutput)>ADoc.ProcessOutputLength) then
  begin
    Delta:=Copy(AOutput,ADoc.ProcessOutputLength+1,MaxInt);
    ADoc.Console.RecordRawTranscriptLine(Delta);
    ADoc.Console.WriteLine(Delta);
  end;
  if (ADoc.Console<>nil) and (Length(AError)>ADoc.ProcessErrorLength) then
  begin
    Delta:=Copy(AError,ADoc.ProcessErrorLength+1,MaxInt);
    ADoc.Console.RecordRawTranscriptLine(Delta);
    ADoc.Console.WriteLine(Delta);
  end;
  ADoc.ProcessOutputLength:=Length(AOutput);
  ADoc.ProcessErrorLength:=Length(AError);
  if ADoc.Console<>nil then
  begin
    ADoc.Console.Prompt:=ADoc.Session.Prompt;
    ADoc.Console.FocusInput;
  end;
  UpdateConsoleCaption(ADoc);
  if AExitCode=0 then
    SetStatus('Console: '+ADoc.Session.Location)
  else
    SetStatus('Console command failed (return code '+IntToStr(AExitCode)+')');
end;

procedure TAFileManagerController.ConsoleExecutionIdle(
  var AMoreWorkPending: Boolean);
var
  I: Integer;
  D: TAFileManagerConsoleDocument;
  Done, PollOk, AnyRunning: Boolean;
  OutText, ErrText, Delta: string;
  ExitCode: LongInt;
  Elapsed: QWord;
begin
  AnyRunning:=False;
  if (FConsoles=nil) or (FShellService=nil) then
  begin
    AMoreWorkPending:=False;
    Exit;
  end;

  for I:=0 to FConsoles.Count-1 do
  begin
    D:=TAFileManagerConsoleDocument(FConsoles[I]);
    if (D=nil) or (D.ProcessId=0) then Continue;
    AnyRunning:=True;

    { 0.17.12.x: poll FIRST.  The timeout used to be checked before the
      poll, so a command whose completion became visible during a long gap
      between idle passes (a busy CPU0, a blocked loop) was reported as a
      console timeout and its result discarded, although it had finished. }
    OutText:=''; ErrText:=''; ExitCode:=-1; Done:=False;
    PollOk:=FShellService.PollShellLine(D.ProcessId,Done,OutText,ErrText,ExitCode);

    Elapsed:=GetTickCount64-D.ProcessStartedAt;
    if PollOk and (not Done) and (D.ProcessTimeoutMs>0) and
       (Elapsed>=QWord(D.ProcessTimeoutMs)) then
    begin
      FShellService.CancelShellLine(D.ProcessId);
      FShellService.ReleaseShellLine(D.ProcessId);
      D.ProcessId:=0;
      if ErrText<>'' then ErrText:=ErrText+LineEnding;
      ErrText:=ErrText+'Stopped after '+IntToStr(D.ProcessTimeoutMs div 1000)+
        ' s (console timeout).';
      FinishConsoleExecution(D,OutText,ErrText,-1);
      Continue;
    end;

    { Stream only bytes that were not already shown. Poll itself never waits. }
    if (D.Console<>nil) and (Length(OutText)>D.ProcessOutputLength) then
    begin
      Delta:=Copy(OutText,D.ProcessOutputLength+1,MaxInt);
      D.ProcessOutputLength:=Length(OutText);
      D.Console.RecordRawTranscriptLine(Delta);
      D.Console.WriteLine(Delta);
    end;
    if (D.Console<>nil) and (Length(ErrText)>D.ProcessErrorLength) then
    begin
      Delta:=Copy(ErrText,D.ProcessErrorLength+1,MaxInt);
      D.ProcessErrorLength:=Length(ErrText);
      D.Console.RecordRawTranscriptLine(Delta);
      D.Console.WriteLine(Delta);
    end;

    if Done or not PollOk then
    begin
      FShellService.ReleaseShellLine(D.ProcessId);
      D.ProcessId:=0;
      FinishConsoleExecution(D,OutText,ErrText,ExitCode);
    end;
  end;

  AnyRunning:=False;
  for I:=0 to FConsoles.Count-1 do
    if TAFileManagerConsoleDocument(FConsoles[I]).ProcessId<>0 then
    begin AnyRunning:=True; Break; end;
  if (not AnyRunning) and FConsoleExecutionIdleAttached and
     (FNativeHost<>nil) and (FNativeHost.Application<>nil) and
     (FNativeHost.Application.Loop<>nil) then
  begin
    FNativeHost.Application.Loop.RemoveIdleHandler(@ConsoleExecutionIdle);
    FConsoleExecutionIdleAttached:=False;
  end;
  { Waiting for a child is not CPU work. The normal event-loop wait wakes the
    idle handler again without starving menus, pointer input or painting. }
  AMoreWorkPending:=False;
end;

{ every line that is not an AFileManager command id }
function TAFileManagerController.ConsoleSubmit(ASender: TArosaControl;
  const ALine: string): string;
var
  Output: TStringList;
  I, P: Integer;
  R: TArosaShellResult;
  Msg, Verb, LowerVerb, StartError: string;
  D: TAFileManagerConsoleDocument;
  ProcessId: PtrUInt;
  BuiltInOrProvider: Boolean;
begin
  Result:='';
  D:=ConsoleDocumentForControl(ASender);
  if (D=nil) or (D.Session=nil) or (D.Console=nil) then
  begin
    SetStatus('Console session is not available');
    Exit;
  end;
  FConsole:=D.Console; FShellSession:=D.Session;

  if D.ProcessId<>0 then
  begin
    Result:='A command is already running in this console.';
    Exit;
  end;

  D.Console.RecordRawTranscriptLine(D.Console.Prompt+ALine);
  if HandleConsoleTargetCommand(D,ALine) then
  begin
    D.Console.FocusInput;
    Exit('');
  end;

  P:=1;
  while (P<=Length(ALine)) and not (ALine[P] in [' ',#9]) do Inc(P);
  Verb:=Copy(ALine,1,P-1);
  LowerVerb:=LowerCase(Verb);
  BuiltInOrProvider:=(LowerVerb='cd') or (LowerVerb='pwd') or
    (LowerVerb='clear') or (LowerVerb='cls') or (LowerVerb='help') or
    (LowerVerb='?') or
    ((Pos('://',LowerCase(D.Session.Location))>0) and
     (Pos('arosa://',LowerCase(D.Session.Location))<>1));

  { Built-ins change ShellSession state and are intentionally immediate. Remote
    provider commands keep their existing service path for now. Native external
    commands are started asynchronously and polled from the application loop. }
  if not BuiltInOrProvider then
  begin
    ProcessId:=0; StartError:='';
    if (FShellService=nil) or not FShellService.BeginShellLine(ALine,
       D.Session.ExecutionWorkingDirectory,ProcessId,StartError) then
    begin
      if StartError='' then StartError:='Native process service is not available.';
      Result:='Cannot run the command: '+StartError;
      SetStatus(Result);
      Exit;
    end;
    D.ProcessId:=ProcessId;
    D.ProcessOutputLength:=0;
    D.ProcessErrorLength:=0;
    D.ProcessStartedAt:=GetTickCount64;
    D.ProcessTimeoutMs:=D.Session.TimeoutMs;
    D.ProcessLine:=ALine;
    { During TArosaCommandConsole.Submit this setter only changes the prompt
      text; Submit appends it after this callback returns. }
    D.Console.Prompt:='[running] ';
    EnsureConsoleExecutionIdle;
    SetStatus('Console command running: '+Verb);
    Exit('');
  end;

  Output:=TStringList.Create;
  try
    try
      R:=D.Session.Execute(ALine,Output);
      if R=asrClear then D.Console.ClearOutput
      else
      begin
        for I:=0 to Output.Count-1 do D.Console.RecordRawTranscriptLine(Output[I]);
        FormatConsoleColumns(Output,D.Console);
        for I:=0 to Output.Count-1 do D.Console.WriteLine(Output[I]);
      end;
      D.Console.Prompt:=D.Session.Prompt;
      UpdateConsoleCaption(D);
      D.Console.InvalidatePaint;
      case R of
        asrFailed:
          begin
            if Output.Count>0 then Msg:=Output[Output.Count-1] else Msg:='command failed';
            SetStatus('Console command failed: '+Msg);
          end;
        asrNotAvailable:
          begin
            if Output.Count>0 then Msg:=Output[Output.Count-1] else Msg:='command unavailable';
            SetStatus('Console command unavailable: '+Msg);
          end;
      else
        if R<>asrClear then SetStatus('Console: '+D.Session.Location);
      end;
    except
      on E: Exception do
      begin
        Msg:='Console error: '+E.Message;
        D.Console.WriteLine('ERROR: '+E.Message);
        SetStatus(Msg);
      end;
    end;
  finally Output.Free; end;
end;

procedure TAFileManagerController.ARexxClick(ASender: TArosaControl);
var Ran: Integer;
begin
  { Demonstrate the ARexx bridge by running a tiny canonical script through the
    same command handlers the UI uses. A native ARexx host feeds real scripts
    into FARexxService the same way. }
  if FARexxService <> nil then
  begin
    Ran := FARexxService.RunScript('REFRESH' + LineEnding);
    SetStatus('ARexx port ' + FARexxService.PortName + ' ready (' +
      IntToStr(Ran) + ' verbs dispatched)');
  end
  else
    SetStatus('ARexx operations selected');
end;

procedure TAFileManagerController.MacrosClick(ASender: TArosaControl);
var Played: Integer;
begin
  { If a macro is being recorded, finish it; otherwise replay the last stored
    macro through the canonical command service. }
  if FMacroService = nil then begin SetStatus('Macros selected'); Exit; end;
  if FMacroService.IsRecording then
  begin
    FMacroService.FinishRecording;
    SetStatus('Macro recording stored');
  end
  else if FMacroService.Count > 0 then
  begin
    Played := FMacroService.Play(FMacroService.FindMacro('default'), FCommandService);
    SetStatus('Macro replayed (' + IntToStr(Played) + ' steps)');
  end
  else
  begin
    FMacroService.BeginRecording('default');
    SetStatus('Macro recording started');
  end;
end;

procedure TAFileManagerController.ShowMetadataClick(ASender: TArosaControl);
begin
  SetPanels(FPreviewVisible, not FMetadataVisible, 1);
end;

function TAFileManagerController.CanRunCommandId(
  const ACommandId: string): Boolean;
begin
  Result := Assigned(HandlerForCommand(LowerCase(ACommandId)));
end;

function TAFileManagerController.RunCommandId(
  const ACommandId: string): Boolean;
var H: TArosaClickEvent;
begin
  Result := False;
  H := HandlerForCommand(LowerCase(ACommandId));
  if not Assigned(H) then Exit;
  { Record into an active macro before dispatch, so recording captures the
    canonical command stream. }
  if (FMacroService <> nil) and FMacroService.IsRecording then
    FMacroService.RecordCommand(LowerCase(ACommandId));
  H(nil);
  Result := True;
end;

procedure TAFileManagerController.ToggleToolbarClick(ASender: TArosaControl);
begin
  if FToolbarTabs=nil then begin SetStatus('Toolbar is not available'); Exit; end;
  FWindowFrame.ToggleToolbar;
  if FWindowFrame.ToolbarVisible then SetStatus('Toolbar shown') else SetStatus('Toolbar hidden');
  BuildRootMenu;
end;

procedure TAFileManagerController.ToggleOperationsClick(ASender: TArosaControl);
begin
  if FOperationTabs=nil then begin SetStatus('Operations are not available'); Exit; end;
  FWindowFrame.ToggleFilePanel;
  if FWindowFrame.FilePanelVisible then SetStatus('Operations shown') else SetStatus('Operations hidden');
  BuildRootMenu;
end;

{ ---- 0.7.13.0.0 file-manager surfaces -------------------------------------
  With split view on, the secondary view hosts any number of file managers.
  The visible surface owns the live list and fields; switching stores them
  into its TAFMSurface and loads the target's (location, view mode, its own
  back/forward history, filter, search, selection).  Switching never records
  navigation history. }

procedure TAFileManagerController.SaveActiveSurface;
var S: TAFMSurface;
begin
  if (FSurfaces=nil) or (FActiveSurface<0) or (FActiveSurface>=FSurfaces.Count) then Exit;
  S:=TAFMSurface(FSurfaces[FActiveSurface]);
  S.Location:=FRightCurrent;
  S.ViewMode:=FRightViewMode;
  S.History:=FRightNavigationHistory;
  if FRightFilter<>nil then S.Filter:=FRightFilter.Text;
  if FRightSearch<>nil then S.Search:=FRightSearch.Text;
  if FRightList<>nil then S.Selected:=FRightList.SelectedIndex;
end;

procedure TAFileManagerController.ShowSurface(AIndex: Integer);
var S: TAFMSurface; Loc: string;
begin
  if (FSurfaces=nil) or (AIndex<0) or (AIndex>=FSurfaces.Count) then Exit;
  S:=TAFMSurface(FSurfaces[AIndex]);
  FActiveSurface:=AIndex;
  FRightNavigationHistory:=S.History;
  FRightViewMode:=S.ViewMode;
  if FRightFilter<>nil then FRightFilter.Text:=S.Filter;
  if FRightSearch<>nil then FRightSearch.Text:=S.Search;
  ApplyFileViewGeometry(1);
  Loc:=S.Location;
  if Trim(Loc)='' then Loc:=FLeftCurrent;
  FRightCurrent:='';
  FRestoringHistory:=True;
  try
    NavigateView(1,Loc);
  finally
    FRestoringHistory:=False;
  end;
  if FRightList<>nil then
  begin
    FRightList.SetFilter(S.Filter);
    if (S.Selected>=0) and (S.Selected<FRightList.ItemCount) then FRightList.SelectItem(S.Selected);
  end;
  SetActiveView(1);
  RebuildSurfaceBar;
  UpdateViewToolbarState;
  BuildRootMenu;
  SetStatus(SysUtils.Format(LocalText('afilemanager_status_file_manager','File manager %d of %d: %s'),
    [AIndex+1,FSurfaces.Count,FRightCurrent]));
end;

procedure TAFileManagerController.RebuildSurfaceBar;
var I: Integer; B: TArosaButton; S: TAFMSurface; Caption, Loc: string;
begin
  if (FSurfaceBar=nil) or (FSurfaces=nil) then Exit;
  FSurfaceBar.ClearVisuals;
  for I:=0 to FSurfaces.Count-1 do
  begin
    S:=TAFMSurface(FSurfaces[I]);
    if I=FActiveSurface then Loc:=FRightCurrent else Loc:=S.Location;
    Caption:=ExtractFileName(ExcludeTrailingPathDelimiter(Loc));
    if Caption='' then Caption:=Loc;
    if Caption='' then Caption:=IntToStr(I+1);
    if Length(Caption)>18 then Caption:=Copy(Caption,1,17)+'~';
    B:=NewButton(FSurfaceBar,Caption,Loc,@SurfaceTabClick,12+7*Length(Caption));
    B.Tag:=I;
    B.Toggled:=I=FActiveSurface;
  end;
  B:=NewButton(FSurfaceBar,'+',LocalText('afilemanager_hint_new_file_manager',
    'Open another file manager in the second view (Ctrl+T)'),@NewFileManagerClick,26);
  ApplyButtonIcon(B,'WindowIcons','Surface.New',26);
  if FSurfaces.Count>1 then
  begin
    B:=NewButton(FSurfaceBar,'x',LocalText('afilemanager_hint_close_file_manager',
      'Close the file manager shown in the second view (Ctrl+W)'),@CloseFileManagerClick,26);
    ApplyButtonIcon(B,'WindowIcons','Surface.Close',26);
  end;
  FSurfaceBar.InvalidateLayout;
  FSurfaceBar.InvalidatePaint;
end;

procedure TAFileManagerController.SurfaceTabClick(ASender: TArosaControl);
begin
  if (ASender=nil) or (FSurfaces=nil) then Exit;
  if ASender.Tag=FActiveSurface then begin SetActiveView(1); Exit; end;
  SaveActiveSurface;
  ShowSurface(ASender.Tag);
end;

procedure TAFileManagerController.NewFileManagerClick(ASender: TArosaControl);
var S: TAFMSurface;
begin
  if (FSurfaces=nil) or (FRightColumn=nil) then
  begin
    SetStatus(LocalText('afilemanager_surface_unavailable','Another file manager needs split view.'));
    Exit;
  end;
  if (FWindowFrame<>nil) and not FWindowFrame.SplitView then ToggleSplitClick(nil);
  SaveActiveSurface;
  S:=TAFMSurface.Create;
  if Trim(FRightCurrent)<>'' then S.Location:=FRightCurrent else S.Location:=FLeftCurrent;
  S.ViewMode:=FRightViewMode;
  Inc(FSurfaceCounter);
  S.History:=FHistoryService.CreateChain('navigation.surface'+IntToStr(FSurfaceCounter),100);
  S.Selected:=-1;
  FSurfaces.Add(S);
  ShowSurface(FSurfaces.Count-1);
  { the first entry of its own history }
  if S.History<>nil then S.History.RecordEntry(FRightCurrent);
  Diagnostic('SURFACE new count='+IntToStr(FSurfaces.Count)+' location='+FRightCurrent);
end;

procedure TAFileManagerController.CloseFileManagerClick(ASender: TArosaControl);
var Closing: Integer;
begin
  if (FSurfaces=nil) or (FSurfaces.Count<=1) then
  begin
    SetStatus(LocalText('afilemanager_surface_last','The last file manager stays open (hide split view to hide it).'));
    Exit;
  end;
  Closing:=FActiveSurface;
  TAFMSurface(FSurfaces[Closing]).Free;
  FSurfaces.Delete(Closing);
  if Closing>=FSurfaces.Count then Closing:=FSurfaces.Count-1;
  FActiveSurface:=-1;      { nothing to save: the closed surface is gone }
  ShowSurface(Closing);
  Diagnostic('SURFACE closed count='+IntToStr(FSurfaces.Count));
end;

procedure TAFileManagerController.ToggleSplitClick(ASender: TArosaControl);
begin
  if FRightColumn=nil then begin SetStatus('Split view is not available'); Exit; end;
  FWindowFrame.ToggleSplitView;
  if FWindowFrame.SplitView then
  begin
    { A newly opened secondary pane starts from the primary pane's current
      location. Never expose a blank second browser merely because it was
      hidden when the application started. }
    if (Trim(FRightCurrent)='') or (FRightList=nil) or (FRightList.RowCount=0) then
    begin
      FRightCurrent:='';
      NavigateView(1,FLeftCurrent);
      SetActiveView(0);
    end;
    SetStatus('Split view shown');
  end
  else SetStatus('Split view hidden');
  UpdateViewToolbarState;
  BuildRootMenu;
end;

procedure TAFileManagerController.TogglePreviewClick(ASender: TArosaControl);
begin
  SetPanels(not FPreviewVisible, FMetadataVisible, 0);
end;

{ Context-menu "Metadata" for a resource: make the metadata page visible
  and select it, leaving the preview page as it is. }
procedure TAFileManagerController.ShowResourceMetadataClick(ASender: TArosaControl);
begin
  SetPanels(FPreviewVisible, True, 1);
end;

{ 0.6.1.3: Preview and Metadata are independent tab pages of one panel.
  ASelectTab (0 preview, 1 metadata) is selected when that page is being
  shown by this call; hiding a page leaves the other page selected. }
procedure TAFileManagerController.SetPanels(APreview, AMetadata: Boolean;
  ASelectTab: Integer);
var SelectIt: Boolean; Msg: string;
begin
  SelectIt:=((ASelectTab=0) and APreview) or ((ASelectTab=1) and AMetadata);
  FPreviewVisible:=APreview;
  FMetadataVisible:=AMetadata;
  if (APreview or AMetadata) and (FWindowFrame<>nil) and (FWindowFrame.PreviewPlacement=0) then
    FWindowFrame.SetPreviewPlacement(FPreviewPreferredPlacement);
  UpdatePanelTabVisibility;
  if SelectIt then
  begin
    if FActiveView=0 then
    begin
      if FMetadataTabs<>nil then FMetadataTabs.SelectedIndex:=ASelectTab;
    end
    else if FRightMetadataTabs<>nil then FRightMetadataTabs.SelectedIndex:=ASelectTab;
  end;
  if APreview or AMetadata then UpdatePreview(FActiveView);
  if APreview and AMetadata then Msg:=LocalText('afilemanager_status_panel_both','Panel: preview and metadata')
  else if APreview then Msg:=LocalText('afilemanager_status_panel_preview','Panel: preview')
  else if AMetadata then Msg:=LocalText('afilemanager_status_panel_metadata','Panel: metadata')
  else Msg:=LocalText('afilemanager_status_panel_hidden','Panel hidden');
  SetStatus(Msg);
  UpdateViewToolbarState;
  BuildRootMenu;
end;


procedure TAFileManagerController.TogglePlacesDetailClick(ASender: TArosaControl);
begin
  FPlacesDetailVisible:=not FPlacesDetailVisible;
  if FPlacesDetailTabs<>nil then FPlacesDetailTabs.Visible:=FPlacesDetailVisible;
  if FPlacesDetailSplit<>nil then begin FPlacesDetailSplit.InvalidateLayout; FPlacesDetailSplit.InvalidatePaint; end;
  FPlacesActive:=True;
  UpdatePreviewPercentLabel;
  SaveLayout;
  UpdateViewToolbarState;
  if FPlacesDetailVisible then SetStatus('Places properties/edit panel shown')
  else SetStatus('Places properties/edit panel hidden');
end;

procedure TAFileManagerController.PreviewShareDownClick(ASender: TArosaControl);
begin
  if FPlacesActive then begin if not FPlacesDetailVisible then TogglePlacesDetailClick(ASender); StepPreviewPercent(-5); Exit; end;
  if not FPreviewVisible and not FMetadataVisible then
  begin
    FPreviewVisible:=True;
    UpdatePanelTabVisibility;
    if (FWindowFrame<>nil) and (FWindowFrame.PreviewPlacement=0) then
      FWindowFrame.SetPreviewPlacement(FPreviewPreferredPlacement);
  end;
  StepPreviewPercent(-5);
  UpdateViewToolbarState;
end;

procedure TAFileManagerController.PreviewShareUpClick(ASender: TArosaControl);
begin
  if FPlacesActive then begin if not FPlacesDetailVisible then TogglePlacesDetailClick(ASender); StepPreviewPercent(5); Exit; end;
  if not FPreviewVisible and not FMetadataVisible then
  begin
    FPreviewVisible:=True;
    UpdatePanelTabVisibility;
    if (FWindowFrame<>nil) and (FWindowFrame.PreviewPlacement=0) then
      FWindowFrame.SetPreviewPlacement(FPreviewPreferredPlacement);
  end;
  StepPreviewPercent(5);
  UpdateViewToolbarState;
end;

procedure TAFileManagerController.UpdateViewToolbarState;
var Mode: Integer;
begin
  if FUpdatingToolbarState then Exit;
  FUpdatingToolbarState:=True;
  try
    { 0.6.1.3: stateful toggles.  Preview and Metadata are INDEPENDENT tab
      pages of the panel: each button shows its own page's state and both
      may be on together. }
    if FHiddenToolbarButton<>nil then FHiddenToolbarButton.Toggled:=FShowHiddenFiles;
    if FThumbnailToolbarButton<>nil then
      FThumbnailToolbarButton.Toggled:=FShowThumbnails;
    { Places and file panes are distinct view surfaces.  Do not mix their
      panel toggles in one active surface.  Panel Size already targets Places
      through FPlacesActive or the selected file pane through ActivePreviewSplit. }
    if FPreviewToolbarButton<>nil then
    begin
      FPreviewToolbarButton.Visible:=not FPlacesActive;
      FPreviewToolbarButton.Toggled:=(not FPlacesActive) and FPreviewVisible;
    end;
    if FMetadataToolbarButton<>nil then
    begin
      FMetadataToolbarButton.Visible:=not FPlacesActive;
      FMetadataToolbarButton.Toggled:=(not FPlacesActive) and FMetadataVisible;
    end;
    if FPlacesDetailToolbarButton<>nil then
    begin
      FPlacesDetailToolbarButton.Visible:=FPlacesActive;
      FPlacesDetailToolbarButton.Toggled:=FPlacesActive and FPlacesDetailVisible;
    end;
    if FSplitToolbarButton<>nil then
      FSplitToolbarButton.Toggled:=(FWindowFrame<>nil) and FWindowFrame.SplitView;
    if FActiveView=0 then Mode:=FLeftViewMode else Mode:=FRightViewMode;
    if FListModeRadio<>nil then FListModeRadio.Toggled:=Mode=0;
    if FDetailsModeRadio<>nil then FDetailsModeRadio.Toggled:=Mode=1;
    if FIconsModeRadio<>nil then FIconsModeRadio.Toggled:=Mode=2;
    if FWindowsModeRadio<>nil then FWindowsModeRadio.Toggled:=Mode=3;
    { Visibility changes above alter the retained toolbar layout. }
    if FToolbarTabs<>nil then
    begin
      FToolbarTabs.InvalidateLayout;
      FToolbarTabs.InvalidatePaint;
    end;
  finally
    FUpdatingToolbarState:=False;
  end;
end;

procedure TAFileManagerController.UpdatePanelTabVisibility;
var
  AnyVisible: Boolean;
begin
  AnyVisible := FPreviewVisible or FMetadataVisible;

  if FPreviewPage<>nil then FPreviewPage.Visible:=FPreviewVisible;
  if FMetadataPage<>nil then FMetadataPage.Visible:=FMetadataVisible;
  if FRightPreviewPage<>nil then FRightPreviewPage.Visible:=FPreviewVisible;
  if FRightMetadataPage<>nil then FRightMetadataPage.Visible:=FMetadataVisible;

  { Hiding Preview/Metadata must never detach or hide the browser.  The
    splitter already expands its first pane when the second pane is invisible,
    so panel visibility is purely a visibility decision, not a reparenting
    operation. }
  if FLeftPreviewHost<>nil then FLeftPreviewHost.Visible:=AnyVisible;
  if FRightPreviewHost<>nil then FRightPreviewHost.Visible:=AnyVisible;

  if FMetadataTabs<>nil then
  begin
    if FPreviewVisible and not FMetadataVisible then FMetadataTabs.SelectedIndex:=0
    else if FMetadataVisible and not FPreviewVisible then FMetadataTabs.SelectedIndex:=1;
    FMetadataTabs.InvalidateLayout;
    FMetadataTabs.InvalidatePaint;
  end;
  if FRightMetadataTabs<>nil then
  begin
    if FPreviewVisible and not FMetadataVisible then FRightMetadataTabs.SelectedIndex:=0
    else if FMetadataVisible and not FPreviewVisible then FRightMetadataTabs.SelectedIndex:=1;
    FRightMetadataTabs.InvalidateLayout;
    FRightMetadataTabs.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.ThemeDarkClick(ASender: TArosaControl);
begin
  if (FWindowFrame<>nil) and (FDarkTheme<>nil) then
  begin
    ApplyTheme(FDarkTheme);
    FActiveThemeId:='Dark';
    BuildRootMenu;
    SetStatus(LocalText('afilemanager_theme_dark_status','Theme: Dark'));
  end;
end;

procedure TAFileManagerController.ThemeLightClick(ASender: TArosaControl);
begin
  if (FWindowFrame<>nil) and (FLightTheme<>nil) then
  begin
    ApplyTheme(FLightTheme);
    FActiveThemeId:='Light';
    BuildRootMenu;
    SetStatus(LocalText('afilemanager_theme_light_status','Theme: Light'));
  end;
end;

procedure TAFileManagerController.ViewListClick(ASender: TArosaControl);
begin
  if FUpdatingToolbarState then Exit;
  if FActiveView=0 then FLeftViewMode:=0 else FRightViewMode:=0;
  ApplyFileViewGeometry(FActiveView);
  RefreshView(FActiveView);
  UpdateViewToolbarState;
  SetStatus('View: List');
end;
procedure TAFileManagerController.ViewDetailsClick(ASender: TArosaControl);
begin
  if FUpdatingToolbarState then Exit;
  if FActiveView=0 then FLeftViewMode:=1 else FRightViewMode:=1;
  ApplyFileViewGeometry(FActiveView);
  RefreshView(FActiveView);
  UpdateViewToolbarState;
  SetStatus('View: Details');
end;
procedure TAFileManagerController.ViewIconsClick(ASender: TArosaControl);
begin
  if FUpdatingToolbarState then Exit;
  { Icon view keeps the same resource identity/selection model, but companion
    .info files become presentation metadata instead of duplicate rows. }
  if FActiveView=0 then FLeftViewMode:=2 else FRightViewMode:=2;
  ApplyFileViewGeometry(FActiveView);
  RefreshView(FActiveView);
  UpdateViewToolbarState;
  SetStatus('View: Icons');
end;

procedure TAFileManagerController.ViewWindowsClick(ASender: TArosaControl);
begin
  if FUpdatingToolbarState then Exit;
  if FActiveView=0 then FLeftViewMode:=3 else FRightViewMode:=3;
  ApplyFileViewGeometry(FActiveView);
  RefreshView(FActiveView);
  UpdateViewToolbarState;
  SetStatus('View: Workbench');
  if ASender=nil then ;
end;

procedure TAFileManagerController.LeftFilterChanged(ASender: TArosaControl);
begin
  if FLeftList<>nil then FLeftList.SetFilter(FLeftFilter.Text);
end;

procedure TAFileManagerController.LeftSearchChanged(ASender: TArosaControl);
begin
  ApplyResourceSearch(0);
end;

procedure TAFileManagerController.RightFilterChanged(ASender: TArosaControl);
begin
  if (FRightList<>nil) and (FRightFilter<>nil) then
    FRightList.SetFilter(FRightFilter.Text);
end;

procedure TAFileManagerController.RightSearchChanged(ASender: TArosaControl);
begin
  ApplyResourceSearch(1);
end;

procedure TAFileManagerController.PlacesFilterChanged(ASender: TArosaControl);
begin
  if (FAssignments<>nil) and (FPlacesFilter<>nil) then
    FAssignments.SetFilter(FPlacesFilter.Text);
end;

procedure TAFileManagerController.ClearPlacesFilterClick(ASender: TArosaControl);
begin
  if FPlacesFilter=nil then Exit;
  FPlacesFilter.Text:='';
  if FAssignments<>nil then FAssignments.ClearFilter;
end;

procedure TAFileManagerController.HoverHint(const AHint: string);
begin
  if FStatus=nil then Exit;
  if Trim(AHint)<>'' then FStatus.Text:=AHint
  else FStatus.Text:=LocalText('afilemanager_status_ready','Ready');
  FStatus.InvalidatePaint;
end;


function TAFileManagerController.ResourceTypeName(
  const AInfo: TArosaFileInfo): string;
var E: string;
begin
  if AInfo.Kind=afekDirectory then Exit(LocalText('afilemanager_type_directory','DIR'));
  E:=LowerCase(ExtractFileExt(AInfo.Name));
  if E='.info' then Exit(LocalText('afilemanager_type_info','INFO'));
  if (E='.txt') or (E='.readme') then Exit(LocalText('afilemanager_type_text','TEXT'));
  if (E='.pas') or (E='.pp') or (E='.c') or (E='.h') or (E='.cpp') then Exit(LocalText('afilemanager_type_source','SOURCE'));
  if (E='.png') or (E='.jpg') or (E='.jpeg') or (E='.gif') or (E='.bmp') then Exit(LocalText('afilemanager_type_image','IMAGE'));
  if (E='.zip') or (E='.lha') or (E='.lzh') or (E='.tar') or (E='.gz') then Exit(LocalText('afilemanager_type_archive','ARCHIVE'));
  if (E='.odt') or (E='.doc') or (E='.docx') or (E='.pdf') then Exit(LocalText('afilemanager_type_document','DOCUMENT'));
  if E<>'' then Exit(UpperCase(Copy(E,2,10)));
  Result:=LocalText('afilemanager_type_file','FILE');
end;

function TAFileManagerController.DetailsHeader: string;
begin
  Result := 'TYPE      NAME                         SIZE       MODIFIED          PERMISSIONS';
end;

function TAFileManagerController.DetailsRow(const AInfo: TArosaFileInfo): string;
var T,N,Sz,Dt,Perm: string;
begin
  T:=ResourceTypeName(AInfo);
  N:=AInfo.Name;
  if Length(T)>9 then SetLength(T,9);
  while Length(T)<10 do T:=T+' ';
  if Length(N)>28 then SetLength(N,28);
  while Length(N)<29 do N:=N+' ';
  if AInfo.Kind=afekDirectory then Sz:=''
  else Sz:=SizeText(AInfo.Size);
  while Length(Sz)<10 do Sz:=' '+Sz;
  if AInfo.ModifiedUtc>0 then Dt:=FormatDateTime('yyyy-mm-dd hh:nn',AInfo.ModifiedUtc)
  else Dt:='';
  while Length(Dt)<18 do Dt:=Dt+' ';
  if AInfo.ReadOnly then Perm:=LocalText('afilemanager_permission_read_only','read-only') else Perm:=LocalText('afilemanager_permission_read_write','read/write');
  Result:=T+N+Sz+'  '+Dt+' '+Perm;
end;

procedure TAFileManagerController.ExecuteScriptClick(ASender: TArosaControl);
var I: Integer; P, OutText: string; L: TArosaFilteredListView;
begin
  FCommandHistory.Remember('File.Execute');
  L := ViewList(FActiveView); I := L.SelectedIndex;
  if I < 0 then begin SetStatus('Select one script first'); Exit; end;
  P := SelectedPath(FActiveView, I);
  if IsProviderLocation(P) then
  begin
    SetStatus('Remote resources cannot be executed directly; copy the file locally first');
    Exit;
  end;
  if FPaths.IsDirectory(P) then begin SetStatus('A directory cannot be executed'); Exit; end;
  if RunCommand('C:Execute', P, ViewCurrent(FActiveView), OutText) then
    SetStatus('Script completed: ' + P) else SetStatus('Script failed: ' + P + ' ' + OutText);
end;

procedure TAFileManagerController.DualViewClick(ASender: TArosaControl);
begin
  if not FWindowFrame.SplitView then FWindowFrame.ToggleSplitView;
  SetStatus('Dual-location view');
end;
procedure TAFileManagerController.LeftOnlyClick(ASender: TArosaControl);
begin
  SetActiveView(0);
  if FWindowFrame.SplitView then FWindowFrame.ToggleSplitView
  else WindowSplitViewChanged(FWindowFrame);
end;
procedure TAFileManagerController.RightOnlyClick(ASender: TArosaControl);
begin
  SetActiveView(1);
  if FWindowFrame.SplitView then FWindowFrame.ToggleSplitView
  else WindowSplitViewChanged(FWindowFrame);
end;
procedure TAFileManagerController.WindowToolbarChanged(ASender: TArosaControl);
begin
  if FToolbarTabs <> nil then
  begin
    FToolbarTabs.Visible := FWindowFrame.ToolbarVisible;
    FToolbarTabs.InvalidateLayout;
    FToolbarTabs.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.WindowFilePanelChanged(ASender: TArosaControl);
begin
  if FOperationTabs <> nil then
  begin
    FOperationTabs.Visible := FWindowFrame.FilePanelVisible;
    FOperationTabs.InvalidateLayout;
    FOperationTabs.InvalidatePaint;
  end;
end;

procedure TAFileManagerController.WindowSplitViewChanged(ASender: TArosaControl);
begin
  { Dual-location visuals are instantiated only when the descriptor requested
    the capability. A runtime toggle cannot synthesize a missing second view.

    Reparenting must be explicit and ordered. The places tree is a child of
    FPlacesPanel, never a direct child of FPlacesSplit. Likewise FLeftColumn
    must be detached from FDualViewSplit before it can become the sole view. }
  if FRightColumn=nil then Exit;

  FLeftColumn.Visible := True;
  FRightColumn.Visible := FWindowFrame.SplitView;

  if FPlacesSplit<>nil then
    FPlacesSplit.SetPanes(nil,nil);

  if FWindowFrame.SplitView then
  begin
    FDualViewSplit.SetPanes(FLeftColumn,FRightColumn);
    FDualViewSplit.Visible := True;
    FViewsHost := FDualViewSplit;
  end
  else
  begin
    FDualViewSplit.SetPanes(nil,nil);
    FDualViewSplit.Visible := False;
    FViewsHost := FLeftColumn;
  end;

  if FPlacesSplit<>nil then
    FPlacesSplit.SetPanes(FPlacesPanel,FViewsHost);
  if FViewsHost<>nil then FViewsHost.InvalidateLayout;
  if ASender=nil then ;
end;

procedure TAFileManagerController.SwapViewsClick(ASender: TArosaControl);
var S: string; OldActive: Integer;
begin
  if FRightList=nil then
  begin
    SetStatus('Swap views requires DualView.');
    Exit;
  end;
  OldActive := FActiveView;
  S := FLeftCurrent; FLeftCurrent := FRightCurrent; FRightCurrent := S;
  { The path editors are authoritative for Refresh, so swap them together
    with the location models.  The previous code swapped only the model and
    the next Refresh restored the old path into the active pane. }
  FLeftPath.Text := FLeftCurrent;
  FRightPath.Text := FRightCurrent;
  SyncCrumbs(0);
  SyncCrumbs(1);
  RefreshView(0);
  RefreshView(1);
  SetActiveView(1 - OldActive);
end;


{ 0.8.29.2.3: progress points from inside font opening, font file reading
  and the font catalogue.  The point is always published as the endpoint
  stage ('progress ...'), which Foundation shows while the program is
  blocked inside a system call; during start-up it is also logged. }
var
  GProgressLogging: Boolean = True;

procedure AFMProgressHook(const APoint: string);
begin
  ArosaAppEndpointSetStage('progress '+APoint);
  if GProgressLogging then
  begin
    DiagnosticInfo('startup progress '+APoint);
    DiagnosticFlush;
  end;
end;

procedure StartupCheckpoint(const AStage: string);
begin
  { Startup checkpoints are operational lifecycle information, not DEBUG-only
    chatter.  Keep them at INFO so a failed launch remains diagnosable even
    when no --trace switch is supplied.  Pump immediately because startup may
    fail before the normal application event loop gets a chance to flush the
    diagnostic queue.  0.8.27.10: the stage is also published in the
    application endpoint, and every record names the Exec task. }
  ArosaAppEndpointSetStage(AStage);
  DiagnosticInfo('startup stage='+AStage+' build='+ArosaBuildTag+
    ' instance='+ArosaCurrentTaskText);
  { 0.8.29.1.2: the whole queue - under --trace one batch per checkpoint
    left the log far behind the program }
  DiagnosticFlush;
end;

{ 0.6.1.6: the program's work runs in this procedure so that every hidden
  interface temporary FPC creates (function results such as
  ArosaCreatePlatform, interface arguments) is released when it returns -
  while the platform object is still alive.  In the main block those
  temporaries were only released at "end.", AFTER ArosaDestroyPlatform had
  freed the object: fpc_intf_decr_ref on freed memory at program exit,
  whose outcome depended on what had reused that memory (the quit
  crash).  The platform is destroyed by the main block after this
  procedure has returned. }
procedure RunAFileManager(var APlatform: IArosaPlatform);
var
  App: TArosaApplication; Theme: TArosaTheme;
  Fonts: TArosaFontCache; Form: TArosaForm; Host: TArosaFormHost;
  StartupForm: TArosaForm; StartupHost: TArosaFormHost;
  StartupFrame: TArosaWindowFrame; StartupRoot: TArosaColumnPanel;
  StartupTitle, StartupText: TArosaLabel;
  Controller: TAFileManagerController;
  DescriptorArg: string;
  I: Integer;
  WorkspaceScreen: TArosaPlatformHandle;
  RequestedScreenName: string;
begin
  App := nil; Theme := nil; Fonts := nil; Form := nil; Host := nil;
  StartupForm:=nil; StartupHost:=nil; StartupFrame:=nil; StartupRoot:=nil;
  StartupTitle:=nil; StartupText:=nil;
  Controller := nil;
  WorkspaceScreen:=ArosaNilHandle;
  RequestedScreenName:='';
  try
    {$IFDEF AROS}
    APlatform := ArosaCreatePlatform('AROS');
    {$ELSE}
    APlatform := ArosaCreatePlatform('Null');
    {$ENDIF}
    StartupCheckpoint('platform-created');
    App := TArosaApplication.CreateApplication('AFileManager', ArosaBuildTag, APlatform);
    StartupCheckpoint('application-created');
    App.Initialize; StartupCheckpoint('application-initialized'); Theme := ArosaCreateArosaTheme; Fonts := TArosaFontCache.CreateForPlatform(APlatform);

    { 0.15.3.0.0.0: cold start can spend tens of seconds building/refreshing
      caches, fonts, descriptors and workspace metadata before the primary
      frame exists.  Put up an AROSA preparation surface first so the user
      never mistakes legitimate first-start work for a hung application. }
    StartupForm:=TArosaForm.Create;
    StartupForm.Caption:='AFileManager is preparing';
    StartupForm.Resizable:=False;
    StartupForm.BorderStyle:=afbsNone;
    StartupForm.WindowBounds:=ArosaRectXYWH(120,100,560,180);
    StartupFrame:=TArosaWindowFrame.CreateControl(Theme,Fonts);
    StartupFrame.NativeDecorations:=False;
    StartupFrame.Title:='AFileManager '+ArosaBuildTag;
    StartupFrame.SetConstraintWidth(asmStar,ArosaCoord(1));
    StartupFrame.SetConstraintHeight(asmStar,ArosaCoord(1));
    StartupForm.AddVisual(StartupFrame);
    StartupRoot:=TArosaColumnPanel.Create;
    StartupRoot.Spacing:=ArosaCoord(10);
    StartupRoot.SetConstraintWidth(asmStar,ArosaCoord(1));
    StartupRoot.SetConstraintHeight(asmStar,ArosaCoord(1));
    StartupFrame.ClientContent:=StartupRoot;
    StartupTitle:=TArosaLabel.CreateControl(Theme,Fonts);
    StartupTitle.Text:='Preparing AFileManager...';
    StartupTitle.SetConstraintHeight(asmFixed,ArosaCoord(36));
    StartupRoot.AddVisual(StartupTitle);
    StartupText:=TArosaLabel.CreateControl(Theme,Fonts);
    StartupText.Text:='First start may take 30 seconds or more while AROSA builds caches, loads fonts, descriptors and workspace metadata.';
    StartupText.SetConstraintHeight(asmFixed,ArosaCoord(72));
    StartupRoot.AddVisual(StartupText);
    StartupHost:=TArosaFormHost.Create(App,StartupForm);
    StartupHost.CloseTerminatesApplication:=False;
    StartupHost.BindWindowFrame(StartupFrame);
    StartupHost.Open;
    StartupCheckpoint('preparation-window-opened');

    Form := TArosaForm.Create;
    Form.Resizable := True;
    Form.BorderStyle := afbsNone;
    { Preserve the established first-argument descriptor contract. --trace is
      a flag, not a descriptor selector.  For compatibility with the documented
      test form `--trace <descriptor.window>`, accept the following argument as
      a descriptor only when it is actually a .window descriptor.  In
      particular, a log/output filename after --trace must never replace the
      normal PROGDIR:AFileManager.window startup descriptor. }
    DescriptorArg := '';
    { Diagnostic switches are flags, never descriptor names.  Preserve the
      old positional descriptor contract while allowing --verbose/--trace in
      either order. }
    if ParamCount>0 then
      for I:=1 to ParamCount do
        if (Trim(ParamStr(I))<>'') and (ParamStr(I)[1]<>'-') and
           SameText(ExtractFileExt(Trim(ParamStr(I))),'.window') then
        begin
          DescriptorArg:=ParamStr(I);
          Break;
        end;
    Controller := TAFileManagerController.CreateManager(
      APlatform, Form, Theme, Fonts, DescriptorArg,'default');
    StartupCheckpoint('controller-created');
    FreeAndNil(StartupHost);
    FreeAndNil(StartupForm);
    StartupFrame:=nil; StartupRoot:=nil; StartupTitle:=nil; StartupText:=nil;
    StartupCheckpoint('preparation-window-closed');
    Host := TArosaFormHost.Create(App, Form);
    Host.CloseTerminatesApplication := False;
    {$IFDEF AROS}
    { AROSA environment launches pass --screen=<public-screen>. An explicit
      target is authoritative: never silently fall back to Workbench when that
      screen cannot be borrowed. A direct/manual launch without --screen keeps
      the traditional behaviour and opens on the current front screen. }
    RequestedScreenName:=ArosaCommandLineScreenName;
    if RequestedScreenName<>'' then
    begin
      if not ArosaBorrowPublicScreen(RequestedScreenName,WorkspaceScreen) then
        raise Exception.Create('Requested AROSA workspace screen is not available: '+
          RequestedScreenName);
    end
    else
      ArosaBorrowFrontScreen(WorkspaceScreen);
    if WorkspaceScreen<>ArosaNilHandle then Host.TargetScreen:=WorkspaceScreen;
    {$ENDIF}
    Controller.BindNativeHost(Host);
    StartupCheckpoint('window-opening'); Host.Open; StartupCheckpoint('window-opened');
    { from here on a second launch hands off to this instance }
    ArosaAppEndpointSetPhase(aapeRunning);
    StartupCheckpoint('event-loop-enter');
    GProgressLogging:=False;
    App.Run;
    ArosaAppEndpointSetPhase(aapeExiting);
    StartupCheckpoint('event-loop-returned');
    DiagnosticInfo('startup stage=event-loop-stack '+ArosaStackReport);
  finally
    { a later launch now waits for this process to finish instead of
      handing off to it }
    ArosaAppEndpointSetPhase(aapeExiting);
    { unbind while the host and the application are still alive }
    FreeAndNil(StartupHost);
    FreeAndNil(StartupForm);
    StartupFrame:=nil; StartupRoot:=nil; StartupTitle:=nil; StartupText:=nil;
    if Controller<>nil then Controller.UnbindNativeHost;
    StartupCheckpoint('shutdown-host-unbound');
    FreeAndNil(Host);
    StartupCheckpoint('shutdown-host-released');
    FreeAndNil(Controller);
    StartupCheckpoint('shutdown-controller-released');
    {$IFDEF AROS}
    { Final-process teardown only: the detached retained form tree currently
      trips a stale child callback during recursive destruction on AROS.  The
      process is exiting immediately, so let Exec reclaim this process-owned
      tree instead of traversing it after its controller has gone away. }
    Form:=nil;
    {$ELSE}
    FreeAndNil(Form);
    {$ENDIF}
    StartupCheckpoint('shutdown-form-released');
    {$IFDEF AROS}
    { Release only after every window/controller that may reference the
      borrowed public screen has been destroyed. }
    ArosaReleaseBorrowedScreen(WorkspaceScreen);
    StartupCheckpoint('shutdown-screen-released');
    {$ENDIF}
    FreeAndNil(Fonts);
    StartupCheckpoint('shutdown-fonts-released');
    FreeAndNil(Theme);
    StartupCheckpoint('shutdown-theme-released');
    FreeAndNil(App);
    StartupCheckpoint('application-objects-released');
  end;
end;

var
  Platform: IArosaPlatform;
  LaunchDecision: TAFMLaunchDecision;
  LaunchReport, LaunchMessage: string;
  ClaimWaitMs: QWord;
  StaleBreak: Boolean;
  SelfEndpoint: TArosaAppEndpointInfo;
begin
  { Detached transfer worker mode. A new AmigaDOS Process starts this same
    executable, so it receives a complete independent FPC program startup and
    does not depend on a second worker binary being deployed beside AFileManager.
    0.8.27.10: under its own Exec task name it is never counted as a second
    AFileManager - not by the single-instance logic, not by Foundation. }
  if (ParamCount>=2) and SameText(ParamStr(1),'--transfer-worker') then
  begin
    ArosaRenameCurrentTask('AFileManager.TransferWorker');
    try
      RunAFileManagerTransferWorker(ParamStr(2));
    finally
      ArosaRestoreTaskName;
    end;
    Halt(0);
  end;

  { 0.8.29.1: before anything deep runs - see the $M note at the top }
  ArosaStackPaint;

  { A Ctrl-C still pending in the Shell process this program runs in
    belongs to something earlier; it must not close this instance on its
    first event-loop pass.  It is reported once diagnostics are up. }
  StaleBreak:=ArosaClearStaleBreak;

  { Single instance, decided BEFORE the diagnostics session starts: a launch
    that hands off must not restart the running instance's log session. }
  LaunchDecision:=AFileManagerClaimInstance(LaunchReport,LaunchMessage,ClaimWaitMs);
  if LaunchDecision<>afldRun then
  begin
    DiagnosticStart(AFM_LAUNCHER_ID);
    if LaunchDecision=afldHandedOff then
      DiagnosticInfo('startup stage=duplicate-launch-handed-off '+LaunchReport+
        ' waited-ms='+IntToStr(ClaimWaitMs)+' instance='+ArosaCurrentTaskText+
        ' build='+ArosaBuildTag)
    else
      DiagnosticWarning('startup stage=duplicate-launch-refused '+LaunchReport+
        ' waited-ms='+IntToStr(ClaimWaitMs)+' instance='+ArosaCurrentTaskText+
        ' build='+ArosaBuildTag);
    DiagnosticFlush;
    DiagnosticStop;
    { AFileManager never fails silently: the user is told too - in the
      launching CLI, or in a requester when there is no interactive
      output (RUN >NIL:, Workbench).  A hand-off needs no requester: the
      running window comes to the front. }
    if LaunchDecision=afldRefused then
      AFileManagerTellUser(LaunchMessage+#10+'Details: AROSAFoundation application '+
        AFM_APPLICATION_ID+' status')
    else
      ArosaConsoleLine(LaunchMessage);
    if LaunchDecision=afldHandedOff then Halt(0) else Halt(10);
  end;

  DiagnosticStart(AFM_APPLICATION_ID);
  StartupCheckpoint('process-enter');
  ArosaSetProgressHook(@AFMProgressHook);
  if StaleBreak then
    DiagnosticWarning('startup stale-break-signal-cleared instance='+
      ArosaCurrentTaskText);
  if LaunchReport<>'' then
    DiagnosticWarning('startup '+LaunchReport+' waited-ms='+IntToStr(ClaimWaitMs)+
      ' instance='+ArosaCurrentTaskText)
  else if ClaimWaitMs>0 then
    DiagnosticInfo('startup instance-claimed waited-ms='+IntToStr(ClaimWaitMs)+
      ' instance='+ArosaCurrentTaskText);
  DiagnosticInfo('build='+ArosaBuildTag+' line='+ArosaBuildLine+
    ' clock='+ArosaMonotonicSource);
  { 0.8.29.1.2: what other processes (Foundation, a second launch) see of
    this instance's endpoint }
  if ArosaAppEndpointInspect(AFM_APPLICATION_ID,SelfEndpoint) then
    DiagnosticInfo('startup endpoint name='+ArosaAppEndpointName(AFM_APPLICATION_ID)+
      ' owned='+BoolToStr(ArosaAppEndpointOwned,True)+
      ' visible=True owner='+IntToHex(SelfEndpoint.OwnerTask,8)+
      ' listed='+BoolToStr(SelfEndpoint.OwnerListed,True)+
      ' phase='+ArosaAppEndpointPhaseName(SelfEndpoint.Phase))
  else
    DiagnosticWarning('startup endpoint name='+ArosaAppEndpointName(AFM_APPLICATION_ID)+
      ' owned='+BoolToStr(ArosaAppEndpointOwned,True)+' visible=False foreign='+
      BoolToStr(SelfEndpoint.Foreign,True));
  DiagnosticInfo('startup endpoint-port '+ArosaAppEndpointDiagnosis);
  { Phase F: this instance's application context - the launch the
    Application Service gave it, or one of the console session.  Without the
    Security Service AFileManager keeps working in compatibility mode. }
  if ArosaSessionAttachProcess(AFM_APPLICATION_ID,LaunchReport) then
    DiagnosticInfo('startup security-context=application launch='+ArosaProcessLaunchMode)
  else
    DiagnosticWarning('startup security-context=none ('+LaunchReport+
      '): resource state in compatibility mode');
  DiagnosticPump;
  {$IFNDEF AROS}
  WriteLn('AFileManager'); WriteLn('=================='); WriteLn(ArosaBuildLine); Flush(Output);
  {$ENDIF}
  Platform := nil;
  try
    try
      RunAFileManager(Platform);
    except
      on E: Exception do
      begin
        DiagnosticFatal('startup exception class='+E.ClassName+' message='+E.Message);
        DiagnosticFlush;
        raise;
      end;
    end;
  finally
    ArosaSetProgressHook(nil);
    ArosaDestroyPlatform(Platform);
    StartupCheckpoint('platform-destroyed-exit');
    { the instance's context ends with it (sec. 7.2) }
    ArosaSessionDetachProcess;
    { the next launch may become the instance from this moment on }
    ArosaAppEndpointRelease;
    DiagnosticInfo('startup stage=application-endpoint-released instance='+
      ArosaCurrentTaskText);
    { the whole run, measured before the start-up code frees the stack }
    if ArosaStackExhausted then
    begin
      DiagnosticWarning('startup stage=shutdown-stack '+ArosaStackReport);
      ArosaConsoleLine('AFileManager: the program stack was exhausted ('+
        ArosaStackReport+'); please report this with the log.');
    end
    else
      DiagnosticInfo('startup stage=shutdown-stack '+ArosaStackReport);
    DiagnosticPump;
    DiagnosticStop;
  end;
end.
