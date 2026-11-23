// Copyright (c) 2026 DaniloS
// This file is part of the AFileManager project.
// This Source Code Form is subject to the terms of the
// Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

unit AFileManager.Dialogs;

{ AFileManager application dialogs built entirely from the shared AROSA
  retained UI controls.  The dialogs deliberately do not introduce private
  text/editing widgets: text, sliders, check boxes, tabs and buttons all use
  the framework controls so AROS, Linux and Windows hosts share behaviour. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils,
  Arosa.Geometry, Arosa.Graphics, Arosa.Platform.Api,
  Arosa.UI.Visual, Arosa.UI.Input, Arosa.UI.Layout, Arosa.UI.Controls,
  Arosa.UI.Theme, Arosa.UI.Pickers, Arosa.UI.HtmlView, Arosa.UI.FileDialog, Arosa.UI.FileDialog.Images, Arosa.UI.Localization,
  Arosa.Services.Images, Arosa.Services.Fonts, Arosa.Services.Localization,
  Arosa.Services.DataTransfer, Arosa.Services.WorkspaceModules;

type
  { Shortcut list with list-level in-place recording.

    Earlier revisions embedded one focusable editor control in every list row.
    On AROS that forced nested row hit-testing/focus routing and repaint work for
    every shortcut keystroke. The list itself is already the routed focus target,
    so shortcut capture belongs here: rows remain lightweight labels, clicking the
    Shortcut column selects an editing cell, and the next key combination updates
    that cell directly. }
  TAFMShortcutListView = class(TArosaFilteredListView)
  private
    FEditingRow: Integer;
    function ShortcutColumnLeft: TArosaCoord;
    function ShortcutLabel(AVisibleIndex: Integer): TArosaLabel;
    procedure SetShortcut(AVisibleIndex: Integer; const AValue: string);
  protected
    procedure PaintContent(ACanvas: TArosaCanvas); override;
    procedure HandleInput(var AEvent: TArosaInputEvent); override;
  public
    constructor Create; override;
    procedure EndShortcutEdit;
  end;

  TAFMConfigurationSettings = record
    ThemeId: string;             { Dark / Light appearance }
    ThemePackageId: string;      { installed package under themes/ }
    InterfaceLanguage: string;
    ToolbarVisible: Boolean;
    OperationsVisible: Boolean;
    SplitView: Boolean;
    PreviewVisible: Boolean;
    EditorRenditionVisible: Boolean; { show document rendition pane when an editor opens }
    MetadataVisible: Boolean;
    ConfirmDeletion: Boolean;
    { 0.10.6.2: what a plain drag does - Move, Copy or Ask - within one
      volume and across volumes ([FileOperations] DragSameVolume /
      DragOtherVolume) }
    DragSameVolume: string;
    DragOtherVolume: string;
    LoggingEnabled: Boolean;      { AROSA Logging Service request }
    LoggingLevel: string;         { Trace/Debug/Info/Warning/Error/Fatal }
    ShowThumbnails: Boolean;
    ThumbnailSize: Integer;
    IconSize: Integer;
    RowPadding: Integer;
    IconTextGap: Integer;
    DefaultViewMode: string;
    ColumnOrder: string;          { comma-separated semantic column ids }
    VisibleColumns: string;       { comma-separated visible semantic ids }
    DefaultSortColumn: string;
    DefaultSortAscending: Boolean;
    DefaultDescriptor: string;
    UserProfile: string;
    UIFontFamily: string;
    UIFontSize: Integer;
    FileFontFamily: string;
    FileFontSize: Integer;
    FixedFontFamily: string;
    FixedFontSize: Integer;
    DocumentFontFamily: string;
    DocumentFontSize: Integer;
    InfoFontFamily: string;
    InfoFontSize: Integer;
    ShortcutBindings: string;     { effective Key=Command bindings }
    DefaultShortcutBindings: string; { descriptor defaults, before user overlay }
  end;

  TAFMFontRole = (affrText, affrLists, affrConsole, affrHelp, affrInfo);

  TAFMColumnConfiguration = record
    Id: string;
    Caption: string;
    Visible: Boolean;
  end;

  TAFMConfigurationApplyEvent = procedure(ASender: TArosaControl;
    const ASettings: TAFMConfigurationSettings; APersist: Boolean) of object;

  { Common retained application-dialog surface.  It owns the modality/scrim,
    while concrete dialogs compose their content from normal AROSA controls. }
  TAFMDialogSurface = class(TArosaControl)
  private
    FDialogPanel: TArosaPanel;
    FContent: TArosaColumnPanel;
    FPreferredWidth: Integer;
    FPreferredHeight: Integer;
    FResizable: Boolean;
    FResizeDragging: Boolean;
    FResizeStartRoot: TArosaPoint;
    FResizeStartWidth: Integer;
    FResizeStartHeight: Integer;
    function ResizeHandleRect: TArosaRect;
  protected
    procedure PaintContent(ACanvas: TArosaCanvas); override;
    procedure ArrangeOverride(const AFinalSize: TArosaSize); override;
    procedure HandleInput(var AEvent: TArosaInputEvent); override;
    function AcceptsFocus: Boolean; override;
    procedure BeginModal;
    procedure EndModal;
    property DialogPanel: TArosaPanel read FDialogPanel;
    property Content: TArosaColumnPanel read FContent;
  public
    constructor CreateDialog(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      AWidth, AHeight: Integer);
    procedure ShowDialog;
    procedure Dismiss;
    property Resizable: Boolean read FResizable write FResizable;
  end;

  TAFileManagerConfigurationDialog = class(TAFMDialogSurface)
  private
    FThemeCombo: TArosaComboBox;
    FAppearanceCombo: TArosaComboBox;
    FLanguageCombo: TArosaComboBox;
    FToolbar, FOperations, FSplit, FPreview, FEditorRendition, FMetadata, FConfirmDelete: TArosaCheckBox;
    FLoggingEnabled: TArosaCheckBox;
    FLoggingLevel: TArosaComboBox;
    FDragSameCombo, FDragOtherCombo: TArosaComboBox;
    FShowThumbnails: TArosaCheckBox;
    FThumbnailSize, FIconSize, FRowPadding, FIconGap: TArosaSlider;
    FThumbnailSizeValue, FIconSizeValue, FRowPaddingValue, FIconGapValue: TArosaLabel;
    FViewList, FViewDetails, FViewIcons, FViewWorkbench: TArosaRadioButton;
    FColumnList: TArosaFilteredListView;
    FColumnFilter: TArosaTextBox;
    FColumnMoveUp, FColumnMoveDown: TArosaButton;
    FDefaultSortCombo: TArosaComboBox;
    FDefaultSortAscending: TArosaCheckBox;
    FColumns: array of TAFMColumnConfiguration;
    FColumnCount: Integer;
    FDescriptorCombo, FProfileCombo: TArosaComboBox;
    FFontPicker: TArosaFontPicker;
    FFontPickerGroup: TArosaGroupBox;
    FShortcutFilter: TArosaTextBox;
    FShortcutList: TAFMShortcutListView;
    FShortcutRestore: TArosaButton;
    FDefaultShortcutBindings: string;
    FFontSelections: array[TAFMFontRole] of TArosaFontDescription;
    FFontRoleLabels: array[TAFMFontRole] of TArosaLabel;
    FFontValueLabels: array[TAFMFontRole] of TArosaLabel;
    FFontSelectButtons: array[TAFMFontRole] of TArosaButton;
    FActiveFontRole: TAFMFontRole;
    FApplyButton, FSaveButton, FCancelButton: TArosaButton;
    FOnApply: TAFMConfigurationApplyEvent;
    FLocalization: TArosaLocalizationService;
    FControlFonts: TArosaFontCache;
    function LocalText(const AKey, AFallback: string): string;
    procedure SliderChanged(ASender: TArosaControl; AValue: Integer);
    procedure ApplyClick(ASender: TArosaControl);
    procedure SaveClick(ASender: TArosaControl);
    procedure CancelClick(ASender: TArosaControl);
    procedure FontPickerChanged(ASender: TArosaControl);
    procedure TextFontClick(ASender: TArosaControl);
    procedure ListsFontClick(ASender: TArosaControl);
    procedure ConsoleFontClick(ASender: TArosaControl);
    procedure HelpFontClick(ASender: TArosaControl);
    procedure InfoFontClick(ASender: TArosaControl);
    procedure ColumnFilterChanged(ASender: TArosaControl);
    procedure ColumnVisibilityChanged(ASender: TArosaControl);
    procedure ColumnMoveUpClick(ASender: TArosaControl);
    procedure ColumnMoveDownClick(ASender: TArosaControl);
    procedure ShortcutFilterChanged(ASender: TArosaControl);
    procedure ShortcutRestoreClick(ASender: TArosaControl);
    procedure RebuildShortcutList(const ACurrent, ADefaults: string);
    function ShortcutBindingsText: string;
    function ShortcutCommandCaption(const ACommand: string): string;
    function ColumnDragBegin(ASender: TArosaControl; AIndex: Integer;
      const ARootPosition: TArosaPoint; const AModifiers: TArosaModifiers;
      out APayload: TArosaDragPayload): Boolean;
    procedure ColumnDragEnd(ASender: TArosaControl; AIndex: Integer;
      APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
      const AModifiers: TArosaModifiers);
    procedure InitializeColumns;
    procedure RebuildColumnList(ASelectIndex: Integer = -1);
    procedure RebuildSortChoices;
    procedure MoveColumn(AFrom, ATo: Integer);
    function ColumnIndexById(const AId: string): Integer;
    function ColumnOrderText: string;
    function VisibleColumnsText: string;
    procedure LoadColumnConfiguration(const AOrder, AVisible: string);
    procedure SelectFontRole(ARole: TAFMFontRole);
    procedure UpdateFontRoleLabel(ARole: TAFMFontRole);
    function FontRoleCaption(ARole: TAFMFontRole): string;
    function CurrentSettings: TAFMConfigurationSettings;
    procedure UpdateValueLabels;
    function NewPage(ATabs: TArosaTabControl; const ACaption: string): TArosaColumnPanel;
    procedure AddCheck(AParent: TArosaColumnPanel; ACheck: TArosaCheckBox);
    procedure AddSlider(AParent: TArosaColumnPanel; const ACaption: string;
      ASlider: TArosaSlider; AValueLabel: TArosaLabel);
  public
    constructor CreateConfiguration(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const AClipboard: IArosaClipboardPlatform;
      ALocalization: TArosaLocalizationService);
    procedure ShowSettings(const ASettings: TAFMConfigurationSettings);
    procedure SetAvailableFonts(AFontsService: TArosaFontService);
    procedure SetStartupOptions(const ADescriptors, AProfiles: array of string);
    procedure SetThemeOptions(const AThemes: array of string);
    procedure SetLanguageOptions(const ALanguages: array of string);
    property OnApply: TAFMConfigurationApplyEvent read FOnApply write FOnApply;
  end;

  TAFMNameAcceptEvent = procedure(ASender: TArosaControl;
    const AValue: string) of object;

  TAFileManagerNameDialog = class(TAFMDialogSurface)
  private
    FPromptLabel: TArosaLabel;
    FNameBox: TArosaTextBox;
    FOption: TArosaCheckBox;
    FOKButton, FCancelButton: TArosaButton;
    FOnAccept: TAFMNameAcceptEvent;
    function GetOptionChecked: Boolean;
    procedure AcceptClick(ASender: TArosaControl);
    procedure CancelClick(ASender: TArosaControl);
    procedure TextAccept(ASender: TArosaControl);
  public
    constructor CreateNameDialog(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const AClipboard: IArosaClipboardPlatform);
    procedure ShowName(const ATitle, APrompt, AInitialValue: string);
    { The same dialog with one yes/no choice under the name, for a question
      that belongs to the thing being named ("give the new folder an
      icon").  Read the answer from OptionChecked in OnAccept. }
    procedure ShowNameWithOption(const ATitle, APrompt, AInitialValue,
      AOptionCaption: string; AOptionChecked: Boolean);
    { False whenever the dialog was shown without an option. }
    property OptionChecked: Boolean read GetOptionChecked;
    property OnAccept: TAFMNameAcceptEvent read FOnAccept write FOnAccept;
  end;

  TAFMFilePathEvent = procedure(ASender: TArosaControl;
    const APath: string) of object;

  { AFileManager host surface for the shared AROSA file requester. The actual
    browsing/filter/preview control lives in Arosa.UI.FileDialog so other
    AROSA applications can reuse the same requester without AFileManager UI. }
  TAFileManagerOpenFileDialog = class(TAFMDialogSurface)
  private
    FDialog: TArosaFileDialog;
    FImagePresentation: TArosaFileDialogImagePresentation;
    FOnAcceptPath: TAFMFilePathEvent;
    procedure DialogAccepted(ASender: TArosaControl);
    procedure DialogCancelled(ASender: TArosaControl);
  protected
    procedure DoDispose; override;
  public
    constructor CreateOpenFileDialog(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const AClipboard: IArosaClipboardPlatform;
      AImageLoader: TArosaImageLoaderService);
    procedure SetLister(ALister: TArosaDirLister);
    procedure SetRowDecorator(ADecorator: TArosaFileDialogRowDecorator);
    procedure SetIconResolver(AResolver: TArosaFileDialogIconResolver);
    procedure ClearLocations;
    function AddLocationGroup(const ACaption, ASemanticIcon: string): TArosaTreeNode;
    function AddLocation(AParent: TArosaTreeNode; const ACaption, APath,
      ASemanticIcon: string): TArosaTreeNode;
    procedure SetPreviewPlacement(APlacement: TArosaFileDialogPreviewPlacement);
    procedure ShowOpen(const ADirectory, AFileName: string);
    property OnAcceptPath: TAFMFilePathEvent read FOnAcceptPath write FOnAcceptPath;
  end;

  { Compatibility name retained while callers migrate.  The implementation is
    shared by all AROSA consumers in Arosa.UI.Pickers. }
  TAFMGradientPreview = class(TArosaGradientPreview);

  TAFMWorkspaceProperties = record
    Name: string;
    ThemeId: string;
    ScreenWidth: Integer;
    ScreenHeight: Integer;
    ScreenDepth: Integer;
    BackgroundImage: string;
    BackgroundMode: string;
    BackgroundColour1: TArosaColour;
    BackgroundColour2: TArosaColour;
    BackgroundColour3: TArosaColour;
    BackgroundColour4: TArosaColour;
    BackgroundGradientDirection: string;
    BackgroundLayerOrder: string;
    BackgroundOpacity: Integer;
    ShareClipboard: Boolean;
    ShareDesk: Boolean;
  end;

  TAFMWorkspacePropertiesApplyEvent = procedure(ASender: TArosaControl;
    const ASettings: TAFMWorkspaceProperties) of object;

  TAFileManagerWorkspacePropertiesDialog = class(TAFMDialogSurface)
  private
    FLocalization: TArosaLocalizationService;
    FTitleLabel: TArosaLabel;
    FNameBox: TArosaTextBox;
    FThemeCombo: TArosaComboBox;
    FScreenModeCombo: TArosaComboBox;
    FScreenModes: TArosaScreenModeArray;
    FBackgroundBox: TArosaTextBox;
    FBackgroundBrowse: TArosaButton;
    FBackgroundColourRadio, FBackgroundGradientRadio: TArosaRadioButton;
    FBackgroundStartPicker, FBackgroundEndPicker: TArosaColourPicker;
    FBackgroundGradientPreview: TAFMGradientPreview;
    FBackgroundStartLabel, FBackgroundEndLabel: TArosaLabel;
    FBackgroundColours: array[0..3] of TArosaColour;
    FBackgroundDirection: TArosaComboBox;
    FBackgroundLayerOrder: TArosaComboBox;
    FBackgroundOpacity: TArosaSlider;
    FBackgroundOpacityLabel: TArosaLabel;
    FShareClipboard, FShareDesk: TArosaCheckBox;
    FSaveButton, FCancelButton: TArosaButton;
    FOnApply: TAFMWorkspacePropertiesApplyEvent;
    FOnBrowseBackground: TArosaClickEvent;
    function LocalText(const AKey, AFallback: string): string;
    function CurrentSettings: TAFMWorkspaceProperties;
    procedure SaveClick(ASender: TArosaControl);
    procedure CancelClick(ASender: TArosaControl);
    procedure BackgroundBrowseClick(ASender: TArosaControl);
    procedure BackgroundModeChanged(ASender: TArosaControl);
    procedure BackgroundDirectionChanged(ASender: TArosaControl);
    procedure BackgroundStartColourChanged(ASender: TArosaControl);
    procedure BackgroundEndColourChanged(ASender: TArosaControl);
    procedure UpdateBackgroundEditorState;
    procedure UpdateBackgroundGradientColours;
    procedure BackgroundOpacityChanged(ASender: TArosaControl; AValue: Integer);
  public
    constructor CreateWorkspaceProperties(ATheme: TArosaTheme;
      AFonts: TArosaFontCache; const AClipboard: IArosaClipboardPlatform;
      ALocalization: TArosaLocalizationService);
    procedure SetScreenModes(const AModes: TArosaScreenModeArray);
    procedure ShowSettings(const ASettings: TAFMWorkspaceProperties);
    procedure SetBackgroundImage(const APath: string);
    function BackgroundImage: string;
    property OnApply: TAFMWorkspacePropertiesApplyEvent
      read FOnApply write FOnApply;
    property OnBrowseBackground: TArosaClickEvent
      read FOnBrowseBackground write FOnBrowseBackground;
  end;


  TAFMWorkspaceModuleChangeEvent = procedure(ASender: TArosaControl;
    const AWorkspaceId, AModuleId: string; AEnabled: Boolean) of object;

  { 0.8.6.6: where a module of a workspace shows - AKind 0 start menu,
    1 taskbar, 2 desktop }
  TAFMModulePlacementQuery = function(const AWorkspaceId, AModuleId: string;
    AKind: Integer): Boolean of object;
  TAFMModulePlacementChange = procedure(ASender: TArosaControl;
    const AWorkspaceId, AModuleId: string; AKind: Integer;
    AEnabled: Boolean) of object;

  { 0.8.7.0: the dialog edits a configuration and commits it on request.
    The boxes of a row are, in order: 0 part of the workspace, 1 start menu,
    2 taskbar, 3 desktop.  Ticking changes nothing outside the dialog.
      Apply    writes what the boxes say and stays open
      Restore  puts the boxes back to the configuration the dialog opened
               with (to make that the configuration again: Apply or Save)
      Save     writes what the boxes say and closes
      Cancel   closes; what was not applied is dropped }
  TAFMModuleBoxes = array[0..3] of Boolean;

  TAFileManagerWorkspaceModulesDialog = class(TAFMDialogSurface)
  private
    FChecks: TStringList;         { 'module-id|box' -> its check box }
    FStatusLabels: TStringList;   { module id -> its status label }
    FIds: TStringList;            { module ids, in row order }
    FOriginal: array of TAFMModuleBoxes;   { when the dialog opened }
    FPending: array of TAFMModuleBoxes;    { what the boxes say }
    FUpdating: Boolean;
    FOnQueryPlacement: TAFMModulePlacementQuery;
    FOnPlacement: TAFMModulePlacementChange;
    FLocalization: TArosaLocalizationService;
    FModules: TArosaWorkspaceModuleService;
    FWorkspaceId: string;
    FTitleLabel: TArosaLabel;
    FFilter: TArosaTextBox;
    FList: TArosaFilteredListView;
    FDescription: TArosaLabel;
    FApplyButton, FRestoreButton, FSaveButton, FCancelButton: TArosaButton;
    FOnChange: TAFMWorkspaceModuleChangeEvent;
    function LocalText(const AKey, AFallback: string): string;
    function SelectedModuleId: string;
    procedure RebuildList;
    procedure FilterChanged(ASender: TArosaControl);
    procedure SelectionChanged(ASender: TArosaControl; AIndex: Integer);
    procedure ApplyClick(ASender: TArosaControl);
    procedure RestoreClick(ASender: TArosaControl);
    procedure SaveClick(ASender: TArosaControl);
    procedure CancelClick(ASender: TArosaControl);
    function Live(const AModule: TArosaWorkspaceModule): TAFMModuleBoxes;
    function StatusText(AIndex: Integer; const AModule: TArosaWorkspaceModule): string;
    function HasUnapplied: Boolean;
    function DiffersFromOriginal: Boolean;
    procedure RefreshRow(AIndex: Integer);
    procedure UpdateButtons;
    procedure BoxToggled(ASender: TArosaControl);
    procedure ApplyPending;
  protected
    procedure DoDispose; override;
  public
    constructor CreateWorkspaceModules(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const AClipboard: IArosaClipboardPlatform;
      ALocalization: TArosaLocalizationService);
    procedure ShowModules(const AWorkspaceId, AWorkspaceName: string;
      AModules: TArosaWorkspaceModuleService);
    property OnChange: TAFMWorkspaceModuleChangeEvent read FOnChange write FOnChange;
    property OnQueryPlacement: TAFMModulePlacementQuery read FOnQueryPlacement
      write FOnQueryPlacement;
    property OnPlacement: TAFMModulePlacementChange read FOnPlacement
      write FOnPlacement;
    { for the tests: the rows as text, a click on one check box (ABox 0..3),
      a press of 'apply', 'restore', 'save' or 'cancel' }
    function TestDescribe: string;
    function TestToggle(const AModuleId: string; ABox: Integer): Boolean;
    procedure TestPress(const AButton: string);
  end;

    TAFileManagerInfoDialog = class(TAFMDialogSurface)
  private
    FInfoView: TArosaHtmlView;
    FCreditsView: TArosaHtmlView;
    FLogo: TArosaImageBox;
    FLogoResource: TArosaImageResource;
    FCloseButton: TArosaButton;
    FInfoFontFamily: string;
    FInfoFontSize: Integer;
    FOnExternalLink: TArosaHtmlLinkEvent;
    procedure CloseClick(ASender: TArosaControl);
    procedure ApplyInfoFont(AControl: TArosaControl);
    procedure HtmlLinkClicked(ASender: TArosaControl; const AHref: string);
    function InfoCss: string;
  protected
    procedure DoDispose; override;
  public
    constructor CreateInfo(ATheme: TArosaTheme; AFonts: TArosaFontCache;
      const AClipboard: IArosaClipboardPlatform; AImageLoader: TArosaImageLoaderService;
      const AInfoFontFamily: string; AInfoFontSize: Integer);
    procedure ShowInfo(const AText: string);
    property OnExternalLink: TArosaHtmlLinkEvent read FOnExternalLink write FOnExternalLink;
  end;

implementation

{ 0.10.6.2: drag rules as stored ([FileOperations]) and as listed in the
  configuration combos (Move, Copy, Ask) }
function DragRuleText(AIndex: Integer; const ADefault: string): string;
begin
  case AIndex of
    0: Result:='Move';
    1: Result:='Copy';
    2: Result:='Ask';
  else Result:=ADefault;
  end;
end;

function DragRuleIndex(const ARule: string; ADefault: Integer): Integer;
begin
  if SameText(Trim(ARule),'Move') then Result:=0
  else if SameText(Trim(ARule),'Copy') then Result:=1
  else if SameText(Trim(ARule),'Ask') then Result:=2
  else Result:=ADefault;
end;

constructor TAFMShortcutListView.Create;
begin
  inherited Create;
  FEditingRow:=-1;
end;

function TAFMShortcutListView.ShortcutColumnLeft: TArosaCoord;
var
  I: Integer;
begin
  Result:=0;
  for I:=0 to ColumnCount-1 do
  begin
    if I>=2 then Break;
    if (Columns[I]<>nil) and Columns[I].Visible then
      Result:=Result+Columns[I].Width;
  end;
end;

function TAFMShortcutListView.ShortcutLabel(
  AVisibleIndex: Integer): TArosaLabel;
var
  Row: TArosaListRow;
begin
  Result:=nil;
  if (AVisibleIndex<0) or (AVisibleIndex>=ItemCount) then Exit;
  Row:=VisibleRowsView[AVisibleIndex];
  if (Row=nil) or (Row.ObjectCount<3) then Exit;
  if Row.Objects[2] is TArosaLabel then
    Result:=TArosaLabel(Row.Objects[2]);
end;

procedure TAFMShortcutListView.SetShortcut(AVisibleIndex: Integer;
  const AValue: string);
var
  L: TArosaLabel;
begin
  L:=ShortcutLabel(AVisibleIndex);
  if L=nil then Exit;
  if L.Text=AValue then Exit;
  L.Text:=AValue;
  { Rows are retained data objects rather than children of the list visual.
    Invalidate the list explicitly so no nested child/root traversal occurs. }
  InvalidatePaint;
end;

procedure TAFMShortcutListView.EndShortcutEdit;
begin
  if FEditingRow<0 then Exit;
  FEditingRow:=-1;
  InvalidatePaint;
end;

procedure TAFMShortcutListView.PaintContent(ACanvas: TArosaCanvas);
var
  F: TArosaFont;
  L: TArosaLabel;
  X, Y, H, HeaderH, CaretX: TArosaCoord;
  CellRect: TArosaRect;
  Extent: TArosaSize;
begin
  inherited PaintContent(ACanvas);
  if (ACanvas=nil) or (Theme=nil) or (FEditingRow<0) then Exit;
  if (FEditingRow<ScrollOffset) or
     (FEditingRow>=ScrollOffset+VisibleRowCount) then Exit;
  L:=ShortcutLabel(FEditingRow);
  if L=nil then Exit;
  F:=UIFont;
  if F=nil then Exit;

  if HeaderVisible and (ColumnCount>0) then HeaderH:=HeaderHeight
  else HeaderH:=0;
  H:=ItemHeight;
  X:=ShortcutColumnLeft-ArosaCoord(HorizontalOffset);
  Y:=HeaderH+ArosaCoord(FEditingRow-ScrollOffset)*H;
  if ColumnCount>2 then
    CellRect:=ArosaRectRaw(X,Y,X+Columns[2].Width,Y+H)
  else
    CellRect:=ArosaRectRaw(X,Y,ArosaRectWidth(Bounds),Y+H);

  { A focused cell is unmistakable without introducing a separate text
    editor. The accent frame and caret are painted by the list itself. }
  ACanvas.FrameRect(CellRect,Theme.ColourFor(AROSA_ROLE_ACCENT),ArosaCoord(1));
  ACanvas.SetFont(F);
  Extent:=ACanvas.MeasureText(L.Text);
  CaretX:=X+ArosaCoord(6)+Extent.Width+ArosaCoord(1);
  if CaretX>CellRect.Right-ArosaCoord(3) then
    CaretX:=CellRect.Right-ArosaCoord(3);
  ACanvas.DrawVerticalLine(CaretX,Y+ArosaCoord(4),Y+H-ArosaCoord(4),
    Theme.ColourFor(AROSA_ROLE_ACCENT));
end;

procedure TAFMShortcutListView.HandleInput(var AEvent: TArosaInputEvent);
var
  Index: Integer;
  X: TArosaCoord;
  Shortcut: string;
begin
  if AEvent.Kind=aieMouseDown then
  begin
    if AEvent.Button=ambLeft then
    begin
      Index:=ItemAtPosition(AEvent.Position);
      X:=AEvent.Position.X+ArosaCoord(HorizontalOffset);
      if (Index>=0) and (X>=ShortcutColumnLeft) then
      begin
        SelectItem(Index);
        FEditingRow:=Index;
        InvalidatePaint;
        AEvent.Handled:=True;
        Exit;
      end;
      EndShortcutEdit;
    end;
  end;

  if (FEditingRow>=0) and (AEvent.Kind=aieKeyDown) then
  begin
    if AEvent.KeyCode=AROSA_KEY_ESCAPE then
    begin
      EndShortcutEdit;
      AEvent.Handled:=True;
      Exit;
    end;
    if AEvent.KeyCode=AROSA_KEY_ENTER then
    begin
      EndShortcutEdit;
      AEvent.Handled:=True;
      Exit;
    end;
    if AEvent.KeyCode in [AROSA_KEY_DELETE,AROSA_KEY_BACKSPACE] then
    begin
      SetShortcut(FEditingRow,'');
      AEvent.Handled:=True;
      Exit;
    end;
    Shortcut:=ArosaShortcutText(AEvent);
    if Shortcut<>'' then
      SetShortcut(FEditingRow,Shortcut);
    { Once a shortcut cell is active, every key-down is consumed. This is
      both faster than routing through embedded controls and prevents the
      combination from reaching AFileManager command dispatch. }
    AEvent.Handled:=True;
    Exit;
  end;

  if (FEditingRow>=0) and (AEvent.Kind=aieKeyUp) then
  begin
    AEvent.Handled:=True;
    Exit;
  end;

  if AEvent.Kind=aieFocusLost then EndShortcutEdit;
  inherited HandleInput(AEvent);
end;

function RawRect(X,Y,W,H: TArosaCoord): TArosaRect; inline;
begin
  Result:=ArosaRectRaw(X,Y,X+W,Y+H);
end;

function HtmlEscape(const S: string): string;
begin
  Result:=StringReplace(S,'&','&amp;',[rfReplaceAll]);
  Result:=StringReplace(Result,'<','&lt;',[rfReplaceAll]);
  Result:=StringReplace(Result,'>','&gt;',[rfReplaceAll]);
  Result:=StringReplace(Result,'"','&quot;',[rfReplaceAll]);
end;


constructor TAFMDialogSurface.CreateDialog(ATheme: TArosaTheme;
  AFonts: TArosaFontCache; AWidth, AHeight: Integer);
begin
  inherited CreateControl(ATheme,AFonts);
  Visible:=False;
  CanFocus:=True;
  BorderVisible:=False;
  FPreferredWidth:=AWidth;
  FPreferredHeight:=AHeight;
  FResizable:=False;
  FResizeDragging:=False;
  FResizeStartRoot:=ArosaPoint(0,0);
  FResizeStartWidth:=AWidth;
  FResizeStartHeight:=AHeight;

  FDialogPanel:=TArosaPanel.Create;
  FDialogPanel.BackgroundRole:=AROSA_ROLE_CONTROL_BG;
  FDialogPanel.Padding:=ArosaUniformMargins(12);
  AddVisual(FDialogPanel);

  FContent:=TArosaColumnPanel.Create;
  FContent.Spacing:=ArosaCoord(8);
  FDialogPanel.AddVisual(FContent);
end;

procedure TAFMDialogSurface.BeginModal;
begin
  if RootView<>nil then RootView.ModalOwner:=Self;
end;

procedure TAFMDialogSurface.EndModal;
begin
  if (RootView<>nil) and (RootView.ModalOwner=Self) then RootView.ModalOwner:=nil;
end;

procedure TAFMDialogSurface.ShowDialog;
begin
  Visible:=True;
  BeginModal;
  if ParentVisual<>nil then
  begin
    ParentVisual.InvalidateLayout;
    ParentVisual.InvalidatePaint;
  end
  else
  begin
    InvalidateLayout;
    InvalidatePaint;
  end;
end;

procedure TAFMDialogSurface.Dismiss;
var P: TArosaVisual;
begin
  EndModal;
  Visible:=False;
  P:=ParentVisual;
  if P<>nil then
  begin
    P.InvalidateLayout;
    P.InvalidatePaint;
  end
  else InvalidatePaint;
end;

function TAFMDialogSurface.ResizeHandleRect: TArosaRect;
var R: TArosaRect;
begin
  if FDialogPanel=nil then Exit(ArosaRectRaw(0,0,0,0));
  R:=FDialogPanel.Bounds;
  Result:=ArosaRectRaw(R.Right-ArosaCoord(18),R.Bottom-ArosaCoord(18),
    R.Right,R.Bottom);
end;

procedure TAFMDialogSurface.PaintContent(ACanvas: TArosaCanvas);
var R, G: TArosaRect; I: Integer; C: TArosaColour;
begin
  if (ACanvas=nil) or (Theme=nil) then Exit;
  { Modal focus is explicit: shade the already-painted application beneath
    the dialog, then paint the dialog panel itself fully opaque. }
  ACanvas.ShadeRect(ArosaRectRaw(0,0,ArosaRectWidth(Bounds),ArosaRectHeight(Bounds)),
    ArosaColour(0,0,0),2);
  R:=FDialogPanel.Bounds;
  ACanvas.FillRect(R,Theme.ColourFor(AROSA_ROLE_CONTROL_BG,avsNormal));
  ACanvas.FrameRect(R,Theme.ColourFor(AROSA_ROLE_BORDER,avsNormal),ArosaCoord(2));
  if FResizable then
  begin
    { Standard retained-dialog resize grip. Keep it deliberately small so it
      does not steal space from the file requester footer. }
    C:=Theme.ColourFor(AROSA_ROLE_SECONDARY_TEXT,avsNormal);
    G:=ResizeHandleRect;
    for I:=0 to 2 do
      ACanvas.FillRect(ArosaRectXYWH(G.Right-ArosaCoord(4+I*4),
        G.Bottom-ArosaCoord(4),ArosaCoord(2),ArosaCoord(2)),C);
    for I:=1 to 2 do
      ACanvas.FillRect(ArosaRectXYWH(G.Right-ArosaCoord(4),
        G.Bottom-ArosaCoord(4+I*4),ArosaCoord(2),ArosaCoord(2)),C);
  end;
end;

procedure TAFMDialogSurface.ArrangeOverride(const AFinalSize: TArosaSize);
var W,H,L,T,MaxW,MaxH: TArosaCoord;
begin
  if FDialogPanel=nil then Exit;
  MaxW:=AFinalSize.Width-ArosaCoord(24);
  MaxH:=AFinalSize.Height-ArosaCoord(24);
  W:=ArosaCoord(FPreferredWidth); H:=ArosaCoord(FPreferredHeight);
  if W>MaxW then W:=MaxW;
  if H>MaxH then H:=MaxH;
  if W<ArosaCoord(280) then W:=MaxW;
  if H<ArosaCoord(180) then H:=MaxH;
  L:=(AFinalSize.Width-W) div 2;
  T:=(AFinalSize.Height-H) div 2;
  FDialogPanel.Arrange(RawRect(L,T,W,H));
end;

procedure TAFMDialogSurface.HandleInput(var AEvent: TArosaInputEvent);
var DX,DY: Integer;
begin
  if not Visible then Exit;

  if FResizable then
  begin
    if (AEvent.Kind=aieMouseDown) and (AEvent.Button=ambLeft) and
       ArosaRectContains(ResizeHandleRect,AEvent.Position) then
    begin
      FResizeDragging:=True;
      FResizeStartRoot:=AEvent.RootPosition;
      FResizeStartWidth:=FPreferredWidth;
      FResizeStartHeight:=FPreferredHeight;
      AEvent.Handled:=True;
      Exit;
    end;
    if FResizeDragging and (AEvent.Kind=aieMouseMove) then
    begin
      DX:=ArosaCoordWhole(AEvent.RootPosition.X-FResizeStartRoot.X);
      DY:=ArosaCoordWhole(AEvent.RootPosition.Y-FResizeStartRoot.Y);
      FPreferredWidth:=FResizeStartWidth+DX;
      FPreferredHeight:=FResizeStartHeight+DY;
      if FPreferredWidth<520 then FPreferredWidth:=520;
      if FPreferredHeight<340 then FPreferredHeight:=340;
      InvalidateLayout;
      InvalidatePaint;
      AEvent.Handled:=True;
      Exit;
    end;
    if FResizeDragging and (AEvent.Kind=aieMouseUp) then
    begin
      FResizeDragging:=False;
      AEvent.Handled:=True;
      Exit;
    end;
  end;

  if (AEvent.Kind=aieKeyDown) and (AEvent.KeyCode=27) then
  begin
    Dismiss;
    AEvent.Handled:=True;
  end;
end;

function TAFMDialogSurface.AcceptsFocus: Boolean;
begin
  Result:=Visible;
end;

function TAFileManagerConfigurationDialog.NewPage(ATabs: TArosaTabControl;
  const ACaption: string): TArosaColumnPanel;
var Page: TArosaTabPage;
begin
  Page:=TArosaTabPage.Create;
  Page.Caption:=ACaption;
  Page.Padding:=ArosaUniformMargins(10);
  ATabs.AddTabPage(Page);
  Result:=TArosaColumnPanel.Create;
  Result.Spacing:=ArosaCoord(7);
  Page.AddVisual(Result);
end;

procedure TAFileManagerConfigurationDialog.AddCheck(AParent: TArosaColumnPanel;
  ACheck: TArosaCheckBox);
begin
  ACheck.SetConstraintHeight(asmFixed,ArosaCoord(30));
  AParent.AddVisual(ACheck);
end;

procedure TAFileManagerConfigurationDialog.AddSlider(AParent: TArosaColumnPanel;
  const ACaption: string; ASlider: TArosaSlider; AValueLabel: TArosaLabel);
var Row: TArosaRowPanel; L: TArosaLabel;
begin
  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(Theme,FontCache);
  L.Text:=ACaption;
  L.SetConstraintWidth(asmFixed,ArosaCoord(170));
  Row.AddVisual(L);
  ASlider.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(ASlider);
  AValueLabel.SetConstraintWidth(asmFixed,ArosaCoord(54));
  Row.AddVisual(AValueLabel);
  AParent.AddVisual(Row);
end;

function TAFileManagerConfigurationDialog.LocalText(
  const AKey, AFallback: string): string;
begin
  if FLocalization<>nil then
    Result:=FLocalization.Text(AKey,AFallback)
  else
    Result:=AFallback;
end;

constructor TAFileManagerConfigurationDialog.CreateConfiguration(
  ATheme: TArosaTheme; AFonts: TArosaFontCache;
  const AClipboard: IArosaClipboardPlatform;
  ALocalization: TArosaLocalizationService);
var
  Title: TArosaLabel;
  Tabs: TArosaTabControl;
  General, View, ColumnsPage, FontsPage, ShortcutsPage, DiagnosticsPage, Startup: TArosaColumnPanel;
  Row: TArosaRowPanel;
  L: TArosaLabel;
begin
  inherited CreateDialog(ATheme,AFonts,760,640);
  FLocalization:=ALocalization;
  FControlFonts:=AFonts;
  FActiveFontRole:=affrText;

  Title:=TArosaLabel.CreateControl(ATheme,AFonts);
  Title.Text:=LocalText('afilemanager_config_title','AFileManager Configuration');
  Title.TextRole:=AROSA_ROLE_ACCENT;
  Title.SetConstraintHeight(asmFixed,ArosaCoord(30));
  Content.AddVisual(Title);

  Tabs:=TArosaTabControl.Create;
  Tabs.Font:=UIFont;
  Tabs.ActiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsPressed);
  Tabs.InactiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsNormal);
  Tabs.ActiveText:=ATheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT,avsNormal);
  Tabs.InactiveText:=ATheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT,avsNormal);
  Tabs.BorderColour:=ATheme.ColourFor(AROSA_ROLE_BORDER,avsNormal);
  Tabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  Content.AddVisual(Tabs);

  General:=NewPage(Tabs,LocalText('afilemanager_config_general','General'));
  FThemeCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FThemeCombo.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FThemeCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_theme','Theme');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  Row.AddVisual(FThemeCombo); General.AddVisual(Row);

  FAppearanceCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FAppearanceCombo.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FAppearanceCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  FAppearanceCombo.AddItem(LocalText('afilemanager_config_dark','Dark'));
  FAppearanceCombo.AddItem(LocalText('afilemanager_config_light','Light'));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_appearance','Appearance');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  Row.AddVisual(FAppearanceCombo); General.AddVisual(Row);

  FLanguageCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FLanguageCombo.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FLanguageCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_language','Interface language');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  Row.AddVisual(FLanguageCombo); General.AddVisual(Row);

  FToolbar:=TArosaCheckBox.CreateControl(ATheme,AFonts); FToolbar.Caption:=LocalText('afilemanager_config_show_toolbar','Show toolbar'); AddCheck(General,FToolbar);
  FOperations:=TArosaCheckBox.CreateControl(ATheme,AFonts); FOperations.Caption:=LocalText('afilemanager_config_show_operations','Show operations panel'); AddCheck(General,FOperations);
  FSplit:=TArosaCheckBox.CreateControl(ATheme,AFonts); FSplit.Caption:=LocalText('afilemanager_config_split_view','Split file view'); AddCheck(General,FSplit);
  FPreview:=TArosaCheckBox.CreateControl(ATheme,AFonts); FPreview.Caption:=LocalText('afilemanager_config_show_preview','Show preview panel'); AddCheck(General,FPreview);
  FEditorRendition:=TArosaCheckBox.CreateControl(ATheme,AFonts); FEditorRendition.Caption:=LocalText('afilemanager_config_editor_rendition','Show document rendition when editor opens'); AddCheck(General,FEditorRendition);
  FMetadata:=TArosaCheckBox.CreateControl(ATheme,AFonts); FMetadata.Caption:=LocalText('afilemanager_config_show_metadata','Show metadata panel'); AddCheck(General,FMetadata);
  FConfirmDelete:=TArosaCheckBox.CreateControl(ATheme,AFonts); FConfirmDelete.Caption:=LocalText('afilemanager_config_confirm_delete','Confirm deletion'); AddCheck(General,FConfirmDelete);

  { 0.10.6.2: drag and drop - item order = Move, Copy, Ask (DragRuleText) }
  FDragSameCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FDragSameCombo.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FDragSameCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDragSameCombo.AddItem(LocalText('afilemanager_config_drag_move','Move'));
  FDragSameCombo.AddItem(LocalText('afilemanager_config_drag_copy','Copy'));
  FDragSameCombo.AddItem(LocalText('afilemanager_config_drag_ask','Ask (Move / Copy menu)'));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_drag_same_volume','Drag within a volume');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  Row.AddVisual(FDragSameCombo); General.AddVisual(Row);

  FDragOtherCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FDragOtherCombo.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FDragOtherCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDragOtherCombo.AddItem(LocalText('afilemanager_config_drag_move','Move'));
  FDragOtherCombo.AddItem(LocalText('afilemanager_config_drag_copy','Copy'));
  FDragOtherCombo.AddItem(LocalText('afilemanager_config_drag_ask','Ask (Move / Copy menu)'));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_drag_other_volume','Drag to another volume');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  Row.AddVisual(FDragOtherCombo); General.AddVisual(Row);

  DiagnosticsPage:=NewPage(Tabs,LocalText('afilemanager_config_diagnostics','Diagnostics'));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_diagnostics_note',
    'AROSA records application diagnostics through the Logging Service. Normal preview logging uses Info and above.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(48));
  DiagnosticsPage.AddVisual(L);
  FLoggingEnabled:=TArosaCheckBox.CreateControl(ATheme,AFonts);
  FLoggingEnabled.Caption:=LocalText('afilemanager_config_logging_enabled','Enable diagnostic logging');
  AddCheck(DiagnosticsPage,FLoggingEnabled);
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_logging_level','Logging level');
  L.SetConstraintWidth(asmFixed,ArosaCoord(170)); Row.AddVisual(L);
  FLoggingLevel:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FLoggingLevel.SetConstraintHeight(asmFixed,ArosaCoord(30));
  FLoggingLevel.SetConstraintWidth(asmStar,ArosaCoord(1));
  FLoggingLevel.AddItem('Trace');
  FLoggingLevel.AddItem('Debug');
  FLoggingLevel.AddItem('Info');
  FLoggingLevel.AddItem('Warning');
  FLoggingLevel.AddItem('Error');
  FLoggingLevel.AddItem('Fatal');
  Row.AddVisual(FLoggingLevel); DiagnosticsPage.AddVisual(Row);
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_logging_launch_note',
    '--verbose temporarily requests Debug; --trace temporarily requests Trace for the current launch.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(44));
  DiagnosticsPage.AddVisual(L);

  View:=NewPage(Tabs,LocalText('afilemanager_config_file_view','File view'));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_default_view','Default view mode');
  L.SetConstraintHeight(asmFixed,ArosaCoord(24)); View.AddVisual(L);
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(32));
  FViewList:=TArosaRadioButton.CreateControl(ATheme,AFonts); FViewList.Caption:=LocalText('afilemanager_config_list','List');
  FViewList.GroupName:='default-view'; FViewList.SetConstraintWidth(asmFixed,ArosaCoord(110)); Row.AddVisual(FViewList);
  FViewDetails:=TArosaRadioButton.CreateControl(ATheme,AFonts); FViewDetails.Caption:=LocalText('afilemanager_config_details','Details');
  FViewDetails.GroupName:='default-view'; FViewDetails.SetConstraintWidth(asmFixed,ArosaCoord(110)); Row.AddVisual(FViewDetails);
  FViewIcons:=TArosaRadioButton.CreateControl(ATheme,AFonts); FViewIcons.Caption:=LocalText('afilemanager_config_icons','Icons');
  FViewIcons.GroupName:='default-view'; FViewIcons.SetConstraintWidth(asmFixed,ArosaCoord(110)); Row.AddVisual(FViewIcons);
  FViewWorkbench:=TArosaRadioButton.CreateControl(ATheme,AFonts); FViewWorkbench.Caption:=LocalText('afilemanager_config_workbench','Workbench');
  FViewWorkbench.GroupName:='default-view'; FViewWorkbench.SetConstraintWidth(asmFixed,ArosaCoord(130)); Row.AddVisual(FViewWorkbench);
  View.AddVisual(Row);

  { Thumbnail visibility is configured with the other List/Details columns
    on the dedicated Columns page. }
  FShowThumbnails:=nil;
  FThumbnailSize:=TArosaSlider.CreateControl(ATheme,AFonts);
  FThumbnailSize.Minimum:=12; FThumbnailSize.Maximum:=64; FThumbnailSize.OnChange:=@SliderChanged;
  FThumbnailSizeValue:=TArosaLabel.CreateControl(ATheme,AFonts);
  AddSlider(View,LocalText('afilemanager_config_thumbnail_size','Thumbnail size'),FThumbnailSize,FThumbnailSizeValue);

  FIconSize:=TArosaSlider.CreateControl(ATheme,AFonts); FIconSize.Minimum:=12; FIconSize.Maximum:=96; FIconSize.OnChange:=@SliderChanged;
  FIconSizeValue:=TArosaLabel.CreateControl(ATheme,AFonts);
  AddSlider(View,LocalText('afilemanager_config_icon_size','Icon size'),FIconSize,FIconSizeValue);
  FRowPadding:=TArosaSlider.CreateControl(ATheme,AFonts); FRowPadding.Minimum:=0; FRowPadding.Maximum:=24; FRowPadding.OnChange:=@SliderChanged;
  FRowPaddingValue:=TArosaLabel.CreateControl(ATheme,AFonts);
  AddSlider(View,LocalText('afilemanager_config_row_padding','Row padding'),FRowPadding,FRowPaddingValue);
  FIconGap:=TArosaSlider.CreateControl(ATheme,AFonts); FIconGap.Minimum:=0; FIconGap.Maximum:=48; FIconGap.OnChange:=@SliderChanged;
  FIconGapValue:=TArosaLabel.CreateControl(ATheme,AFonts);
  AddSlider(View,LocalText('afilemanager_config_icon_gap','Icon / text gap'),FIconGap,FIconGapValue);

  ColumnsPage:=NewPage(Tabs,
    LocalText('afilemanager_config_columns','Columns'));

  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_columns_note',
    'List and Details use the same column layout. Check columns to show them; drag rows to change their order.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(42));
  ColumnsPage.AddVisual(L);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_filter_columns','Filter');
  L.SetConstraintWidth(asmFixed,ArosaCoord(90));
  Row.AddVisual(L);
  FColumnFilter:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FColumnFilter.Multiline:=False;
  FColumnFilter.Clipboard:=AClipboard;
  FColumnFilter.OnChange:=@ColumnFilterChanged;
  FColumnFilter.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FColumnFilter);
  ColumnsPage.AddVisual(Row);

  FColumnList:=TArosaFilteredListView.CreateControl(ATheme,AFonts);
  FColumnList.SelectionMode:=alsSingle;
  FColumnList.HeaderVisible:=False;
  FColumnList.OnDragBegin:=@ColumnDragBegin;
  FColumnList.OnDragEnd:=@ColumnDragEnd;
  FColumnList.SetConstraintHeight(asmStar,ArosaCoord(1));
  ColumnsPage.AddVisual(FColumnList);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FColumnMoveUp:=TArosaButton.CreateControl(ATheme,AFonts);
  FColumnMoveUp.Caption:=LocalText('afilemanager_config_move_up','Move up');
  FColumnMoveUp.OnClick:=@ColumnMoveUpClick;
  FColumnMoveUp.SetConstraintWidth(asmFixed,ArosaCoord(110));
  Row.AddVisual(FColumnMoveUp);
  FColumnMoveDown:=TArosaButton.CreateControl(ATheme,AFonts);
  FColumnMoveDown.Caption:=LocalText('afilemanager_config_move_down','Move down');
  FColumnMoveDown.OnClick:=@ColumnMoveDownClick;
  FColumnMoveDown.SetConstraintWidth(asmFixed,ArosaCoord(110));
  Row.AddVisual(FColumnMoveDown);
  ColumnsPage.AddVisual(Row);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_default_sort_column',
    'Default sort column');
  L.SetConstraintWidth(asmFixed,ArosaCoord(180));
  Row.AddVisual(L);
  FDefaultSortCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FDefaultSortCombo.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FDefaultSortCombo);
  ColumnsPage.AddVisual(Row);

  FDefaultSortAscending:=TArosaCheckBox.CreateControl(ATheme,AFonts);
  FDefaultSortAscending.Caption:=
    LocalText('afilemanager_config_sort_ascending','Sort ascending');
  AddCheck(ColumnsPage,FDefaultSortAscending);

  InitializeColumns;
  RebuildColumnList;
  RebuildSortChoices;

  FontsPage:=NewPage(Tabs,LocalText('afilemanager_config_fonts','Fonts'));

  { AFileManager consumes the standard AROSA Font Picker once, and exposes
    explicit application roles around it. This avoids nested tab controls and
    makes every role visible even before the picker is opened. }
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FFontRoleLabels[affrText]:=TArosaLabel.CreateControl(ATheme,AFonts);
  L:=FFontRoleLabels[affrText]; L.Text:=LocalText('afilemanager_config_font_application','Application text');
  L.SetConstraintWidth(asmFixed,ArosaCoord(190)); Row.AddVisual(L);
  FFontValueLabels[affrText]:=TArosaLabel.CreateControl(ATheme,AFonts);
  FFontValueLabels[affrText].SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FFontValueLabels[affrText]);
  FFontSelectButtons[affrText]:=TArosaButton.CreateControl(ATheme,AFonts);
  FFontSelectButtons[affrText].Caption:=LocalText('afilemanager_config_select','Select...'); FFontSelectButtons[affrText].OnClick:=@TextFontClick;
  FFontSelectButtons[affrText].SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FFontSelectButtons[affrText]);
  FontsPage.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FFontRoleLabels[affrLists]:=TArosaLabel.CreateControl(ATheme,AFonts);
  L:=FFontRoleLabels[affrLists]; L.Text:=LocalText('afilemanager_config_font_lists','File lists / paths');
  L.SetConstraintWidth(asmFixed,ArosaCoord(190)); Row.AddVisual(L);
  FFontValueLabels[affrLists]:=TArosaLabel.CreateControl(ATheme,AFonts);
  FFontValueLabels[affrLists].SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FFontValueLabels[affrLists]);
  FFontSelectButtons[affrLists]:=TArosaButton.CreateControl(ATheme,AFonts);
  FFontSelectButtons[affrLists].Caption:=LocalText('afilemanager_config_select','Select...'); FFontSelectButtons[affrLists].OnClick:=@ListsFontClick;
  FFontSelectButtons[affrLists].SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FFontSelectButtons[affrLists]);
  FontsPage.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FFontRoleLabels[affrConsole]:=TArosaLabel.CreateControl(ATheme,AFonts);
  L:=FFontRoleLabels[affrConsole]; L.Text:=LocalText('afilemanager_config_font_console','Console / editor');
  L.SetConstraintWidth(asmFixed,ArosaCoord(190)); Row.AddVisual(L);
  FFontValueLabels[affrConsole]:=TArosaLabel.CreateControl(ATheme,AFonts);
  FFontValueLabels[affrConsole].SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FFontValueLabels[affrConsole]);
  FFontSelectButtons[affrConsole]:=TArosaButton.CreateControl(ATheme,AFonts);
  FFontSelectButtons[affrConsole].Caption:=LocalText('afilemanager_config_select','Select...'); FFontSelectButtons[affrConsole].OnClick:=@ConsoleFontClick;
  FFontSelectButtons[affrConsole].SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FFontSelectButtons[affrConsole]);
  FontsPage.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FFontRoleLabels[affrHelp]:=TArosaLabel.CreateControl(ATheme,AFonts);
  L:=FFontRoleLabels[affrHelp]; L.Text:=LocalText('afilemanager_config_font_help','Help / documents');
  L.SetConstraintWidth(asmFixed,ArosaCoord(190)); Row.AddVisual(L);
  FFontValueLabels[affrHelp]:=TArosaLabel.CreateControl(ATheme,AFonts);
  FFontValueLabels[affrHelp].SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FFontValueLabels[affrHelp]);
  FFontSelectButtons[affrHelp]:=TArosaButton.CreateControl(ATheme,AFonts);
  FFontSelectButtons[affrHelp].Caption:=LocalText('afilemanager_config_select','Select...'); FFontSelectButtons[affrHelp].OnClick:=@HelpFontClick;
  FFontSelectButtons[affrHelp].SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FFontSelectButtons[affrHelp]);
  FontsPage.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FFontRoleLabels[affrInfo]:=TArosaLabel.CreateControl(ATheme,AFonts);
  L:=FFontRoleLabels[affrInfo]; L.Text:=LocalText('afilemanager_config_font_info','Information / credits');
  L.SetConstraintWidth(asmFixed,ArosaCoord(190)); Row.AddVisual(L);
  FFontValueLabels[affrInfo]:=TArosaLabel.CreateControl(ATheme,AFonts);
  FFontValueLabels[affrInfo].SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FFontValueLabels[affrInfo]);
  FFontSelectButtons[affrInfo]:=TArosaButton.CreateControl(ATheme,AFonts);
  FFontSelectButtons[affrInfo].Caption:=LocalText('afilemanager_config_select','Select...'); FFontSelectButtons[affrInfo].OnClick:=@InfoFontClick;
  FFontSelectButtons[affrInfo].SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FFontSelectButtons[affrInfo]);
  FontsPage.AddVisual(Row);

  FFontPickerGroup:=TArosaGroupBox.CreateControl(ATheme,AFonts);
  FFontPickerGroup.Caption:=LocalText('afilemanager_config_font_selector','Font selector');
  { Keep the picker fully inside the configuration surface on the 800-line
    AROS preview screen.  The picker reserves its own final row for the
    discrete bitmap-size controls. }
  FFontPickerGroup.SetConstraintHeight(asmFixed,ArosaCoord(320));

  FFontPicker:=TArosaFontPicker.Create;
  FFontPicker.SetTheme(ATheme,AFonts);
  FFontPicker.ShowStyles:=False;
  FFontPicker.PreviewText:='AFileManager  AaBbGg  0123456789';
  FFontPicker.OnChanged:=@FontPickerChanged;
  FFontPicker.SetConstraintHeight(asmStar,ArosaCoord(1));
  FFontPickerGroup.AddVisual(FFontPicker);

  { Select... is the explicit entry point.  Until a role is selected the
    picker stays hidden, so it cannot be mistaken for an unlabelled global
    font setting. }
  FFontPickerGroup.Visible:=False;
  FontsPage.AddVisual(FFontPickerGroup);

  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_font_note','Select a role, choose an installed font and size. Apply previews it immediately; Save also persists it.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(36)); FontsPage.AddVisual(L);

  ShortcutsPage:=NewPage(Tabs,
    LocalText('afilemanager_config_shortcuts','Shortcuts'));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_shortcuts_note',
    'Filter commands, then edit the shortcut. Original shows the descriptor default.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(34));
  ShortcutsPage.AddVisual(L);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_filter_shortcuts','Filter');
  L.SetConstraintWidth(asmFixed,ArosaCoord(90));
  Row.AddVisual(L);
  FShortcutFilter:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FShortcutFilter.Multiline:=False;
  FShortcutFilter.Clipboard:=AClipboard;
  FShortcutFilter.OnChange:=@ShortcutFilterChanged;
  FShortcutFilter.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FShortcutFilter);
  FShortcutRestore:=TArosaButton.CreateControl(ATheme,AFonts);
  FShortcutRestore.Caption:=LocalText('afilemanager_config_restore_shortcuts','Restore defaults');
  FShortcutRestore.OnClick:=@ShortcutRestoreClick;
  FShortcutRestore.SetConstraintWidth(asmFixed,ArosaCoord(150));
  Row.AddVisual(FShortcutRestore);
  ShortcutsPage.AddVisual(Row);

  FShortcutList:=TAFMShortcutListView.CreateControl(ATheme,AFonts);
  FShortcutList.SelectionMode:=alsSingle;
  FShortcutList.HeaderVisible:=True;
  FShortcutList.AddColumn('command',
    LocalText('afilemanager_config_shortcut_command','Command'),
    ArosaCoord(430));
  FShortcutList.AddColumn('original',
    LocalText('afilemanager_config_shortcut_original','Original'),
    ArosaCoord(180));
  FShortcutList.AddColumn('shortcut',
    LocalText('afilemanager_config_shortcut_current','Shortcut'),
    ArosaCoord(250));
  FShortcutList.SetConstraintHeight(asmStar,ArosaCoord(1));
  ShortcutsPage.AddVisual(FShortcutList);

  Startup:=NewPage(Tabs,LocalText('afilemanager_config_startup','Startup'));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_startup_descriptor','Startup descriptor');
  L.SetConstraintHeight(asmFixed,ArosaCoord(24)); Startup.AddVisual(L);
  FDescriptorCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FDescriptorCombo.SetConstraintHeight(asmFixed,ArosaCoord(34)); Startup.AddVisual(FDescriptorCombo);
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_config_user_profile','User profile');
  L.SetConstraintHeight(asmFixed,ArosaCoord(24)); Startup.AddVisual(L);
  FProfileCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FProfileCombo.SetConstraintHeight(asmFixed,ArosaCoord(34)); Startup.AddVisual(FProfileCombo);
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_config_startup_note','Save sets the launcher defaults. Descriptor/profile changes take effect on the next launch.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT; L.SetConstraintHeight(asmFixed,ArosaCoord(44)); Startup.AddVisual(L);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FApplyButton:=TArosaButton.CreateControl(ATheme,AFonts); FApplyButton.Caption:=LocalText('afilemanager_config_apply','Apply'); FApplyButton.OnClick:=@ApplyClick; FApplyButton.SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FApplyButton);
  FSaveButton:=TArosaButton.CreateControl(ATheme,AFonts); FSaveButton.Caption:=LocalText('afilemanager_config_save','Save'); FSaveButton.OnClick:=@SaveClick; FSaveButton.SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FSaveButton);
  FCancelButton:=TArosaButton.CreateControl(ATheme,AFonts); FCancelButton.Caption:=LocalText('afilemanager_config_cancel','Cancel'); FCancelButton.OnClick:=@CancelClick; FCancelButton.SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FCancelButton);
  Content.AddVisual(Row);

  { Keep the platform clipboard contract available to every text control added
    to this dialog in future revisions.  Current controls do not need it yet. }
  if AClipboard=nil then ;
end;

function TAFileManagerConfigurationDialog.ShortcutCommandCaption(
  const ACommand: string): string;
begin
  if SameText(ACommand,'View.NewFileManager') then
    Exit(LocalText('afilemanager_action_new_file_manager','New file manager'));
  if SameText(ACommand,'View.CloseFileManager') then
    Exit(LocalText('afilemanager_action_close_file_manager','Close file manager'));
  if SameText(ACommand,'Navigation.Back') then
    Exit(LocalText('afilemanager_action_back','Back'));
  if SameText(ACommand,'Navigation.Forward') then
    Exit(LocalText('afilemanager_action_forward','Forward'));
  if SameText(ACommand,'Navigation.Refresh') then
    Exit(LocalText('afilemanager_action_refresh','Refresh'));
  if SameText(ACommand,'Selection.All') then
    Exit(LocalText('afilemanager_action_select_all','Select all'));
  if SameText(ACommand,'Selection.None') then
    Exit(LocalText('afilemanager_action_select_none','Clear selection'));
  if SameText(ACommand,'Resource.Copy') then
    Exit(LocalText('afilemanager_action_copy','Copy'));
  if SameText(ACommand,'Resource.Cut') then
    Exit(LocalText('afilemanager_action_cut','Cut'));
  if SameText(ACommand,'Resource.Paste') then
    Exit(LocalText('afilemanager_action_paste','Paste'));
  if SameText(ACommand,'File.Delete') or SameText(ACommand,'Resource.Delete') then
    Exit(LocalText('afilemanager_action_delete','Delete'));
  if SameText(ACommand,'Resource.Rename') then
    Exit(LocalText('afilemanager_action_rename','Rename'));
  if SameText(ACommand,'Resource.CreateFolder') then
    Exit(LocalText('afilemanager_action_create_folder','Create folder'));
  if SameText(ACommand,'Resource.CreateFile') then
    Exit(LocalText('afilemanager_action_create_file','Create file'));
  if SameText(ACommand,'History.Undo') then
    Exit(LocalText('afilemanager_action_undo','Undo'));
  if SameText(ACommand,'Help.Contents') then
    Exit(LocalText('afilemanager_menu_help','Help'));
  Result:=ACommand;
end;

procedure TAFileManagerConfigurationDialog.RebuildShortcutList(
  const ACurrent, ADefaults: string);
var
  Current, Defaults, Commands: TStringList;
  I, J: Integer;
  Key, Cmd, OriginalKey, CurrentKey: string;
  Row: TArosaListRow;
  NameLabel, OriginalLabel: TArosaLabel;
  CurrentLabel: TArosaLabel;

  procedure AddCommand(const ACommand: string);
  begin
    if (Trim(ACommand)<>'') and (ACommand<>'-') and
       (Commands.IndexOf(ACommand)<0) then Commands.Add(ACommand);
  end;

  function KeyForCommand(AList: TStringList; const ACommand: string): string;
  var K: Integer;
  begin
    Result:='';
    for K:=0 to AList.Count-1 do
      if SameText(Trim(AList.ValueFromIndex[K]),ACommand) then
        Exit(Trim(AList.Names[K]));
  end;
begin
  if FShortcutList=nil then Exit;
  Current:=TStringList.Create;
  Defaults:=TStringList.Create;
  Commands:=TStringList.Create;
  try
    Current.NameValueSeparator:='=';
    Defaults.NameValueSeparator:='=';
    Current.Text:=ACurrent;
    Defaults.Text:=ADefaults;
    Commands.CaseSensitive:=False;
    Commands.Sorted:=False;

    for I:=0 to Defaults.Count-1 do AddCommand(Trim(Defaults.ValueFromIndex[I]));
    for I:=0 to Current.Count-1 do AddCommand(Trim(Current.ValueFromIndex[I]));

    FShortcutList.Clear;
    for I:=0 to Commands.Count-1 do
    begin
      Cmd:=Commands[I];
      OriginalKey:=KeyForCommand(Defaults,Cmd);
      CurrentKey:=KeyForCommand(Current,Cmd);
      if CurrentKey='' then CurrentKey:=OriginalKey;

      Row:=TArosaListRow.Create;
      Row.Text:=Cmd;
      Row.SearchText:=ShortcutCommandCaption(Cmd)+' '+Cmd+' '+OriginalKey;

      NameLabel:=TArosaLabel.CreateControl(Theme,FControlFonts);
      NameLabel.Text:=ShortcutCommandCaption(Cmd);
      NameLabel.Hint:=Cmd;
      NameLabel.SetConstraintWidth(asmFixed,ArosaCoord(430));
      Row.AddObject(NameLabel);

      OriginalLabel:=TArosaLabel.CreateControl(Theme,FControlFonts);
      OriginalLabel.Text:=OriginalKey;
      OriginalLabel.SetConstraintWidth(asmFixed,ArosaCoord(180));
      Row.AddObject(OriginalLabel);

      CurrentLabel:=TArosaLabel.CreateControl(Theme,FControlFonts);
      CurrentLabel.Text:=CurrentKey;
      CurrentLabel.SetConstraintWidth(asmStar,ArosaCoord(1));
      Row.AddObject(CurrentLabel);

      FShortcutList.AddRow(Row);
    end;
    if FShortcutFilter<>nil then FShortcutList.Filter:=FShortcutFilter.Text;
  finally
    Commands.Free;
    Defaults.Free;
    Current.Free;
  end;
end;

procedure TAFileManagerConfigurationDialog.ShortcutFilterChanged(
  ASender: TArosaControl);
begin
  if (FShortcutList<>nil) and (FShortcutFilter<>nil) then
    FShortcutList.Filter:=FShortcutFilter.Text;
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.ShortcutRestoreClick(
  ASender: TArosaControl);
var
  I: Integer;
  Row: TArosaListRow;
  OriginalLabel: TArosaLabel;
  CurrentLabel: TArosaLabel;
begin
  if FShortcutList=nil then Exit;
  FShortcutList.EndShortcutEdit;
  for I:=0 to FShortcutList.RowCount-1 do
  begin
    Row:=FShortcutList.Rows[I];
    if (Row=nil) or (Row.ObjectCount<3) then Continue;
    if not (Row.Objects[1] is TArosaLabel) then Continue;
    if not (Row.Objects[2] is TArosaLabel) then Continue;
    OriginalLabel:=TArosaLabel(Row.Objects[1]);
    CurrentLabel:=TArosaLabel(Row.Objects[2]);
    CurrentLabel.Text:=OriginalLabel.Text;
  end;
  if ASender=nil then ;
end;

function TAFileManagerConfigurationDialog.ShortcutBindingsText: string;
var
  OutList: TStringList;
  I: Integer;
  Row: TArosaListRow;
  OriginalLabel: TArosaLabel;
  CurrentLabel: TArosaLabel;
  Cmd, OriginalKey, CurrentKey: string;
begin
  Result:='';
  if FShortcutList=nil then Exit;
  OutList:=TStringList.Create;
  try
    OutList.NameValueSeparator:='=';
    for I:=0 to FShortcutList.RowCount-1 do
    begin
      Row:=FShortcutList.Rows[I];
      if (Row=nil) or (Row.ObjectCount<3) then Continue;
      if not (Row.Objects[1] is TArosaLabel) then Continue;
      if not (Row.Objects[2] is TArosaLabel) then Continue;
      Cmd:=Trim(Row.Text);
      OriginalLabel:=TArosaLabel(Row.Objects[1]);
      CurrentLabel:=TArosaLabel(Row.Objects[2]);
      OriginalKey:=Trim(OriginalLabel.Text);
      CurrentKey:=Trim(CurrentLabel.Text);
      { A changed/cleared default key must be explicitly disabled in the user
        overlay or descriptor inheritance would make it active again. }
      if (OriginalKey<>'') and (not SameText(OriginalKey,CurrentKey)) then
        OutList.Add(OriginalKey+'=-');
      if (CurrentKey<>'') and (Cmd<>'') then
        OutList.Add(CurrentKey+'='+Cmd);
    end;
    Result:=OutList.Text;
  finally
    OutList.Free;
  end;
end;

procedure TAFileManagerConfigurationDialog.UpdateValueLabels;
begin
  if FThumbnailSizeValue<>nil then FThumbnailSizeValue.Text:=IntToStr(FThumbnailSize.Value)+' px';
  FIconSizeValue.Text:=IntToStr(FIconSize.Value)+' px';
  FRowPaddingValue.Text:=IntToStr(FRowPadding.Value)+' px';
  FIconGapValue.Text:=IntToStr(FIconGap.Value)+' px';
end;

procedure TAFileManagerConfigurationDialog.SliderChanged(ASender: TArosaControl;
  AValue: Integer);
begin
  UpdateValueLabels;
  if ASender=nil then ;
  if AValue<0 then ;
end;

function TAFileManagerConfigurationDialog.CurrentSettings: TAFMConfigurationSettings;
begin
  { Save/Apply must commit the editor that is currently open even if the user
    presses Save immediately after changing family or size. }
  if (FFontPicker<>nil) and (FFontPickerGroup<>nil) and
     FFontPickerGroup.Visible then
  begin
    FFontSelections[FActiveFontRole]:=FFontPicker.Selection;
    UpdateFontRoleLabel(FActiveFontRole);
  end;
  { Every field is assigned below.  Do not FillChar records containing
    managed strings. }
  Result.ThemePackageId:=FThemeCombo.SelectedText;
  if Trim(Result.ThemePackageId)='' then Result.ThemePackageId:='default';
  if FAppearanceCombo.SelectedIndex=1 then Result.ThemeId:='Light' else Result.ThemeId:='Dark';
  Result.InterfaceLanguage:=FLanguageCombo.SelectedText;
  if Trim(Result.InterfaceLanguage)='' then Result.InterfaceLanguage:='System';
  Result.ToolbarVisible:=FToolbar.Checked;
  Result.OperationsVisible:=FOperations.Checked;
  Result.SplitView:=FSplit.Checked;
  Result.PreviewVisible:=FPreview.Checked;
  Result.EditorRenditionVisible:=FEditorRendition.Checked;
  Result.MetadataVisible:=FMetadata.Checked;
  Result.ConfirmDeletion:=FConfirmDelete.Checked;
  Result.DragSameVolume:=DragRuleText(FDragSameCombo.SelectedIndex,'Move');
  Result.DragOtherVolume:=DragRuleText(FDragOtherCombo.SelectedIndex,'Copy');
  Result.LoggingEnabled:=FLoggingEnabled.Checked;
  Result.LoggingLevel:=FLoggingLevel.SelectedText;
  if Trim(Result.LoggingLevel)='' then Result.LoggingLevel:='Info';
  Result.ColumnOrder:=ColumnOrderText;
  Result.VisibleColumns:=VisibleColumnsText;
  Result.ShowThumbnails:=Pos(',resource.thumbnail,',
    ','+LowerCase(Result.VisibleColumns)+',')>0;
  Result.DefaultSortColumn:=FDefaultSortCombo.SelectedText;
  if Trim(Result.DefaultSortColumn)='' then Result.DefaultSortColumn:='resource.name';
  Result.DefaultSortAscending:=FDefaultSortAscending.Checked;
  Result.ThumbnailSize:=FThumbnailSize.Value;
  Result.IconSize:=FIconSize.Value;
  Result.RowPadding:=FRowPadding.Value;
  Result.IconTextGap:=FIconGap.Value;
  if FViewWorkbench.Checked then Result.DefaultViewMode:='Workbench'
  else if FViewIcons.Checked then Result.DefaultViewMode:='Icons'
  else if FViewList.Checked then Result.DefaultViewMode:='List'
  else Result.DefaultViewMode:='Details';
  Result.DefaultDescriptor:=FDescriptorCombo.SelectedText;
  Result.UserProfile:=FProfileCombo.SelectedText;
  Result.UIFontFamily:=FFontSelections[affrText].Family;
  Result.UIFontSize:=FFontSelections[affrText].SizePoints;
  Result.FileFontFamily:=FFontSelections[affrLists].Family;
  Result.FileFontSize:=FFontSelections[affrLists].SizePoints;
  Result.FixedFontFamily:=FFontSelections[affrConsole].Family;
  Result.FixedFontSize:=FFontSelections[affrConsole].SizePoints;
  Result.DocumentFontFamily:=FFontSelections[affrHelp].Family;
  Result.DocumentFontSize:=FFontSelections[affrHelp].SizePoints;
  Result.InfoFontFamily:=FFontSelections[affrInfo].Family;
  Result.InfoFontSize:=FFontSelections[affrInfo].SizePoints;
  Result.ShortcutBindings:=ShortcutBindingsText;
  Result.DefaultShortcutBindings:=FDefaultShortcutBindings;
end;

procedure TAFileManagerConfigurationDialog.ApplyClick(ASender: TArosaControl);
var S: TAFMConfigurationSettings;
begin
  S:=CurrentSettings;
  if Assigned(FOnApply) then FOnApply(Self,S,False);
  { Apply is a runtime test, not persistence. Close the modal so the user can
    inspect the whole application under the temporary configuration. }
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.SaveClick(ASender: TArosaControl);
var S: TAFMConfigurationSettings;
begin
  S:=CurrentSettings;
  if Assigned(FOnApply) then FOnApply(Self,S,True);
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.CancelClick(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.ShowSettings(
  const ASettings: TAFMConfigurationSettings);
var I: Integer;
begin
  I:=FThemeCombo.IndexOf(ASettings.ThemePackageId);
  if I<0 then begin FThemeCombo.AddItem(ASettings.ThemePackageId); I:=FThemeCombo.IndexOf(ASettings.ThemePackageId); end;
  if I<0 then I:=0;
  FThemeCombo.SelectedIndex:=I;
  I:=FAppearanceCombo.IndexOf(ASettings.ThemeId);
  if I<0 then I:=0;
  FAppearanceCombo.SelectedIndex:=I;
  I:=FLanguageCombo.IndexOf(ASettings.InterfaceLanguage);
  if I<0 then begin FLanguageCombo.AddItem(ASettings.InterfaceLanguage); I:=FLanguageCombo.IndexOf(ASettings.InterfaceLanguage); end;
  if I<0 then I:=0;
  FLanguageCombo.SelectedIndex:=I;
  FToolbar.Checked:=ASettings.ToolbarVisible;
  FOperations.Checked:=ASettings.OperationsVisible;
  FSplit.Checked:=ASettings.SplitView;
  FPreview.Checked:=ASettings.PreviewVisible;
  FEditorRendition.Checked:=ASettings.EditorRenditionVisible;
  FMetadata.Checked:=ASettings.MetadataVisible;
  FConfirmDelete.Checked:=ASettings.ConfirmDeletion;
  FDragSameCombo.SelectedIndex:=DragRuleIndex(ASettings.DragSameVolume,0);
  FDragOtherCombo.SelectedIndex:=DragRuleIndex(ASettings.DragOtherVolume,1);
  FLoggingEnabled.Checked:=ASettings.LoggingEnabled;
  I:=FLoggingLevel.IndexOf(ASettings.LoggingLevel);
  if I<0 then I:=FLoggingLevel.IndexOf('Info');
  if I<0 then I:=0;
  FLoggingLevel.SelectedIndex:=I;
  LoadColumnConfiguration(ASettings.ColumnOrder,ASettings.VisibleColumns);
  { Preserve compatibility with older profiles that only carried
    FileView.ShowThumbnails. }
  I:=ColumnIndexById('resource.thumbnail');
  if (I>=0) and (Trim(ASettings.VisibleColumns)='') then
    FColumns[I].Visible:=ASettings.ShowThumbnails;
  RebuildColumnList;
  RebuildSortChoices;
  I:=FDefaultSortCombo.IndexOf(ASettings.DefaultSortColumn);
  if I<0 then I:=FDefaultSortCombo.IndexOf('resource.name');
  if I<0 then I:=0;
  FDefaultSortCombo.SelectedIndex:=I;
  FDefaultSortAscending.Checked:=ASettings.DefaultSortAscending;
  FThumbnailSize.Value:=ASettings.ThumbnailSize;
  FIconSize.Value:=ASettings.IconSize;
  FRowPadding.Value:=ASettings.RowPadding;
  FIconGap.Value:=ASettings.IconTextGap;
  FViewList.Checked:=SameText(ASettings.DefaultViewMode,'List');
  FViewIcons.Checked:=SameText(ASettings.DefaultViewMode,'Icons');
  FViewWorkbench.Checked:=SameText(ASettings.DefaultViewMode,'Workbench') or
    SameText(ASettings.DefaultViewMode,'Windows');
  FViewDetails.Checked:=not FViewList.Checked and not FViewIcons.Checked and
    not FViewWorkbench.Checked;
  I:=FDescriptorCombo.IndexOf(ASettings.DefaultDescriptor);
  if I<0 then begin FDescriptorCombo.AddItem(ASettings.DefaultDescriptor); I:=FDescriptorCombo.IndexOf(ASettings.DefaultDescriptor); end;
  if I<0 then I:=0; FDescriptorCombo.SelectedIndex:=I;
  I:=FProfileCombo.IndexOf(ASettings.UserProfile);
  if I<0 then begin FProfileCombo.AddItem(ASettings.UserProfile); I:=FProfileCombo.IndexOf(ASettings.UserProfile); end;
  if I<0 then I:=0; FProfileCombo.SelectedIndex:=I;

  FFontSelections[affrText]:=ArosaFontDescription(ASettings.UIFontFamily,ASettings.UIFontSize,afwNormal);
  FFontSelections[affrLists]:=ArosaFontDescription(ASettings.FileFontFamily,ASettings.FileFontSize,afwNormal);
  FFontSelections[affrConsole]:=ArosaFontDescription(ASettings.FixedFontFamily,ASettings.FixedFontSize,afwNormal,False,True);
  FFontSelections[affrHelp]:=ArosaFontDescription(ASettings.DocumentFontFamily,ASettings.DocumentFontSize,afwNormal);
  FFontSelections[affrInfo]:=ArosaFontDescription(ASettings.InfoFontFamily,ASettings.InfoFontSize,afwNormal);
  UpdateFontRoleLabel(affrText);
  UpdateFontRoleLabel(affrLists);
  UpdateFontRoleLabel(affrConsole);
  UpdateFontRoleLabel(affrHelp);
  UpdateFontRoleLabel(affrInfo);
  FActiveFontRole:=affrText;
  if FFontPickerGroup<>nil then FFontPickerGroup.Visible:=False;
  FDefaultShortcutBindings:=ASettings.DefaultShortcutBindings;
  RebuildShortcutList(ASettings.ShortcutBindings,ASettings.DefaultShortcutBindings);
  UpdateValueLabels;
  ShowDialog;
end;

procedure TAFileManagerConfigurationDialog.InitializeColumns;
  procedure Add(const AId, ACaption: string; AVisible: Boolean);
  begin
    if FColumnCount>=Length(FColumns) then
    begin
      if Length(FColumns)=0 then SetLength(FColumns,8)
      else SetLength(FColumns,Length(FColumns)*2);
    end;
    FColumns[FColumnCount].Id:=AId;
    FColumns[FColumnCount].Caption:=ACaption;
    FColumns[FColumnCount].Visible:=AVisible;
    Inc(FColumnCount);
  end;
begin
  FColumnCount:=0;
  SetLength(FColumns,8);
  Add('resource.thumbnail',
    LocalText('afilemanager_column_thumbnail','Thumbnail'),True);
  Add('resource.type',
    LocalText('afilemanager_column_type','Type'),True);
  Add('resource.name',
    LocalText('afilemanager_column_name','Name'),True);
  Add('resource.size',
    LocalText('afilemanager_column_size','Size'),True);
  Add('resource.modified',
    LocalText('afilemanager_column_modified','Date modified'),True);
  Add('resource.permissions',
    LocalText('afilemanager_column_permissions','Permissions'),True);
end;

function TAFileManagerConfigurationDialog.ColumnIndexById(
  const AId: string): Integer;
var I: Integer;
begin
  Result:=-1;
  for I:=0 to FColumnCount-1 do
    if SameText(FColumns[I].Id,AId) then Exit(I);
end;

procedure TAFileManagerConfigurationDialog.RebuildColumnList(
  ASelectIndex: Integer);
var
  I: Integer;
  R: TArosaListRow;
  C: TArosaCheckBox;
  L: TArosaLabel;
begin
  if FColumnList=nil then Exit;
  FColumnList.Clear;
  for I:=0 to FColumnCount-1 do
  begin
    R:=FColumnList.NewRow(FColumns[I].Id);
    R.SearchText:=FColumns[I].Caption;
    C:=TArosaCheckBox.CreateControl(Theme,FControlFonts);
    C.Caption:='';
    C.Checked:=FColumns[I].Visible;
    C.OnChange:=@ColumnVisibilityChanged;
    C.SetConstraintWidth(asmFixed,ArosaCoord(34));
    R.AddObject(C);
    L:=TArosaLabel.CreateControl(Theme,FControlFonts);
    L.Text:=FColumns[I].Caption;
    L.SetConstraintWidth(asmStar,ArosaCoord(1));
    R.AddObject(L);
  end;

  if FColumnFilter<>nil then FColumnList.SetFilter(FColumnFilter.Text);
  if (ASelectIndex>=0) and (ASelectIndex<FColumnList.ItemCount) then
    FColumnList.SelectItem(ASelectIndex);
end;

procedure TAFileManagerConfigurationDialog.RebuildSortChoices;
var
  I, Selected: Integer;
  Current: string;
begin
  if FDefaultSortCombo=nil then Exit;
  Current:=FDefaultSortCombo.SelectedText;
  FDefaultSortCombo.ClearItems;
  for I:=0 to FColumnCount-1 do
    if not SameText(FColumns[I].Id,'resource.thumbnail') then
      FDefaultSortCombo.AddItem(FColumns[I].Id);

  Selected:=FDefaultSortCombo.IndexOf(Current);
  if Selected<0 then Selected:=FDefaultSortCombo.IndexOf('resource.name');
  if Selected<0 then Selected:=0;
  FDefaultSortCombo.SelectedIndex:=Selected;
end;

procedure TAFileManagerConfigurationDialog.ColumnFilterChanged(
  ASender: TArosaControl);
begin
  if (FColumnList<>nil) and (FColumnFilter<>nil) then
    FColumnList.SetFilter(FColumnFilter.Text);
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.ColumnVisibilityChanged(
  ASender: TArosaControl);
var
  I, J, ColumnIndex: Integer;
  R: TArosaListRow;
begin
  if (FColumnList=nil) or not (ASender is TArosaCheckBox) then Exit;
  for I:=0 to FColumnList.ItemCount-1 do
  begin
    R:=FColumnList.VisibleRowsView[I];
    for J:=0 to R.ObjectCount-1 do
      if R.Objects[J]=ASender then
      begin
        ColumnIndex:=ColumnIndexById(R.Text);
        if ColumnIndex>=0 then
        begin
          { Name is the stable identity column and remains mandatory. }
          if SameText(FColumns[ColumnIndex].Id,'resource.name') then
          begin
            FColumns[ColumnIndex].Visible:=True;
            TArosaCheckBox(ASender).Checked:=True;
          end
          else
            FColumns[ColumnIndex].Visible:=TArosaCheckBox(ASender).Checked;
        end;
        Exit;
      end;
  end;
end;

procedure TAFileManagerConfigurationDialog.MoveColumn(AFrom, ATo: Integer);
var
  T: TAFMColumnConfiguration;
begin
  if (AFrom<0) or (AFrom>=FColumnCount) or
     (ATo<0) or (ATo>=FColumnCount) or (AFrom=ATo) then Exit;
  T:=FColumns[AFrom];
  if AFrom<ATo then
  begin
    while AFrom<ATo do
    begin
      FColumns[AFrom]:=FColumns[AFrom+1];
      Inc(AFrom);
    end;
  end
  else
  begin
    while AFrom>ATo do
    begin
      FColumns[AFrom]:=FColumns[AFrom-1];
      Dec(AFrom);
    end;
  end;
  FColumns[ATo]:=T;
  RebuildColumnList(ATo);
  RebuildSortChoices;
end;

procedure TAFileManagerConfigurationDialog.ColumnMoveUpClick(
  ASender: TArosaControl);
var
  R: TArosaListRow;
  I: Integer;
begin
  if (FColumnList=nil) or (FColumnList.SelectedRow=nil) then Exit;
  R:=FColumnList.SelectedRow;
  I:=ColumnIndexById(R.Text);
  if I>0 then MoveColumn(I,I-1);
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.ColumnMoveDownClick(
  ASender: TArosaControl);
var
  R: TArosaListRow;
  I: Integer;
begin
  if (FColumnList=nil) or (FColumnList.SelectedRow=nil) then Exit;
  R:=FColumnList.SelectedRow;
  I:=ColumnIndexById(R.Text);
  if (I>=0) and (I<FColumnCount-1) then MoveColumn(I,I+1);
  if ASender=nil then ;
end;

function TAFileManagerConfigurationDialog.ColumnDragBegin(
  ASender: TArosaControl; AIndex: Integer;
  const ARootPosition: TArosaPoint; const AModifiers: TArosaModifiers;
  out APayload: TArosaDragPayload): Boolean;
var
  R: TArosaListRow;
begin
  Result:=False;
  APayload:=nil;
  if (FColumnList=nil) or (AIndex<0) or (AIndex>=FColumnList.ItemCount) then Exit;
  R:=FColumnList.VisibleRowsView[AIndex];
  if R=nil then Exit;
  APayload:=TArosaDragPayload.Create;
  APayload.SourceIdentity:='arosa.afilemanager.configuration.columns';
  APayload.AddText(R.Text);
  Result:=True;
  if ASender=nil then ;
  if ARootPosition.X<0 then ;
  if amShift in AModifiers then ;
end;

procedure TAFileManagerConfigurationDialog.ColumnDragEnd(
  ASender: TArosaControl; AIndex: Integer;
  APayload: TArosaDragPayload; const ARootPosition: TArosaPoint;
  const AModifiers: TArosaModifiers);
var
  Local: TArosaPoint;
  TargetVisible: Integer;
  SourceId, TargetId: string;
  SourceIndex, TargetIndex: Integer;
  R: TArosaListRow;
begin
  if (FColumnList=nil) or (APayload=nil) then Exit;
  if not ArosaRectContains(FColumnList.AbsoluteBounds,ARootPosition) then Exit;

  SourceId:='';
  if (AIndex>=0) and (AIndex<FColumnList.ItemCount) then
  begin
    R:=FColumnList.VisibleRowsView[AIndex];
    if R<>nil then SourceId:=R.Text;
  end;
  if SourceId='' then Exit;

  Local:=FColumnList.RootToLocal(ARootPosition);
  TargetVisible:=FColumnList.ItemAtPosition(Local);
  if TargetVisible<0 then
    TargetIndex:=FColumnCount-1
  else
  begin
    R:=FColumnList.VisibleRowsView[TargetVisible];
    if R=nil then Exit;
    TargetId:=R.Text;
    TargetIndex:=ColumnIndexById(TargetId);
  end;

  SourceIndex:=ColumnIndexById(SourceId);
  if (SourceIndex>=0) and (TargetIndex>=0) then
    MoveColumn(SourceIndex,TargetIndex);

  if ASender=nil then ;
  if amShift in AModifiers then ;
end;

function TAFileManagerConfigurationDialog.ColumnOrderText: string;
var I: Integer;
begin
  Result:='';
  for I:=0 to FColumnCount-1 do
  begin
    if Result<>'' then Result:=Result+',';
    Result:=Result+FColumns[I].Id;
  end;
end;

function TAFileManagerConfigurationDialog.VisibleColumnsText: string;
var I: Integer;
begin
  Result:='';
  for I:=0 to FColumnCount-1 do
    if FColumns[I].Visible then
    begin
      if Result<>'' then Result:=Result+',';
      Result:=Result+FColumns[I].Id;
    end;
end;

procedure TAFileManagerConfigurationDialog.LoadColumnConfiguration(
  const AOrder, AVisible: string);
var
  Order, VisibleList: TStringList;
  NewCols: array of TAFMColumnConfiguration;
  NewCount, I, J: Integer;
  Id: string;
  Found: Boolean;
begin
  Order:=TStringList.Create;
  VisibleList:=TStringList.Create;
  try
    Order.StrictDelimiter:=True;
    Order.Delimiter:=',';
    Order.DelimitedText:=AOrder;
    VisibleList.StrictDelimiter:=True;
    VisibleList.Delimiter:=',';
    VisibleList.DelimitedText:=AVisible;

    SetLength(NewCols,Length(FColumns));
    NewCount:=0;

    for I:=0 to Order.Count-1 do
    begin
      Id:=Trim(Order[I]);
      J:=ColumnIndexById(Id);
      if J<0 then Continue;
      Found:=False;
      if NewCount>0 then
        for J:=0 to NewCount-1 do
          if SameText(NewCols[J].Id,Id) then begin Found:=True; Break; end;
      if Found then Continue;
      J:=ColumnIndexById(Id);
      NewCols[NewCount]:=FColumns[J];
      Inc(NewCount);
    end;

    for I:=0 to FColumnCount-1 do
    begin
      Found:=False;
      for J:=0 to NewCount-1 do
        if SameText(NewCols[J].Id,FColumns[I].Id) then
        begin
          Found:=True;
          Break;
        end;
      if not Found then
      begin
        NewCols[NewCount]:=FColumns[I];
        Inc(NewCount);
      end;
    end;

    for I:=0 to NewCount-1 do
    begin
      if Trim(AVisible)<>'' then
        NewCols[I].Visible:=VisibleList.IndexOf(NewCols[I].Id)>=0;
      if SameText(NewCols[I].Id,'resource.name') then
        NewCols[I].Visible:=True;
    end;

    FColumnCount:=NewCount;
    for I:=0 to NewCount-1 do FColumns[I]:=NewCols[I];
  finally
    Order.Free;
    VisibleList.Free;
  end;
end;

function TAFileManagerConfigurationDialog.FontRoleCaption(
  ARole: TAFMFontRole): string;
begin
  case ARole of
    affrText: Result:='Application text';
    affrLists: Result:='File lists / paths';
    affrConsole: Result:='Console / editor';
    affrHelp: Result:='Help / documents';
    affrInfo: Result:='Information / credits';
  else
    Result:='Font';
  end;
end;

procedure TAFileManagerConfigurationDialog.UpdateFontRoleLabel(
  ARole: TAFMFontRole);
var
  D: TArosaFontDescription;

  procedure ApplyPreviewFont(ALabel: TArosaLabel);
  begin
    if ALabel=nil then Exit;
    ALabel.FontFamily:=D.Family;
    ALabel.FontSize:=D.SizePoints;
    ALabel.InvalidateLayout;
    ALabel.InvalidatePaint;
  end;

begin
  D:=FFontSelections[ARole];
  if D.Family='' then D.Family:='system';
  if D.SizePoints<6 then D.SizePoints:=6;

  if FFontValueLabels[ARole]<>nil then
    FFontValueLabels[ARole].Text:=D.Family+'  '+IntToStr(D.SizePoints)+' pt';

  { The role line itself is the immediate sample for that configured role. }
  ApplyPreviewFont(FFontRoleLabels[ARole]);
  ApplyPreviewFont(FFontValueLabels[ARole]);
end;

procedure TAFileManagerConfigurationDialog.SelectFontRole(ARole: TAFMFontRole);
var R: TAFMFontRole;
begin
  { Save only an editor that was actually opened. }
  if (FFontPicker<>nil) and (FFontPickerGroup<>nil) and
     FFontPickerGroup.Visible then
  begin
    FFontSelections[FActiveFontRole]:=FFontPicker.Selection;
    UpdateFontRoleLabel(FActiveFontRole);
  end;

  FActiveFontRole:=ARole;
  for R:=Low(TAFMFontRole) to High(TAFMFontRole) do
    if FFontSelectButtons[R]<>nil then
      if R=ARole then
        FFontSelectButtons[R].Caption:=LocalText(
          'afilemanager_config_editing','Editing...')
      else
        FFontSelectButtons[R].Caption:=LocalText(
          'afilemanager_config_select','Select...');

  if FFontPickerGroup<>nil then
  begin
    FFontPickerGroup.Caption:=LocalText(
      'afilemanager_config_font_selector_editing',
      'Font selector - Editing: ')+FontRoleCaption(ARole);
    FFontPickerGroup.Visible:=True;
  end;
  FFontPicker.SetSelection(FFontSelections[ARole]);
  FFontPickerGroup.InvalidateLayout;
  FFontPickerGroup.InvalidatePaint;
end;

procedure TAFileManagerConfigurationDialog.FontPickerChanged(
  ASender: TArosaControl);
begin
  FFontSelections[FActiveFontRole]:=FFontPicker.Selection;
  UpdateFontRoleLabel(FActiveFontRole);
  if ASender=nil then ;
end;

procedure TAFileManagerConfigurationDialog.TextFontClick(ASender: TArosaControl);
begin SelectFontRole(affrText); if ASender=nil then ; end;
procedure TAFileManagerConfigurationDialog.ListsFontClick(ASender: TArosaControl);
begin SelectFontRole(affrLists); if ASender=nil then ; end;
procedure TAFileManagerConfigurationDialog.ConsoleFontClick(ASender: TArosaControl);
begin SelectFontRole(affrConsole); if ASender=nil then ; end;
procedure TAFileManagerConfigurationDialog.HelpFontClick(ASender: TArosaControl);
begin SelectFontRole(affrHelp); if ASender=nil then ; end;
procedure TAFileManagerConfigurationDialog.InfoFontClick(ASender: TArosaControl);
begin SelectFontRole(affrInfo); if ASender=nil then ; end;

procedure TAFileManagerConfigurationDialog.SetAvailableFonts(
  AFontsService: TArosaFontService);
var
  I,N: Integer;
  Faces: TArosaFontFaceArray;
begin
  N:=1;
  if AFontsService<>nil then N:=N+AFontsService.FaceCount;
  SetLength(Faces,N);

  Faces[0].Family:='system';
  Faces[0].Kind:=afkBitmap;
  Faces[0].Pitch:=afpProportional;
  Faces[0].Source:='semantic';
  Faces[0].Sizes:='';

  if AFontsService<>nil then
    for I:=0 to AFontsService.FaceCount-1 do
      Faces[I+1]:=AFontsService.Face(I);

  FFontPicker.SetFaces(Faces);
end;

procedure TAFileManagerConfigurationDialog.SetThemeOptions(
  const AThemes: array of string);
var I: Integer;
begin
  if FThemeCombo=nil then Exit;
  FThemeCombo.ClearItems;
  for I:=0 to High(AThemes) do
    if (Trim(AThemes[I])<>'') and (FThemeCombo.IndexOf(AThemes[I])<0) then
      FThemeCombo.AddItem(AThemes[I]);
  if FThemeCombo.ItemCount=0 then FThemeCombo.AddItem('default');
  FThemeCombo.SelectedIndex:=0;
end;

procedure TAFileManagerConfigurationDialog.SetLanguageOptions(
  const ALanguages: array of string);
var I: Integer;
begin
  if FLanguageCombo=nil then Exit;
  FLanguageCombo.ClearItems;
  FLanguageCombo.AddItem('System');
  for I:=0 to High(ALanguages) do
    if (Trim(ALanguages[I])<>'') and (FLanguageCombo.IndexOf(ALanguages[I])<0) then
      FLanguageCombo.AddItem(ALanguages[I]);
  if FLanguageCombo.ItemCount>0 then FLanguageCombo.SelectedIndex:=0;
end;

procedure TAFileManagerConfigurationDialog.SetStartupOptions(
  const ADescriptors, AProfiles: array of string);
var I: Integer;
begin
  FDescriptorCombo.ClearItems;
  for I:=0 to High(ADescriptors) do FDescriptorCombo.AddItem(ADescriptors[I]);
  if FDescriptorCombo.ItemCount=0 then
    FDescriptorCombo.AddItem('descriptors/AFileManager.release.window');

  FProfileCombo.ClearItems;
  for I:=0 to High(AProfiles) do FProfileCombo.AddItem(AProfiles[I]);
  if FProfileCombo.ItemCount=0 then
    FProfileCombo.AddItem('configurations/default.user');
end;

constructor TAFileManagerNameDialog.CreateNameDialog(ATheme: TArosaTheme;
  AFonts: TArosaFontCache; const AClipboard: IArosaClipboardPlatform);
var Row: TArosaRowPanel;
begin
  inherited CreateDialog(ATheme,AFonts,500,190);
  FPromptLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FPromptLabel.SetConstraintHeight(asmFixed,ArosaCoord(28));
  Content.AddVisual(FPromptLabel);
  FNameBox:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FNameBox.Multiline:=False;
  FNameBox.Clipboard:=AClipboard;
  FNameBox.OnAccept:=@TextAccept;
  FNameBox.SetConstraintHeight(asmFixed,ArosaCoord(34));
  Content.AddVisual(FNameBox);
  FOption:=TArosaCheckBox.CreateControl(ATheme,AFonts);
  FOption.SetConstraintHeight(asmFixed,ArosaCoord(28));
  FOption.Visible:=False;
  Content.AddVisual(FOption);
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FOKButton:=TArosaButton.CreateControl(ATheme,AFonts); FOKButton.Caption:='OK';
  FOKButton.OnClick:=@AcceptClick; FOKButton.SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FOKButton);
  FCancelButton:=TArosaButton.CreateControl(ATheme,AFonts); FCancelButton.Caption:='Cancel';
  FCancelButton.OnClick:=@CancelClick; FCancelButton.SetConstraintWidth(asmFixed,ArosaCoord(92)); Row.AddVisual(FCancelButton);
  Content.AddVisual(Row);
end;

procedure TAFileManagerNameDialog.ShowName(const ATitle, APrompt, AInitialValue: string);
begin
  FOption.Visible:=False;
  FOption.Checked:=False;
  FPreferredHeight:=190;
  FPromptLabel.Text:=ATitle+' - '+APrompt;
  FNameBox.Text:=AInitialValue;
  FNameBox.SelectAllText;
  InvalidateLayout;
  ShowDialog;
end;

procedure TAFileManagerNameDialog.ShowNameWithOption(const ATitle, APrompt,
  AInitialValue, AOptionCaption: string; AOptionChecked: Boolean);
begin
  FOption.Caption:=AOptionCaption;
  FOption.Checked:=AOptionChecked;
  FOption.Visible:=True;
  { one more row than the plain dialog }
  FPreferredHeight:=226;
  FPromptLabel.Text:=ATitle+' - '+APrompt;
  FNameBox.Text:=AInitialValue;
  FNameBox.SelectAllText;
  InvalidateLayout;
  ShowDialog;
end;

function TAFileManagerNameDialog.GetOptionChecked: Boolean;
begin
  Result:=(FOption<>nil) and FOption.Visible and FOption.Checked;
end;

procedure TAFileManagerNameDialog.AcceptClick(ASender: TArosaControl);
var V: string;
begin
  V:=Trim(FNameBox.Text);
  if V='' then Exit;
  Dismiss;
  if Assigned(FOnAccept) then FOnAccept(Self,V);
  if ASender=nil then ;
end;

procedure TAFileManagerNameDialog.TextAccept(ASender: TArosaControl);
begin
  AcceptClick(ASender);
end;

procedure TAFileManagerNameDialog.CancelClick(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;

constructor TAFileManagerOpenFileDialog.CreateOpenFileDialog(
  ATheme: TArosaTheme; AFonts: TArosaFontCache;
  const AClipboard: IArosaClipboardPlatform;
  AImageLoader: TArosaImageLoaderService);
begin
  inherited CreateDialog(ATheme,AFonts,860,600);
  Resizable:=True;
  FImagePresentation:=nil;
  FDialog:=TArosaFileDialog.CreateControl(ATheme,AFonts);
  FDialog.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDialog.SetConstraintHeight(asmStar,ArosaCoord(1));
  FDialog.OnAccept:=@DialogAccepted;
  FDialog.OnCancel:=@DialogCancelled;
  FImagePresentation:=TArosaFileDialogImagePresentation.CreatePresentation(
    ATheme,AFonts,AImageLoader,AClipboard);
  { AFileManager supplies its richer file-row presenter separately; only the
    standard image preview is attached here. }
  FImagePresentation.Attach(FDialog,False);
  Content.AddVisual(FDialog);
end;

procedure TAFileManagerOpenFileDialog.DoDispose;
begin
  FreeAndNil(FImagePresentation);
  FDialog:=nil;
  inherited DoDispose;
end;

procedure TAFileManagerOpenFileDialog.SetLister(ALister: TArosaDirLister);
begin
  if FDialog<>nil then FDialog.SetLister(ALister);
end;

procedure TAFileManagerOpenFileDialog.SetRowDecorator(
  ADecorator: TArosaFileDialogRowDecorator);
begin
  if FDialog<>nil then FDialog.OnDecorateRow:=ADecorator;
end;

procedure TAFileManagerOpenFileDialog.SetIconResolver(
  AResolver: TArosaFileDialogIconResolver);
begin
  if FDialog<>nil then FDialog.OnResolveIcon:=AResolver;
end;

procedure TAFileManagerOpenFileDialog.ClearLocations;
begin
  if FDialog<>nil then FDialog.ClearLocations;
end;

function TAFileManagerOpenFileDialog.AddLocationGroup(const ACaption,
  ASemanticIcon: string): TArosaTreeNode;
begin
  if FDialog<>nil then Result:=FDialog.AddLocationGroup(ACaption,ASemanticIcon)
  else Result:=nil;
end;

function TAFileManagerOpenFileDialog.AddLocation(AParent: TArosaTreeNode;
  const ACaption, APath, ASemanticIcon: string): TArosaTreeNode;
begin
  if FDialog<>nil then
    Result:=FDialog.AddLocation(AParent,ACaption,APath,ASemanticIcon)
  else Result:=nil;
end;

procedure TAFileManagerOpenFileDialog.SetPreviewPlacement(
  APlacement: TArosaFileDialogPreviewPlacement);
begin
  if FDialog<>nil then FDialog.SetPreviewPlacement(APlacement);
end;

procedure TAFileManagerOpenFileDialog.ShowOpen(const ADirectory,
  AFileName: string);
begin
  if FDialog=nil then Exit;
  FDialog.SetMode(afdmOpen);
  FDialog.ClearTypeFilters;
  FDialog.AddTypeFilter(ArosaText('arosa.dialog.filter.images',
    'Images (*.png;*.jpg;*.jpeg;*.bmp;*.gif)'),'.png;.jpg;.jpeg;.bmp;.gif');
  FDialog.AddTypeFilter(ArosaText('arosa.dialog.filter.all','All files'),'');
  FDialog.SelectTypeFilter(0);
  FDialog.OkCaption:=ArosaText('arosa.dialog.open','Open');
  FDialog.CancelCaption:=ArosaText('arosa.dialog.cancel','Cancel');
  FDialog.Navigate(ADirectory);
  if AFileName<>'' then FDialog.SetFileName(AFileName);
  ShowDialog;
end;

procedure TAFileManagerOpenFileDialog.DialogAccepted(ASender: TArosaControl);
var P: string;
begin
  if FDialog=nil then Exit;
  P:=FDialog.SelectedPath;
  Dismiss;
  if Assigned(FOnAcceptPath) then FOnAcceptPath(Self,P);
  if ASender=nil then ;
end;

procedure TAFileManagerOpenFileDialog.DialogCancelled(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;

function TAFileManagerWorkspacePropertiesDialog.LocalText(
  const AKey, AFallback: string): string;
begin
  if FLocalization<>nil then Result:=FLocalization.Text(AKey,AFallback)
  else Result:=AFallback;
end;

constructor TAFileManagerWorkspacePropertiesDialog.CreateWorkspaceProperties(
  ATheme: TArosaTheme; AFonts: TArosaFontCache;
  const AClipboard: IArosaClipboardPlatform;
  ALocalization: TArosaLocalizationService);
var
  L: TArosaLabel;
  Row: TArosaRowPanel;
  Tabs: TArosaTabControl;
  GeneralPage, BackgroundPage: TArosaTabPage;
  General, Background: TArosaColumnPanel;

  procedure AddTextRow(AParent: TArosaColumnPanel; const ACaption: string;
    ABox: TArosaTextBox);
  begin
    Row:=TArosaRowPanel.Create;
    Row.Spacing:=ArosaCoord(8);
    Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
    L:=TArosaLabel.CreateControl(ATheme,AFonts);
    L.Text:=ACaption;
    L.SetConstraintWidth(asmFixed,ArosaCoord(180));
    Row.AddVisual(L);
    ABox.SetConstraintWidth(asmStar,ArosaCoord(1));
    ABox.SetConstraintHeight(asmFixed,ArosaCoord(30));
    Row.AddVisual(ABox);
    AParent.AddVisual(Row);
  end;

  function NewPage(const ACaption: string; out APage: TArosaTabPage):
    TArosaColumnPanel;
  begin
    APage:=TArosaTabPage.Create;
    APage.Caption:=ACaption;
    APage.Padding:=ArosaUniformMargins(8);
    Tabs.AddTabPage(APage);
    Result:=TArosaColumnPanel.Create;
    Result.Spacing:=ArosaCoord(7);
    APage.AddVisual(Result);
  end;

begin
  inherited CreateDialog(ATheme,AFonts,780,690);
  FLocalization:=ALocalization;

  FTitleLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FTitleLabel.Text:=LocalText('afilemanager_workspace_edit_properties',
    'Edit workspace properties');
  FTitleLabel.TextRole:=AROSA_ROLE_ACCENT;
  FTitleLabel.SetConstraintHeight(asmFixed,ArosaCoord(30));
  Content.AddVisual(FTitleLabel);

  Tabs:=TArosaTabControl.Create;
  Tabs.Font:=UIFont;
  Tabs.ActiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsPressed);
  Tabs.InactiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsNormal);
  Tabs.ActiveText:=ATheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT,avsNormal);
  Tabs.InactiveText:=ATheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT,avsNormal);
  Tabs.BorderColour:=ATheme.ColourFor(AROSA_ROLE_BORDER,avsNormal);
  Tabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  Content.AddVisual(Tabs);

  General:=NewPage(LocalText('afilemanager_workspace_general','General'),GeneralPage);

  FNameBox:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FNameBox.Multiline:=False; FNameBox.Clipboard:=AClipboard;
  AddTextRow(General,LocalText('afilemanager_workspace_name','Workspace name'),FNameBox);

  FThemeCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FThemeCombo.AddItem(LocalText('afilemanager_config_dark','Dark'));
  FThemeCombo.AddItem(LocalText('afilemanager_config_light','Light'));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_theme','Color scheme');
  L.SetConstraintWidth(asmFixed,ArosaCoord(180)); Row.AddVisual(L);
  FThemeCombo.SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FThemeCombo);
  General.AddVisual(Row);

  FScreenModeCombo:=TArosaComboBox.CreateControl(ATheme,AFonts);
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_screen_mode','Screen mode');
  L.SetConstraintWidth(asmFixed,ArosaCoord(180)); Row.AddVisual(L);
  FScreenModeCombo.SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FScreenModeCombo);
  General.AddVisual(Row);

  FShareClipboard:=TArosaCheckBox.CreateControl(ATheme,AFonts);
  FShareClipboard.Caption:=LocalText('afilemanager_workspace_share_clipboard','Share clipboard');
  FShareClipboard.SetConstraintHeight(asmFixed,ArosaCoord(30)); General.AddVisual(FShareClipboard);
  FShareDesk:=TArosaCheckBox.CreateControl(ATheme,AFonts);
  FShareDesk.Caption:=LocalText('afilemanager_workspace_share_desk','Share desk');
  FShareDesk.SetConstraintHeight(asmFixed,ArosaCoord(30)); General.AddVisual(FShareDesk);

  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_properties_note',
    'Resolution/theme/background changes apply when the workspace screen is next created. Sharing is workspace policy.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(52)); General.AddVisual(L);

  Background:=NewPage(LocalText('afilemanager_workspace_background_tab','Background'),BackgroundPage);

  FBackgroundBox:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FBackgroundBox.Multiline:=False; FBackgroundBox.Clipboard:=AClipboard;
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_background','Background picture');
  L.SetConstraintWidth(asmFixed,ArosaCoord(160)); Row.AddVisual(L);
  FBackgroundBox.SetConstraintWidth(asmStar,ArosaCoord(1));
  FBackgroundBox.SetConstraintHeight(asmFixed,ArosaCoord(30)); Row.AddVisual(FBackgroundBox);
  FBackgroundBrowse:=TArosaButton.CreateControl(ATheme,AFonts);
  FBackgroundBrowse.Caption:=LocalText('afilemanager_browse','Browse...');
  FBackgroundBrowse.SetConstraintWidth(asmFixed,ArosaCoord(100));
  FBackgroundBrowse.OnClick:=@BackgroundBrowseClick; Row.AddVisual(FBackgroundBrowse);
  Background.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(18);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(30));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_background_fill','Fill');
  L.SetConstraintWidth(asmFixed,ArosaCoord(160)); Row.AddVisual(L);
  FBackgroundColourRadio:=TArosaRadioButton.CreateControl(ATheme,AFonts);
  FBackgroundColourRadio.Caption:=LocalText('afilemanager_workspace_background_color','Color');
  FBackgroundColourRadio.GroupName:='workspace-background-fill';
  FBackgroundColourRadio.OnChange:=@BackgroundModeChanged;
  FBackgroundColourRadio.SetConstraintWidth(asmFixed,ArosaCoord(120)); Row.AddVisual(FBackgroundColourRadio);
  FBackgroundGradientRadio:=TArosaRadioButton.CreateControl(ATheme,AFonts);
  FBackgroundGradientRadio.Caption:=LocalText('afilemanager_workspace_background_gradient','Gradient');
  FBackgroundGradientRadio.GroupName:='workspace-background-fill';
  FBackgroundGradientRadio.OnChange:=@BackgroundModeChanged;
  FBackgroundGradientRadio.SetConstraintWidth(asmFixed,ArosaCoord(140)); Row.AddVisual(FBackgroundGradientRadio);
  Background.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(12);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(24));
  FBackgroundStartLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FBackgroundStartLabel.Text:=LocalText('afilemanager_workspace_background_start_color','Start / solid color');
  FBackgroundStartLabel.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FBackgroundStartLabel);
  FBackgroundEndLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FBackgroundEndLabel.Text:=LocalText('afilemanager_workspace_background_end_color','End color');
  FBackgroundEndLabel.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FBackgroundEndLabel);
  Background.AddVisual(Row);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(12);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(160));
  FBackgroundStartPicker:=TArosaColourPicker.Create;
  FBackgroundStartPicker.SetTheme(ATheme,AFonts);
  FBackgroundStartPicker.Clipboard:=AClipboard;
  FBackgroundStartPicker.SetConstraintWidth(asmStar,ArosaCoord(1));
  FBackgroundStartPicker.SetConstraintHeight(asmFixed,ArosaCoord(160));
  FBackgroundStartPicker.OnColourChanged:=@BackgroundStartColourChanged;
  Row.AddVisual(FBackgroundStartPicker);

  FBackgroundEndPicker:=TArosaColourPicker.Create;
  FBackgroundEndPicker.SetTheme(ATheme,AFonts);
  FBackgroundEndPicker.Clipboard:=AClipboard;
  FBackgroundEndPicker.SetConstraintWidth(asmStar,ArosaCoord(1));
  FBackgroundEndPicker.SetConstraintHeight(asmFixed,ArosaCoord(160));
  FBackgroundEndPicker.OnColourChanged:=@BackgroundEndColourChanged;
  Row.AddVisual(FBackgroundEndPicker);
  Background.AddVisual(Row);

  FBackgroundGradientPreview:=TAFMGradientPreview.Create;
  FBackgroundGradientPreview.SetTheme(ATheme,AFonts);
  FBackgroundGradientPreview.SetConstraintHeight(asmFixed,ArosaCoord(52));
  FBackgroundGradientPreview.SetConstraintWidth(asmStar,ArosaCoord(1));
  Background.AddVisual(FBackgroundGradientPreview);

  FBackgroundDirection:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FBackgroundDirection.AddItem(LocalText('afilemanager_workspace_gradient_left_right','Left to right'));
  FBackgroundDirection.AddItem(LocalText('afilemanager_workspace_gradient_top_bottom','Top to bottom'));
  FBackgroundDirection.OnChange:=@BackgroundDirectionChanged;
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8); Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_workspace_gradient_direction','Gradient direction');
  L.SetConstraintWidth(asmFixed,ArosaCoord(160)); Row.AddVisual(L);
  FBackgroundDirection.SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FBackgroundDirection); Background.AddVisual(Row);

  FBackgroundLayerOrder:=TArosaComboBox.CreateControl(ATheme,AFonts);
  FBackgroundLayerOrder.AddItem(LocalText('afilemanager_workspace_background_before_image','Before image'));
  FBackgroundLayerOrder.AddItem(LocalText('afilemanager_workspace_background_after_image','After image'));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8); Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_workspace_background_layer','Color/gradient layer');
  L.SetConstraintWidth(asmFixed,ArosaCoord(160)); Row.AddVisual(L);
  FBackgroundLayerOrder.SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FBackgroundLayerOrder); Background.AddVisual(Row);

  FBackgroundOpacity:=TArosaSlider.CreateControl(ATheme,AFonts);
  FBackgroundOpacity.Minimum:=0; FBackgroundOpacity.Maximum:=100; FBackgroundOpacity.Value:=100;
  FBackgroundOpacity.OnChange:=@BackgroundOpacityChanged;
  FBackgroundOpacityLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FBackgroundOpacityLabel.Text:='100%'; FBackgroundOpacityLabel.SetConstraintWidth(asmFixed,ArosaCoord(52));
  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8); Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts); L.Text:=LocalText('afilemanager_workspace_background_opacity','Layer opacity');
  L.SetConstraintWidth(asmFixed,ArosaCoord(160)); Row.AddVisual(L);
  FBackgroundOpacity.SetConstraintWidth(asmStar,ArosaCoord(1)); Row.AddVisual(FBackgroundOpacity); Row.AddVisual(FBackgroundOpacityLabel); Background.AddVisual(Row);

  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_background_note',
    'A color/gradient drawn before the picture acts as the screen background and is visible through transparent image areas. Drawing it after the picture creates a translucent custom overlay.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT; L.SetConstraintHeight(asmFixed,ArosaCoord(58)); Background.AddVisual(L);

  Row:=TArosaRowPanel.Create; Row.Spacing:=ArosaCoord(8); Row.SetConstraintHeight(asmFixed,ArosaCoord(36));
  FSaveButton:=TArosaButton.CreateControl(ATheme,AFonts); FSaveButton.Caption:=LocalText('afilemanager_save','Save');
  FSaveButton.OnClick:=@SaveClick; FSaveButton.SetConstraintWidth(asmFixed,ArosaCoord(100)); Row.AddVisual(FSaveButton);
  FCancelButton:=TArosaButton.CreateControl(ATheme,AFonts); FCancelButton.Caption:=LocalText('afilemanager_cancel','Cancel');
  FCancelButton.OnClick:=@CancelClick; FCancelButton.SetConstraintWidth(asmFixed,ArosaCoord(100)); Row.AddVisual(FCancelButton);
  Content.AddVisual(Row);

  FBackgroundColours[0]:=ArosaColour(32,36,44);
  FBackgroundColours[1]:=ArosaColour(48,54,66);
  FBackgroundColours[2]:=ArosaColour(64,72,88);
  FBackgroundColours[3]:=ArosaColour(80,90,108);
  FBackgroundStartPicker.Colour:=FBackgroundColours[0];
  FBackgroundEndPicker.Colour:=FBackgroundColours[3];
  FBackgroundDirection.SelectedIndex:=0;
  UpdateBackgroundEditorState;
end;

function TAFileManagerWorkspacePropertiesDialog.CurrentSettings:
  TAFMWorkspaceProperties;
begin
  Result.Name:=Trim(FNameBox.Text);
  if FThemeCombo.SelectedIndex=1 then Result.ThemeId:='Light'
  else Result.ThemeId:='Dark';
  Result.ScreenWidth:=0;
  Result.ScreenHeight:=0;
  Result.ScreenDepth:=0;
  if (FScreenModeCombo<>nil) and (FScreenModeCombo.SelectedIndex>0) and
     (FScreenModeCombo.SelectedIndex-1<Length(FScreenModes)) then
  begin
    Result.ScreenWidth:=FScreenModes[FScreenModeCombo.SelectedIndex-1].Width;
    Result.ScreenHeight:=FScreenModes[FScreenModeCombo.SelectedIndex-1].Height;
    Result.ScreenDepth:=FScreenModes[FScreenModeCombo.SelectedIndex-1].Depth;
  end;
  Result.BackgroundImage:=Trim(FBackgroundBox.Text);
  if (FBackgroundGradientRadio<>nil) and FBackgroundGradientRadio.Checked then
    Result.BackgroundMode:='gradient'
  else Result.BackgroundMode:='color';
  UpdateBackgroundGradientColours;
  Result.BackgroundColour1:=FBackgroundColours[0];
  Result.BackgroundColour2:=FBackgroundColours[1];
  Result.BackgroundColour3:=FBackgroundColours[2];
  Result.BackgroundColour4:=FBackgroundColours[3];
  if (FBackgroundDirection<>nil) and (FBackgroundDirection.SelectedIndex=1) then
    Result.BackgroundGradientDirection:='vertical'
  else Result.BackgroundGradientDirection:='horizontal';
  if (FBackgroundLayerOrder<>nil) and (FBackgroundLayerOrder.SelectedIndex=1) then
    Result.BackgroundLayerOrder:='after'
  else Result.BackgroundLayerOrder:='before';
  if FBackgroundOpacity<>nil then Result.BackgroundOpacity:=FBackgroundOpacity.Value
  else Result.BackgroundOpacity:=100;
  Result.ShareClipboard:=FShareClipboard.Checked;
  Result.ShareDesk:=FShareDesk.Checked;
end;

procedure TAFileManagerWorkspacePropertiesDialog.SetScreenModes(
  const AModes: TArosaScreenModeArray);
var
  I: Integer;
  Caption: string;
begin
  SetLength(FScreenModes,Length(AModes));
  for I:=0 to High(AModes) do
    FScreenModes[I]:=AModes[I];
  if FScreenModeCombo=nil then Exit;
  FScreenModeCombo.ClearItems;
  FScreenModeCombo.AddItem(LocalText('afilemanager_workspace_screen_default',
    'Default desktop mode'));
  for I:=0 to High(FScreenModes) do
  begin
    Caption:=IntToStr(FScreenModes[I].Width)+' x '+
      IntToStr(FScreenModes[I].Height)+' x '+IntToStr(FScreenModes[I].Depth);
    if Trim(FScreenModes[I].Name)<>'' then Caption:=Caption+' - '+FScreenModes[I].Name;
    FScreenModeCombo.AddItem(Caption);
  end;
  FScreenModeCombo.SelectedIndex:=0;
end;

procedure TAFileManagerWorkspacePropertiesDialog.ShowSettings(
  const ASettings: TAFMWorkspaceProperties);
var I: Integer;
begin
  if FTitleLabel<>nil then
    FTitleLabel.Text:=LocalText('afilemanager_workspace_edit_properties',
      'Edit workspace properties')+' - '+ASettings.Name;
  FNameBox.Text:=ASettings.Name;
  if SameText(ASettings.ThemeId,'Light') then FThemeCombo.SelectedIndex:=1
  else FThemeCombo.SelectedIndex:=0;
  if FScreenModeCombo<>nil then
  begin
    FScreenModeCombo.SelectedIndex:=0;
    for I:=0 to High(FScreenModes) do
      if (FScreenModes[I].Width=ASettings.ScreenWidth) and
         (FScreenModes[I].Height=ASettings.ScreenHeight) and
         (FScreenModes[I].Depth=ASettings.ScreenDepth) then
      begin
        FScreenModeCombo.SelectedIndex:=I+1;
        Break;
      end;
    { Preserve a previously configured mode even when the platform no longer
      reports it; the user can deliberately move to an available mode. }
    if (FScreenModeCombo.SelectedIndex=0) and (ASettings.ScreenWidth>0) and
       (ASettings.ScreenHeight>0) and (ASettings.ScreenDepth>0) then
    begin
      I:=Length(FScreenModes);
      SetLength(FScreenModes,I+1);
      FScreenModes[I].Width:=ASettings.ScreenWidth;
      FScreenModes[I].Height:=ASettings.ScreenHeight;
      FScreenModes[I].Depth:=ASettings.ScreenDepth;
      FScreenModes[I].RefreshHz:=0;
      FScreenModes[I].Name:=LocalText('afilemanager_workspace_configured_mode','Configured mode');
      FScreenModeCombo.AddItem(IntToStr(ASettings.ScreenWidth)+' x '+
        IntToStr(ASettings.ScreenHeight)+' x '+IntToStr(ASettings.ScreenDepth)+' ('+
        FScreenModes[I].Name+')');
      FScreenModeCombo.SelectedIndex:=I+1;
    end;
  end;
  FBackgroundBox.Text:=ASettings.BackgroundImage;
  FBackgroundColours[0]:=ASettings.BackgroundColour1;
  FBackgroundColours[1]:=ASettings.BackgroundColour2;
  FBackgroundColours[2]:=ASettings.BackgroundColour3;
  FBackgroundColours[3]:=ASettings.BackgroundColour4;
  if SameText(ASettings.BackgroundMode,'gradient') then
  begin FBackgroundGradientRadio.Checked:=True; FBackgroundColourRadio.Checked:=False; end
  else begin FBackgroundColourRadio.Checked:=True; FBackgroundGradientRadio.Checked:=False; end;
  if SameText(ASettings.BackgroundGradientDirection,'vertical') then FBackgroundDirection.SelectedIndex:=1
  else FBackgroundDirection.SelectedIndex:=0;
  BackgroundDirectionChanged(FBackgroundDirection);
  if SameText(ASettings.BackgroundLayerOrder,'after') then FBackgroundLayerOrder.SelectedIndex:=1
  else FBackgroundLayerOrder.SelectedIndex:=0;
  if ASettings.BackgroundOpacity<0 then FBackgroundOpacity.Value:=0
  else if ASettings.BackgroundOpacity>100 then FBackgroundOpacity.Value:=100
  else FBackgroundOpacity.Value:=ASettings.BackgroundOpacity;
  FBackgroundOpacityLabel.Text:=IntToStr(FBackgroundOpacity.Value)+'%';
  FBackgroundStartPicker.Colour:=FBackgroundColours[0];
  FBackgroundEndPicker.Colour:=FBackgroundColours[3];
  UpdateBackgroundGradientColours;
  UpdateBackgroundEditorState;
  FShareClipboard.Checked:=ASettings.ShareClipboard;
  FShareDesk.Checked:=ASettings.ShareDesk;
  ShowDialog;
end;

procedure TAFileManagerWorkspacePropertiesDialog.SetBackgroundImage(
  const APath: string);
begin
  if FBackgroundBox<>nil then FBackgroundBox.Text:=APath;
end;

function TAFileManagerWorkspacePropertiesDialog.BackgroundImage: string;
begin
  if FBackgroundBox<>nil then Result:=Trim(FBackgroundBox.Text)
  else Result:='';
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundBrowseClick(
  ASender: TArosaControl);
begin
  if Assigned(FOnBrowseBackground) then FOnBrowseBackground(Self);
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.UpdateBackgroundGradientColours;
var
  S,E: TArosaColour;
  function Mix(A,B,Part,Total: Integer): Integer;
  begin
    Result:=A+((B-A)*Part) div Total;
  end;
begin
  if FBackgroundStartPicker<>nil then FBackgroundColours[0]:=FBackgroundStartPicker.Colour;
  if FBackgroundEndPicker<>nil then FBackgroundColours[3]:=FBackgroundEndPicker.Colour;
  S:=FBackgroundColours[0]; E:=FBackgroundColours[3];
  FBackgroundColours[1]:=ArosaColour(
    Mix(ArosaColourRed(S),ArosaColourRed(E),1,3),
    Mix(ArosaColourGreen(S),ArosaColourGreen(E),1,3),
    Mix(ArosaColourBlue(S),ArosaColourBlue(E),1,3));
  FBackgroundColours[2]:=ArosaColour(
    Mix(ArosaColourRed(S),ArosaColourRed(E),2,3),
    Mix(ArosaColourGreen(S),ArosaColourGreen(E),2,3),
    Mix(ArosaColourBlue(S),ArosaColourBlue(E),2,3));
  if FBackgroundGradientPreview<>nil then
  begin
    FBackgroundGradientPreview.StartColour:=S;
    FBackgroundGradientPreview.EndColour:=E;
  end;
end;

procedure TAFileManagerWorkspacePropertiesDialog.UpdateBackgroundEditorState;
var
  IsGradient: Boolean;
begin
  IsGradient:=(FBackgroundGradientRadio<>nil) and FBackgroundGradientRadio.Checked;
  if FBackgroundStartLabel<>nil then
    if IsGradient then
      FBackgroundStartLabel.Text:=LocalText('afilemanager_workspace_background_start_color','Start color')
    else
      FBackgroundStartLabel.Text:=LocalText('afilemanager_workspace_background_solid_color','Solid color');
  if FBackgroundEndLabel<>nil then FBackgroundEndLabel.Visible:=IsGradient;
  if FBackgroundEndPicker<>nil then FBackgroundEndPicker.Visible:=IsGradient;
  if FBackgroundGradientPreview<>nil then FBackgroundGradientPreview.Visible:=IsGradient;
  if FBackgroundDirection<>nil then FBackgroundDirection.Enabled:=IsGradient;
  InvalidateLayout;
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundModeChanged(
  ASender: TArosaControl);
begin
  UpdateBackgroundEditorState;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundDirectionChanged(
  ASender: TArosaControl);
begin
  if FBackgroundGradientPreview<>nil then
    FBackgroundGradientPreview.Vertical:=(FBackgroundDirection<>nil) and
      (FBackgroundDirection.SelectedIndex=1);
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundStartColourChanged(
  ASender: TArosaControl);
begin
  UpdateBackgroundGradientColours;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundEndColourChanged(
  ASender: TArosaControl);
begin
  UpdateBackgroundGradientColours;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.BackgroundOpacityChanged(
  ASender: TArosaControl; AValue: Integer);
begin
  FBackgroundOpacityLabel.Text:=IntToStr(AValue)+'%';
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.SaveClick(ASender: TArosaControl);
var S: TAFMWorkspaceProperties;
begin
  S:=CurrentSettings;
  if Trim(S.Name)='' then Exit;
  if Assigned(FOnApply) then FOnApply(Self,S);
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspacePropertiesDialog.CancelClick(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;


function TAFileManagerWorkspaceModulesDialog.LocalText(
  const AKey, AFallback: string): string;
begin
  if FLocalization<>nil then Result:=FLocalization.Text(AKey,AFallback)
  else Result:=AFallback;
end;

constructor TAFileManagerWorkspaceModulesDialog.CreateWorkspaceModules(
  ATheme: TArosaTheme; AFonts: TArosaFontCache;
  const AClipboard: IArosaClipboardPlatform;
  ALocalization: TArosaLocalizationService);
var Row: TArosaRowPanel; L: TArosaLabel;

  function NewButton(const AKey, AFallback: string;
    AClick: TArosaClickEvent): TArosaButton;
  begin
    Result:=TArosaButton.CreateControl(ATheme,AFonts);
    Result.Caption:=LocalText(AKey,AFallback);
    Result.OnClick:=AClick;
    Result.SetConstraintWidth(asmFixed,ArosaCoord(100));
    Row.AddVisual(Result);
  end;

begin
  inherited CreateDialog(ATheme,AFonts,980,560);
  Resizable:=True;
  FLocalization:=ALocalization;
  FChecks:=TStringList.Create;
  FStatusLabels:=TStringList.Create;
  FIds:=TStringList.Create;
  FModules:=nil;
  FWorkspaceId:='';

  FTitleLabel:=TArosaLabel.CreateControl(ATheme,AFonts);
  FTitleLabel.TextRole:=AROSA_ROLE_ACCENT;
  FTitleLabel.SetConstraintHeight(asmFixed,ArosaCoord(30));
  Content.AddVisual(FTitleLabel);

  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_modules_note2',
    'Choose installed software for this workspace and where it appears. The catalogue taxonomy is user-definable.');
  L.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  L.SetConstraintHeight(asmFixed,ArosaCoord(42));
  Content.AddVisual(L);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  L:=TArosaLabel.CreateControl(ATheme,AFonts);
  L.Text:=LocalText('afilemanager_workspace_modules_filter','Filter');
  L.SetConstraintWidth(asmFixed,ArosaCoord(90));
  Row.AddVisual(L);
  FFilter:=TArosaTextBox.CreateControl(ATheme,AFonts);
  FFilter.Multiline:=False;
  FFilter.Clipboard:=AClipboard;
  FFilter.OnChange:=@FilterChanged;
  FFilter.SetConstraintWidth(asmStar,ArosaCoord(1));
  Row.AddVisual(FFilter);
  Content.AddVisual(Row);

  FList:=TArosaFilteredListView.CreateControl(ATheme,AFonts);
  FList.SelectionMode:=alsSingle;
  FList.HeaderVisible:=True;
  FList.AddColumn('module.name',LocalText('afilemanager_workspace_modules_name','Module'),ArosaCoord(220));
  FList.AddColumn('module.category',LocalText('afilemanager_workspace_modules_category','Category'),ArosaCoord(130));
  FList.AddColumn('module.status',LocalText('afilemanager_workspace_modules_status','Status'),ArosaCoord(120));
  FList.AddColumn('module.member',LocalText('afilemanager_workspace_modules_member','Workspace'),ArosaCoord(110));
  FList.AddColumn('module.startmenu',LocalText('afilemanager_workspace_modules_startmenu','Start menu'),ArosaCoord(110));
  FList.AddColumn('module.taskbar',LocalText('afilemanager_workspace_modules_taskbar','Taskbar'),ArosaCoord(100));
  FList.AddColumn('module.desktop',LocalText('afilemanager_workspace_modules_desktop','Desktop'),ArosaCoord(100));
  FList.OnSelect:=@SelectionChanged;
  FList.SetConstraintHeight(asmStar,ArosaCoord(1));
  Content.AddVisual(FList);

  FDescription:=TArosaLabel.CreateControl(ATheme,AFonts);
  FDescription.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  FDescription.SetConstraintHeight(asmFixed,ArosaCoord(54));
  Content.AddVisual(FDescription);

  Row:=TArosaRowPanel.Create;
  Row.Spacing:=ArosaCoord(8);
  Row.SetConstraintHeight(asmFixed,ArosaCoord(36));
  FApplyButton:=NewButton('arosa_action_apply','Apply',@ApplyClick);
  FRestoreButton:=NewButton('afilemanager_workspace_modules_restore','Restore',@RestoreClick);
  FSaveButton:=NewButton('arosa_action_save','Save',@SaveClick);
  FCancelButton:=NewButton('arosa_action_cancel','Cancel',@CancelClick);
  Content.AddVisual(Row);
  if AClipboard=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.DoDispose;
begin
  FreeAndNil(FChecks);
  FreeAndNil(FStatusLabels);
  FreeAndNil(FIds);
  inherited DoDispose;
end;

function TAFileManagerWorkspaceModulesDialog.SelectedModuleId: string;
begin
  Result:='';
  if (FList<>nil) and (FList.SelectedRow<>nil) then Result:=Trim(FList.SelectedRow.Text);
end;

function TAFileManagerWorkspaceModulesDialog.Live(
  const AModule: TArosaWorkspaceModule): TAFMModuleBoxes;
var K: Integer;
begin
  { what is configured now, outside the dialog }
  Result[0]:=(FModules<>nil) and FModules.IsEnabled(FWorkspaceId,AModule.Id);
  for K:=0 to 2 do
    Result[K+1]:=AModule.Available and Assigned(FOnQueryPlacement) and
      FOnQueryPlacement(FWorkspaceId,AModule.Id,K);
end;

function TAFileManagerWorkspaceModulesDialog.StatusText(AIndex: Integer;
  const AModule: TArosaWorkspaceModule): string;
var Now: TAFMModuleBoxes; K: Integer; Changed: Boolean;
begin
  if not AModule.Available then
    Exit(LocalText('afilemanager_workspace_modules_planned','Planned'));
  if FPending[AIndex][0] then
    Result:=LocalText('afilemanager_workspace_modules_added','Added')
  else
    Result:=LocalText('afilemanager_workspace_modules_available','Available');
  { a row whose boxes are not what is configured is marked until it is applied }
  Now:=Live(AModule);
  Changed:=False;
  for K:=0 to 3 do
    if Now[K]<>FPending[AIndex][K] then Changed:=True;
  if Changed then Result:=Result+' *';
end;

function TAFileManagerWorkspaceModulesDialog.HasUnapplied: Boolean;
var I, K: Integer; M: TArosaWorkspaceModule; Now: TAFMModuleBoxes;
begin
  Result:=False;
  if FModules=nil then Exit;
  for I:=0 to FIds.Count-1 do
    if FModules.Find(FIds[I],M) and M.Available then
    begin
      Now:=Live(M);
      for K:=0 to 3 do
        if Now[K]<>FPending[I][K] then Exit(True);
    end;
end;

function TAFileManagerWorkspaceModulesDialog.DiffersFromOriginal: Boolean;
var I, K: Integer;
begin
  Result:=False;
  for I:=0 to FIds.Count-1 do
    for K:=0 to 3 do
      if FOriginal[I][K]<>FPending[I][K] then Exit(True);
end;

procedure TAFileManagerWorkspaceModulesDialog.RebuildList;
const BoxWidth: array[0..3] of Integer = (110,110,100,100);
var Modules: TArosaWorkspaceModuleArray; I, K: Integer; M: TArosaWorkspaceModule;
  Row: TArosaListRow; NameLabel,CategoryLabel,StatusLabel: TArosaLabel;
  Check: TArosaCheckBox;
begin
  { Builds the rows from FPending.  Never called from inside the input of the
    list (a box that is toggled changes its row in place: RefreshRow). }
  if FList=nil then Exit;
  FList.Clear;
  FChecks.Clear;
  FStatusLabels.Clear;
  if FModules=nil then Exit;
  Modules:=FModules.Catalogue;
  for I:=0 to High(Modules) do
  begin
    M:=Modules[I];
    if I>=FIds.Count then Break;
    Row:=TArosaListRow.Create;
    Row.Text:=M.Id;
    Row.SearchText:=M.Name+' '+M.Category+' '+M.Description;
    NameLabel:=TArosaLabel.CreateControl(Theme,FontCache);
    NameLabel.Text:=M.Name;
    NameLabel.SetConstraintWidth(asmFixed,ArosaCoord(220));
    Row.AddObject(NameLabel);
    CategoryLabel:=TArosaLabel.CreateControl(Theme,FontCache);
    CategoryLabel.Text:=M.Category;
    CategoryLabel.SetConstraintWidth(asmFixed,ArosaCoord(130));
    Row.AddObject(CategoryLabel);
    StatusLabel:=TArosaLabel.CreateControl(Theme,FontCache);
    StatusLabel.Text:=StatusText(I,M);
    StatusLabel.SetConstraintWidth(asmFixed,ArosaCoord(120));
    Row.AddObject(StatusLabel);
    FStatusLabels.AddObject(M.Id,StatusLabel);
    for K:=0 to 3 do
    begin
      Check:=TArosaCheckBox.CreateControl(Theme,FontCache);
      Check.Caption:='';
      Check.Checked:=M.Available and FPending[I][K];
      { a component that is only planned cannot be ticked }
      Check.Enabled:=M.Available;
      Check.OnChange:=@BoxToggled;
      Check.SetConstraintWidth(asmFixed,ArosaCoord(BoxWidth[K]));
      Row.AddObject(Check);
      FChecks.AddObject(M.Id+'|'+IntToStr(K),Check);
    end;
    FList.AddRow(Row);
  end;
  if FFilter<>nil then FList.Filter:=FFilter.Text;
  FDescription.Text:='';
  UpdateButtons;
end;

procedure TAFileManagerWorkspaceModulesDialog.RefreshRow(AIndex: Integer);
var J, K: Integer; M: TArosaWorkspaceModule;
begin
  if (AIndex<0) or (AIndex>=FIds.Count) or (FModules=nil) or
     not FModules.Find(FIds[AIndex],M) then Exit;
  FUpdating:=True;
  try
    J:=FStatusLabels.IndexOf(M.Id);
    if J>=0 then TArosaLabel(FStatusLabels.Objects[J]).Text:=StatusText(AIndex,M);
    for K:=0 to 3 do
    begin
      J:=FChecks.IndexOf(M.Id+'|'+IntToStr(K));
      if J>=0 then
        TArosaCheckBox(FChecks.Objects[J]).Checked:=M.Available and FPending[AIndex][K];
    end;
  finally
    FUpdating:=False;
  end;
  if FList<>nil then FList.InvalidatePaint;
end;

procedure TAFileManagerWorkspaceModulesDialog.UpdateButtons;
begin
  if FApplyButton<>nil then FApplyButton.Enabled:=HasUnapplied;
  if FRestoreButton<>nil then FRestoreButton.Enabled:=DiffersFromOriginal;
end;

procedure TAFileManagerWorkspaceModulesDialog.BoxToggled(ASender: TArosaControl);
var I, J, K, Box: Integer; Key, IdValue: string; M: TArosaWorkspaceModule;
  Wanted, Anywhere: Boolean;
begin
  { The box sits in a row of the list and this runs inside the input of that
    list: only FPending and the row itself are changed here. }
  if FUpdating or (FModules=nil) or (FChecks=nil) then Exit;
  J:=FChecks.IndexOfObject(ASender);
  if J<0 then Exit;
  Key:=FChecks[J];
  IdValue:=Copy(Key,1,Pos('|',Key)-1);
  Box:=StrToIntDef(Copy(Key,Pos('|',Key)+1,MaxInt),0);
  I:=FIds.IndexOf(IdValue);
  if (I<0) or (Box<0) or (Box>3) or not FModules.Find(IdValue,M) then Exit;
  if not M.Available then
  begin
    RefreshRow(I);
    Exit;
  end;
  Wanted:=TArosaCheckBox(ASender).Checked;
  FPending[I][Box]:=Wanted;
  if Box=0 then
  begin
    if Wanted then
    begin
      { something that joins the workspace shows in its start menu unless
        it is already told to show somewhere }
      Anywhere:=False;
      for K:=1 to 3 do if FPending[I][K] then Anywhere:=True;
      if not Anywhere then FPending[I][1]:=True;
    end
    else
      { what leaves the workspace shows nowhere }
      for K:=1 to 3 do FPending[I][K]:=False;
  end
  else if Wanted then
    { somewhere to show means: part of the workspace }
    FPending[I][0]:=True;
  RefreshRow(I);
  UpdateButtons;
end;

procedure TAFileManagerWorkspaceModulesDialog.ApplyPending;
var I, K: Integer; M: TArosaWorkspaceModule; Now: TAFMModuleBoxes;
begin
  if FModules=nil then Exit;
  for I:=0 to FIds.Count-1 do
  begin
    if not FModules.Find(FIds[I],M) or not M.Available then Continue;
    Now:=Live(M);
    if Now[0]<>FPending[I][0] then
    begin
      if Assigned(FOnChange) then FOnChange(Self,FWorkspaceId,M.Id,FPending[I][0])
      else FModules.SetEnabled(FWorkspaceId,M.Id,FPending[I][0]);
      { joining or leaving changes where the module shows: ask again }
      Now:=Live(M);
    end;
    for K:=1 to 3 do
      if (Now[K]<>FPending[I][K]) and Assigned(FOnPlacement) then
        FOnPlacement(Self,FWorkspaceId,M.Id,K-1,FPending[I][K]);
  end;
  for I:=0 to FIds.Count-1 do RefreshRow(I);
  UpdateButtons;
end;

procedure TAFileManagerWorkspaceModulesDialog.FilterChanged(ASender: TArosaControl);
begin
  if (FList<>nil) and (FFilter<>nil) then FList.Filter:=FFilter.Text;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.SelectionChanged(
  ASender: TArosaControl; AIndex: Integer);
var M: TArosaWorkspaceModule;
begin
  if (FModules<>nil) and FModules.Find(SelectedModuleId,M) then
    FDescription.Text:=M.Description
  else
    FDescription.Text:='';
  if ASender=nil then ;
  if AIndex<0 then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.ApplyClick(ASender: TArosaControl);
begin
  ApplyPending;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.RestoreClick(ASender: TArosaControl);
var I: Integer;
begin
  { back to the configuration the dialog opened with - in the boxes; Apply
    or Save makes it the configuration again if it was applied away }
  for I:=0 to FIds.Count-1 do FPending[I]:=FOriginal[I];
  for I:=0 to FIds.Count-1 do RefreshRow(I);
  UpdateButtons;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.SaveClick(ASender: TArosaControl);
begin
  ApplyPending;
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.CancelClick(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerWorkspaceModulesDialog.ShowModules(
  const AWorkspaceId, AWorkspaceName: string;
  AModules: TArosaWorkspaceModuleService);
var Modules: TArosaWorkspaceModuleArray; I: Integer;
begin
  FWorkspaceId:=Trim(AWorkspaceId);
  FModules:=AModules;
  FTitleLabel.Text:=LocalText('afilemanager_workspace_modules_title',
    'Workspace catalogue')+' - '+AWorkspaceName;
  if FFilter<>nil then FFilter.Text:='';
  { the configuration as it is now: what Restore goes back to }
  FIds.Clear;
  SetLength(FOriginal,0);
  SetLength(FPending,0);
  if FModules<>nil then
  begin
    Modules:=FModules.Catalogue;
    SetLength(FOriginal,Length(Modules));
    SetLength(FPending,Length(Modules));
    for I:=0 to High(Modules) do
    begin
      FIds.Add(Modules[I].Id);
      FOriginal[I]:=Live(Modules[I]);
      FPending[I]:=FOriginal[I];
    end;
  end;
  RebuildList;
  ShowDialog;
end;

function TAFileManagerWorkspaceModulesDialog.TestDescribe: string;
var I, K, J: Integer;
begin
  Result:='';
  for I:=0 to FIds.Count-1 do
  begin
    Result:=Result+' '+FIds[I]+'=';
    J:=FStatusLabels.IndexOf(FIds[I]);
    if J>=0 then Result:=Result+TArosaLabel(FStatusLabels.Objects[J]).Text;
    Result:=Result+'[';
    for K:=0 to 3 do
    begin
      J:=FChecks.IndexOf(FIds[I]+'|'+IntToStr(K));
      if (J>=0) and TArosaCheckBox(FChecks.Objects[J]).Checked then
        Result:=Result+'x' else Result:=Result+'-';
    end;
    Result:=Result+']';
  end;
  Result:=Result+' apply='+BoolToStr(FApplyButton.Enabled,'on','off')+
    ' restore='+BoolToStr(FRestoreButton.Enabled,'on','off')+
    ' open='+BoolToStr(Visible,'yes','no');
end;

function TAFileManagerWorkspaceModulesDialog.TestToggle(
  const AModuleId: string; ABox: Integer): Boolean;
var J: Integer;
begin
  J:=FChecks.IndexOf(AModuleId+'|'+IntToStr(ABox));
  Result:=(J>=0) and TArosaCheckBox(FChecks.Objects[J]).Enabled;
  if Result then TArosaCheckBox(FChecks.Objects[J]).Toggle;
end;

procedure TAFileManagerWorkspaceModulesDialog.TestPress(const AButton: string);
begin
  if SameText(AButton,'apply') then ApplyClick(FApplyButton)
  else if SameText(AButton,'restore') then RestoreClick(FRestoreButton)
  else if SameText(AButton,'save') then SaveClick(FSaveButton)
  else if SameText(AButton,'cancel') then CancelClick(FCancelButton);
end;

constructor TAFileManagerInfoDialog.CreateInfo(ATheme: TArosaTheme;
  AFonts: TArosaFontCache; const AClipboard: IArosaClipboardPlatform;
  AImageLoader: TArosaImageLoaderService; const AInfoFontFamily: string;
  AInfoFontSize: Integer);
var
  Tabs: TArosaTabControl;
  InformationTab, CreditsTab: TArosaTabPage;
  InformationPage, CreditsPage: TArosaColumnPanel;
  Title, Credit, Product, Updates: TArosaLabel;
  Row, Hero: TArosaRowPanel;
  TextCol: TArosaColumnPanel;
  Err: string;
  CreditsHtml: string;
begin
  inherited CreateDialog(ATheme,AFonts,760,620);
  FLogoResource:=nil;
  FInfoFontFamily:=Trim(AInfoFontFamily);
  if FInfoFontFamily='' then FInfoFontFamily:='system';
  FInfoFontSize:=AInfoFontSize;
  if FInfoFontSize<8 then FInfoFontSize:=8
  else if FInfoFontSize>24 then FInfoFontSize:=24;

  Title:=TArosaLabel.CreateControl(ATheme,AFonts);
  Title.Text:='AFileManager Information';
  Title.TextRole:=AROSA_ROLE_ACCENT;
  Title.SetConstraintHeight(asmFixed,ArosaCoord(30));
  ApplyInfoFont(Title);
  Content.AddVisual(Title);

  Tabs:=TArosaTabControl.Create;
  Tabs.Font:=UIFont;
  Tabs.ActiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsPressed);
  Tabs.InactiveBackground:=ATheme.ColourFor(AROSA_ROLE_CONTROL_BG,avsNormal);
  Tabs.ActiveText:=ATheme.ColourFor(AROSA_ROLE_PRIMARY_TEXT,avsNormal);
  Tabs.InactiveText:=ATheme.ColourFor(AROSA_ROLE_SECONDARY_TEXT,avsNormal);
  Tabs.BorderColour:=ATheme.ColourFor(AROSA_ROLE_BORDER,avsNormal);
  Tabs.SetConstraintHeight(asmStar,ArosaCoord(1));
  Content.AddVisual(Tabs);

  InformationTab:=TArosaTabPage.Create;
  InformationTab.Caption:='Information';
  InformationTab.Padding:=ArosaUniformMargins(8);
  Tabs.AddTabPage(InformationTab);
  InformationPage:=TArosaColumnPanel.Create;
  InformationPage.Spacing:=ArosaCoord(8);
  InformationTab.AddVisual(InformationPage);

  Hero:=TArosaRowPanel.Create;
  Hero.Spacing:=ArosaCoord(12);
  Hero.SetConstraintHeight(asmFixed,ArosaCoord(132));

  FLogo:=TArosaImageBox.CreateControl(ATheme,AFonts);
  FLogo.StretchMode:=aismFit;
  FLogo.AltText:='AIDEa';
  FLogo.SetConstraintWidth(asmFixed,ArosaCoord(128));
  FLogo.SetConstraintHeight(asmFixed,ArosaCoord(128));
  if (AImageLoader<>nil) and
     AImageLoader.TryLoadFile('PROGDIR:assets/aidea-info.png',FLogoResource,Err) then
  begin
    FLogo.Bitmap:=FLogoResource.Bitmap;
    FLogo.SourceRect:=ArosaRectXYWH(0,0,FLogoResource.Width,FLogoResource.Height);
  end;
  Hero.AddVisual(FLogo);

  TextCol:=TArosaColumnPanel.Create;
  TextCol.Spacing:=ArosaCoord(5);
  TextCol.SetConstraintWidth(asmStar,ArosaCoord(1));

  Product:=TArosaLabel.CreateControl(ATheme,AFonts);
  Product.Text:='AFileManager / AROSA';
  Product.TextRole:=AROSA_ROLE_PRIMARY_TEXT;
  Product.FontSize:=FInfoFontSize+2;
  Product.FontFamily:=FInfoFontFamily;
  Product.SetConstraintHeight(asmFixed,ArosaCoord(34));
  TextCol.AddVisual(Product);

  Credit:=TArosaLabel.CreateControl(ATheme,AFonts);
  Credit.Text:='Solution idea created with AIDEa by DaniloS';
  Credit.TextRole:=AROSA_ROLE_ACCENT;
  ApplyInfoFont(Credit);
  Credit.SetConstraintHeight(asmFixed,ArosaCoord(34));
  TextCol.AddVisual(Credit);

  Updates:=TArosaLabel.CreateControl(ATheme,AFonts);
  Updates.Text:='Project and engineering links are available below.';
  Updates.TextRole:=AROSA_ROLE_SECONDARY_TEXT;
  ApplyInfoFont(Updates);
  Updates.SetConstraintHeight(asmFixed,ArosaCoord(28));
  TextCol.AddVisual(Updates);

  Hero.AddVisual(TextCol);
  InformationPage.AddVisual(Hero);

  FInfoView:=TArosaHtmlView.CreateHtmlView(ATheme,AFonts,AImageLoader);
  FInfoView.OnLink:=@HtmlLinkClicked;
  FInfoView.SetConstraintHeight(asmStar,ArosaCoord(1));
  InformationPage.AddVisual(FInfoView);

  CreditsTab:=TArosaTabPage.Create;
  CreditsTab.Caption:='Credits';
  CreditsTab.Padding:=ArosaUniformMargins(8);
  Tabs.AddTabPage(CreditsTab);

  CreditsPage:=TArosaColumnPanel.Create;
  CreditsPage.Spacing:=ArosaCoord(8);
  CreditsTab.AddVisual(CreditsPage);

  FCreditsView:=TArosaHtmlView.CreateHtmlView(ATheme,AFonts,AImageLoader);
  FCreditsView.OnLink:=@HtmlLinkClicked;
  FCreditsView.SetConstraintHeight(asmStar,ArosaCoord(1));
  CreditsPage.AddVisual(FCreditsView);

  CreditsHtml:=
    '<html><head><style>'+InfoCss+
    'h2{margin:6px 0;} p{margin:7px 0;} a{color:#2040d0;text-decoration:underline;}' +
    '</style></head><body>'+
    '<h2>AFileManager / AROSA</h2>'+
    '<p>Solution idea created with <a href="https://sourceforge.net/projects/aidea/">AIDEa</a> by DaniloS.</p>'+
    '<h2>AROSA and AROS</h2>'+
    '<p>Built on the AROSA service-oriented application framework and the '+
    '<a href="https://aros.sourceforge.io/">AROS platform</a>.</p>'+
    '<h2>The AROS Team</h2>'+
    '<p>For preserving the spirit of the Amiga within AROS and providing a platform for its future.</p>'+
    '<h2>Lazarus and Free Pascal</h2>'+
    '<p><a href="https://www.lazarus-ide.org/">Lazarus</a> and '+
    '<a href="https://www.freepascal.org/">Free Pascal</a> provide the freely distributable development foundation used by this work.</p>'+
    '<h2>AIDEa</h2>'+
    '<p><a href="https://sourceforge.net/projects/aidea/">AIDEa project page</a> - engineering environment, design mechanisms and development process.</p>'+
    '<h2>Software by others</h2>'+
    '<p>AROSA and AFileManager stand on the work of these people, with thanks.</p>'+
    '<p><b>NanoSVG</b> - Mikko Mononen. zlib licence. '+
    '<a href="https://github.com/memononen/nanosvg">github.com/memononen/nanosvg</a></p>'+
    '<p><b>QuickJS</b> - Fabrice Bellard and Charlie Gordon. MIT licence. '+
    '<a href="https://bellard.org/quickjs/">bellard.org/quickjs</a></p>'+
    '<p><b>SQLite</b> - D. Richard Hipp and the SQLite contributors. Public domain. '+
    '<a href="https://www.sqlite.org/">www.sqlite.org</a></p>'+
    '<p><b>MiniZip</b> - Gilles Vollant, with Zip64 work by Mathias Svensson. zlib licence; part of the zlib distribution.</p>'+
    '<p><b>zlib</b> - Jean-loup Gailly and Mark Adler. zlib licence. '+
    '<a href="https://zlib.net/">zlib.net</a></p>'+
    '<p><b>FreeType</b> - David Turner, Robert Wilhelm, Werner Lemberg and the FreeType contributors. FreeType licence. '+
    '<a href="https://freetype.org/">freetype.org</a></p>'+
    '<p><b>Mbed TLS</b> - the Mbed TLS contributors. Apache 2.0 licence. '+
    '<a href="https://www.trustedfirmware.org/projects/mbed-tls/">trustedfirmware.org</a></p>'+
    '<h2>AFileManager</h2>'+
    '<p><a href="https://sourceforge.net/p/afilemanager/">AFileManager project page</a> - suggestions, reports, downloads and updates.</p>'+
    '</body></html>';
  FCreditsView.LoadHtml(CreditsHtml);

  Row:=TArosaRowPanel.Create;
  Row.SetConstraintHeight(asmFixed,ArosaCoord(34));
  FCloseButton:=TArosaButton.CreateControl(ATheme,AFonts);
  FCloseButton.Caption:='Close';
  FCloseButton.OnClick:=@CloseClick;
  FCloseButton.SetConstraintWidth(asmFixed,ArosaCoord(92));
  Row.AddVisual(FCloseButton);
  Content.AddVisual(Row);

  { Clipboard remains part of the shared dialog signature for compatibility
    with other retained dialogs; HTML selection/copy can be wired later. }
  if AClipboard=nil then ;
end;

function TAFileManagerInfoDialog.InfoCss: string;
begin
  Result:='body{font-family:"'+HtmlEscape(FInfoFontFamily)+'";font-size:'+
    IntToStr(FInfoFontSize)+'px;color:#111;background:#fff;margin:8px;}'+
    'pre{font-family:"'+HtmlEscape(FInfoFontFamily)+'";font-size:'+
    IntToStr(FInfoFontSize)+'px;white-space:pre-wrap;}';
end;

procedure TAFileManagerInfoDialog.HtmlLinkClicked(ASender: TArosaControl;
  const AHref: string);
begin
  if Assigned(FOnExternalLink) then FOnExternalLink(Self,AHref);
  if ASender=nil then ;
end;

procedure TAFileManagerInfoDialog.ApplyInfoFont(AControl: TArosaControl);
begin
  if AControl=nil then Exit;
  AControl.FontFamily:=FInfoFontFamily;
  AControl.FontSize:=FInfoFontSize;
end;

procedure TAFileManagerInfoDialog.DoDispose;
begin
  FreeAndNil(FLogoResource);
  inherited DoDispose;
end;

procedure TAFileManagerInfoDialog.CloseClick(ASender: TArosaControl);
begin
  Dismiss;
  if ASender=nil then ;
end;

procedure TAFileManagerInfoDialog.ShowInfo(const AText: string);
var H: string;
begin
  H:='<html><head><style>'+InfoCss+
    'h2{margin:5px 0;} p{margin:6px 0;} a{color:#2040d0;text-decoration:underline;}' +
    '</style></head><body>'+
    '<p><b>AFileManager project:</b> '+
    '<a href="https://sourceforge.net/p/afilemanager/">https://sourceforge.net/p/afilemanager/</a></p>'+
    '<p><b>AIDEa project:</b> '+
    '<a href="https://sourceforge.net/projects/aidea/">https://sourceforge.net/projects/aidea/</a></p>'+
    '<pre>'+HtmlEscape(AText)+'</pre>'+
    '</body></html>';
  FInfoView.LoadHtml(H);
  ShowDialog;
end;

end.
