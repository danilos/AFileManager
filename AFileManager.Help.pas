// Copyright (c) 2026 DaniloS
// This file is part of the AFileManager project.
// This Source Code Form is subject to the terms of the
// Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

unit AFileManager.Help;

{ AFileManager integrated help system.

  The implementation follows the same externalized documentation mechanism
  used by AIDEa:
    * localized documentation roots;
    * navigation.order controls topic order and hierarchy;
    * HTML content is rendered by the shared AROSA Presentation Service;
    * the application asks for topic identities/paths and never embeds manual
      prose in UI code.

  Help content is supplied from the AFileManager package resource root with English fallback. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils,
  Arosa.ObjectModel, Arosa.Geometry, Arosa.Graphics, Arosa.Platform.Api,
  Arosa.Lifecycle,
  Arosa.UI.Visual, Arosa.UI.Layout, Arosa.UI.Controls, Arosa.UI.Theme,
  Arosa.UI.Forms, Arosa.UI.FormHost, Arosa.UI.CommandBar, Arosa.UI.HtmlView,
  Arosa.Services.System, Arosa.Services.Content, Arosa.Services.Presentation,
  Arosa.Services.Documentation;

type
  TAFileManagerHelpSystem = class(TArosaObject)
  private
    FDocumentation: TArosaDocumentationService;
    FPresentationService: TArosaPresentationService;
    FTheme: TArosaTheme;
    FFonts: TArosaFontCache;
    FLanguageId: string;
    FRootPath: string;
    FApplication: TArosaApplication;

    FForm: TArosaForm;
    FHost: TArosaFormHost;
    FWindowFrame: TArosaWindowFrame;
    FTree: TArosaFilteredTreeView;
    FFilter: TArosaTextBox;
    FDocumentHost: TArosaColumnPanel;
    FCommandBar: TArosaCommandBar;
    FStatus: TArosaLabel;
    FPresentation: TArosaPresentation;
    FClosePending: Boolean;
    FCloseIdleAttached: Boolean;
    FCloseImage: TArosaPlatformHandle;
    FCloseImageSource: TArosaRect;
    FMinimizeImage: TArosaPlatformHandle;
    FMinimizeImageSource: TArosaRect;
    FOwnerWindow: TArosaPlatformHandle;
    FOwnerScreen: TArosaPlatformHandle;
    FNativeDragging: Boolean;
    FNativeDragZone: TArosaWindowHitZone;
    FNativeDragStart: TArosaRect;
    FNativePointerStart: TArosaPoint;
    FPageSearch: TArosaTextBox;
    FPageSearchStatus: TArosaLabel;
    FCommandTextResolver: TArosaCommandTextResolver;
    FCommandIconResolver: TArosaCommandIconResolver;

    function JoinPath(const ABase, ARelative: string): string;
    function ReadText(const APath: string; out AText: string): Boolean;
    function PageExists(const APath: string): Boolean;
    function ParseNavigationEntry(const ALine: string;
      out ACaption, ATarget: string): Boolean;
    procedure PopulateNavigation;
    procedure PopulateFolder(AParent: TArosaTreeNode; const AFolder: string);
    procedure SelectTopic(ASender: TArosaControl; AIndex: Integer);
    procedure FilterChanged(ASender: TArosaControl);
    procedure LoadPage(const APath: string);
    procedure ShowLandingPage;
    procedure PresentationMessage(ASender: TObject; const AText: string);
    procedure PresentationStateChanged(ASender: TObject);
    procedure NativeDrag(AZone: TArosaWindowHitZone; const APosition: TArosaPoint;
      AStarting, AEnding: Boolean);
    procedure PageSearchChanged(ASender: TArosaControl);
    procedure PageFindPrevious(ASender: TArosaControl);
    procedure PageFindNext(ASender: TArosaControl);
    procedure UpdatePageSearchStatus;
    procedure DestroyWindow;
    procedure BuildWindow;
    procedure WindowCloseRequested(ASender: TArosaControl);
    procedure HostCloseRequested;
    procedure QueueClose;
    procedure CloseIdle(var AMoreWorkPending: Boolean);
  protected
    procedure DoDispose; override;
  public
    constructor CreateHelp(APaths: TArosaPathService; AFiles: TArosaFileService;
      APresentationService: TArosaPresentationService; ATheme: TArosaTheme;
      AFonts: TArosaFontCache; const ABasePath, ALanguageId: string);
    procedure Show(AApplication: TArosaApplication);
    procedure ShowTopic(AApplication: TArosaApplication; const ARelativePage: string);
    procedure ConfigureWindowChrome(AFrame: TArosaWindowFrame; AOwnerHost: TArosaFormHost = nil);
    procedure ConfigureCommandResolvers(ATextResolver: TArosaCommandTextResolver;
      AIconResolver: TArosaCommandIconResolver);
    procedure ApplyDocumentFont(const AFamily: string; ASize: Integer);
    procedure CloseForApplicationExit;
    property RootPath: string read FRootPath;
  end;

implementation

constructor TAFileManagerHelpSystem.CreateHelp(APaths: TArosaPathService;
  AFiles: TArosaFileService; APresentationService: TArosaPresentationService;
  ATheme: TArosaTheme; AFonts: TArosaFontCache; const ABasePath, ALanguageId: string);
begin
  inherited Create;
  FDocumentation := TArosaDocumentationService.CreateForApplication(
    APaths,AFiles,ABasePath,ALanguageId);
  FPresentationService := APresentationService;
  FTheme := ATheme;
  FFonts := AFonts;
  FLanguageId := FDocumentation.LanguageId;
  FRootPath := FDocumentation.LocalizedRoot;
  FApplication := nil;
  FClosePending := False;
  FCloseIdleAttached := False;
  FCloseImage := ArosaNilHandle;
  FCloseImageSource := ArosaRectRaw(0,0,0,0);
  FMinimizeImage := ArosaNilHandle;
  FMinimizeImageSource := ArosaRectRaw(0,0,0,0);
  FOwnerWindow := ArosaNilHandle;
  FOwnerScreen := ArosaNilHandle;
  FNativeDragging := False;
  FPageSearch := nil;
  FPageSearchStatus := nil;
  FCommandTextResolver := nil;
  FCommandIconResolver := nil;
  FForm := nil;
  FHost := nil;
  FWindowFrame := nil;
  FTree := nil;
  FFilter := nil;
  FDocumentHost := nil;
  FCommandBar := nil;
  FStatus := nil;
  FPresentation := nil;
end;

function TAFileManagerHelpSystem.JoinPath(const ABase, ARelative: string): string;
var B, R: string;
begin
  B := Trim(ABase);
  R := Trim(ARelative);
  while (Length(R)>0) and (R[1] in ['/', '\']) do Delete(R,1,1);
  if (B='') or (R='') then
  begin
    if R='' then Result:=B else Result:=R;
    Exit;
  end;
  if B[Length(B)] in [':','/','\'] then Result:=B+R else Result:=B+'/'+R;
end;

function TAFileManagerHelpSystem.ReadText(const APath: string;
  out AText: string): Boolean;
begin
  Result := (FDocumentation<>nil) and FDocumentation.ReadText(APath,AText);
end;

function TAFileManagerHelpSystem.PageExists(const APath: string): Boolean;
begin
  Result := (FDocumentation<>nil) and FDocumentation.PageExists(APath);
end;

function TAFileManagerHelpSystem.ParseNavigationEntry(const ALine: string;
  out ACaption, ATarget: string): Boolean;
var S: string; P: Integer;
begin
  ACaption := '';
  ATarget := '';
  S := Trim(ALine);
  if (S='') or (S[1]='#') or (S[1]=';') or (S[1]='%') then Exit(False);
  P := Pos('|',S);
  if P>0 then
  begin
    ACaption := Trim(Copy(S,1,P-1));
    ATarget := Trim(Copy(S,P+1,MaxInt));
  end
  else
  begin
    ATarget := S;
    ACaption := ChangeFileExt(ExtractFileName(S),'');
  end;
  Result := (ACaption<>'') and (ATarget<>'');
end;

procedure TAFileManagerHelpSystem.PopulateFolder(AParent: TArosaTreeNode;
  const AFolder: string);
var
  Text, Line, Caption, Target, ChildFolder, Landing: string;
  Lines: TStringList;
  I: Integer;
  Node: TArosaTreeNode;
begin
  if (AParent=nil) then Exit;
  if (FDocumentation=nil) or not FDocumentation.ReadNavigation(AFolder,Text) then
  begin
    if FStatus<>nil then FStatus.Text:='Navigation not readable: '+JoinPath(AFolder,'navigation.order');
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I:=0 to Lines.Count-1 do
    begin
      Line := Lines[I];
      if not ParseNavigationEntry(Line,Caption,Target) then Continue;
      if Target[1]='@' then
      begin
        ChildFolder := JoinPath(AFolder,Copy(Target,2,MaxInt));
        Node := AParent.AddChild(Caption);
        Node.Expanded := False;
        Landing := JoinPath(ChildFolder,'index.html');
        if PageExists(Landing) then Node.Hint := Landing;
        PopulateFolder(Node,ChildFolder);
      end
      else
      begin
        Node := AParent.AddChild(Caption);
        Node.Hint := JoinPath(AFolder,Target);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TAFileManagerHelpSystem.PopulateNavigation;
var Root: TArosaTreeNode;
begin
  if FTree=nil then Exit;
  Root := FTree.RootNode;
  Root.ClearChildren;
  Root.Text := 'AFileManager Help';
  Root.Expanded := True;
  Root.Hint := JoinPath(FRootPath,'index.html');
  PopulateFolder(Root,FRootPath);
  FTree.Rebuild;
end;

procedure TAFileManagerHelpSystem.PresentationMessage(ASender: TObject;
  const AText: string);
begin
  if FStatus<>nil then FStatus.Text:=AText;
end;

procedure TAFileManagerHelpSystem.LoadPage(const APath: string);
var
  Pres: TArosaPresentation;
  Content: TArosaContentDescriptor;
  ErrorText: string;
  C: TArosaControl;
begin
  if (FPresentationService=nil) or (FDocumentHost=nil) then Exit;
  if not PageExists(APath) then
  begin
    if FStatus<>nil then FStatus.Text:='Help topic not found: '+APath;
    Exit;
  end;

  if FCommandBar<>nil then FCommandBar.Unbind;
  if (FPresentation<>nil) and (FPresentation.Control<>nil) then
    FDocumentHost.RemoveVisual(FPresentation.Control);
  FreeAndNil(FPresentation);

  Pres := nil;
  if not FPresentationService.CreatePresentationForLocation(
    APath,apmDocument,True,Pres,Content,ErrorText) then
  begin
    if FStatus<>nil then FStatus.Text:='Unable to open help topic: '+ErrorText;
    Exit;
  end;
  FPresentation := Pres;
  FPresentation.OnMessage := @PresentationMessage;
  FPresentation.OnStateChanged := @PresentationStateChanged;
  if not FPresentation.Load(ErrorText) then
  begin
    FreeAndNil(FPresentation);
    if FStatus<>nil then FStatus.Text:='Unable to render help topic: '+ErrorText;
    Exit;
  end;

  C := FPresentation.Control;
  if C<>nil then
  begin
    C.SetConstraintWidth(asmStar,ArosaCoord(1));
    C.SetConstraintHeight(asmStar,ArosaCoord(1));
    FDocumentHost.AddVisual(C);
  end;
  if FCommandBar<>nil then FCommandBar.Bind(FPresentation,FPresentation);
  if FPageSearch<>nil then FPageSearch.Text:='';
  UpdatePageSearchStatus;
  if FStatus<>nil then FStatus.Text:=APath;
end;

procedure TAFileManagerHelpSystem.ShowLandingPage;
var P: string;
begin
  P := JoinPath(FRootPath,'index.html');
  if PageExists(P) then
    LoadPage(P)
  else if FStatus<>nil then
    FStatus.Text:='Help landing page not found: '+P;
end;

procedure TAFileManagerHelpSystem.SelectTopic(ASender: TArosaControl;
  AIndex: Integer);
var N: TArosaTreeNode;
begin
  if FTree=nil then Exit;
  N := FTree.SelectedNode;
  if (N<>nil) and (Trim(N.Hint)<>'') then LoadPage(N.Hint);
end;

procedure TAFileManagerHelpSystem.FilterChanged(ASender: TArosaControl);
begin
  if (FTree<>nil) and (FFilter<>nil) then FTree.SetFilter(FFilter.Text);
end;

procedure TAFileManagerHelpSystem.BuildWindow;
var
  Main: TArosaSplitterHost;
  Left: TArosaColumnPanel;
  FilterRow, PageSearchRow: TArosaRowPanel;
  LabelFilter, LabelSearch: TArosaLabel;
  PrevButton, NextButton: TArosaButton;
  WindowFrame: TArosaWindowFrame;
  Img: TArosaPlatformHandle;
  Src: TArosaRect;
begin
  if FApplication=nil then Exit;
  if FDocumentation<>nil then FRootPath := FDocumentation.LocalizedRoot;

  FForm := TArosaForm.Create;
  FForm.Caption := 'AFileManager Help';
  FForm.Resizable := True;
  FForm.BorderStyle := afbsNone;
  FForm.WindowBounds := ArosaRectXYWH(70,55,920,650);
  FForm.MinSize := ArosaSize(680,460);

  { Help is an AROSA window, not a Workbench-decorated application window.
    The native host is borderless; TArosaWindowFrame supplies the visible
    title/chrome and closes through the same retained AROSA control path as
    AFileManager itself. }
  WindowFrame := TArosaWindowFrame.CreateControl(FTheme,FFonts);
  FWindowFrame := WindowFrame;
  WindowFrame.NativeDecorations := False;
  WindowFrame.Title := 'AFileManager Help';
  WindowFrame.Active := True;
  WindowFrame.ShowCloseGadget := True;
  WindowFrame.ShowMenuGadget := False;
  WindowFrame.CloseGadget.Visible := True;
  { Help has no application menu yet.  Do not display a non-functional burger.
    When Help gains a menu it will use this same TArosaWindowFrame gadget and
    therefore the same AFileManager/AROSA theme icon automatically. }
  WindowFrame.MenuGadget.Visible := False;
  WindowFrame.OnCloseRequest := @WindowCloseRequested;
  WindowFrame.OnNativeDrag := @NativeDrag;
  if FCloseImage<>ArosaNilHandle then
  begin
    WindowFrame.CloseGadget.Image := FCloseImage;
    WindowFrame.CloseGadget.ImageSourceRect := FCloseImageSource;
  end;
  if FMinimizeImage<>ArosaNilHandle then
  begin
    WindowFrame.MinimizeGadget.Image := FMinimizeImage;
    WindowFrame.MinimizeGadget.ImageSourceRect := FMinimizeImageSource;
  end;
  WindowFrame.SetConstraintWidth(asmStar,ArosaCoord(1));
  WindowFrame.SetConstraintHeight(asmStar,ArosaCoord(1));
  FForm.AddVisual(WindowFrame);

  Main := TArosaSplitterHost.Create;
  Main.Orientation := aorHorizontal;
  Main.DividerThickness := ArosaCoord(6);
  Main.MinFirst := ArosaCoord(190);
  Main.MinSecond := ArosaCoord(360);
  Main.SetInitialPercent(28);
  Main.SetConstraintWidth(asmStar,ArosaCoord(1));
  Main.SetConstraintHeight(asmStar,ArosaCoord(1));
  WindowFrame.ClientContent := Main;

  Left := TArosaColumnPanel.Create;
  Left.Spacing := ArosaCoord(4);
  Left.SetConstraintWidth(asmStar,ArosaCoord(1));
  Left.SetConstraintHeight(asmStar,ArosaCoord(1));

  FilterRow := TArosaRowPanel.Create;
  FilterRow.Spacing := ArosaCoord(4);
  FilterRow.SetConstraintHeight(asmFixed,ArosaCoord(26));
  LabelFilter := TArosaLabel.CreateControl(FTheme,FFonts);
  LabelFilter.Text := 'Topics:';
  LabelFilter.SetConstraintWidth(asmFixed,ArosaCoord(42));
  FilterRow.AddVisual(LabelFilter);
  FFilter := TArosaTextBox.CreateControl(FTheme,FFonts);
  FFilter.Hint := 'Filter help topics by title.';
  FFilter.OnChange := @FilterChanged;
  FFilter.SetConstraintWidth(asmStar,ArosaCoord(1));
  FilterRow.AddVisual(FFilter);
  Left.AddVisual(FilterRow);

  FTree := TArosaFilteredTreeView.CreateControl(FTheme,FFonts);
  FTree.Hint := 'Select a help topic.';
  FTree.OnSelect := @SelectTopic;
  FTree.SetConstraintWidth(asmStar,ArosaCoord(1));
  FTree.SetConstraintHeight(asmStar,ArosaCoord(1));
  Left.AddVisual(FTree);

  FDocumentHost := TArosaColumnPanel.Create;
  FDocumentHost.Spacing := ArosaCoord(2);
  FDocumentHost.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDocumentHost.SetConstraintHeight(asmStar,ArosaCoord(1));

  PageSearchRow := TArosaRowPanel.Create;
  PageSearchRow.Spacing := ArosaCoord(4);
  PageSearchRow.SetConstraintHeight(asmFixed,ArosaCoord(26));
  LabelSearch := TArosaLabel.CreateControl(FTheme,FFonts);
  LabelSearch.Text := 'Find in page:';
  { Reserve the complete caption and align it toward the search field. The
    previous 88-unit slot clipped the text even when the row had spare room. }
  LabelSearch.HorizontalAlignment := AROSA_ALIGN_FAR;
  LabelSearch.SetConstraintWidth(asmFixed,ArosaCoord(116));
  PageSearchRow.AddVisual(LabelSearch);
  FPageSearch := TArosaTextBox.CreateControl(FTheme,FFonts);
  FPageSearch.Hint := 'Search all rendered text in the current HTML page.';
  FPageSearch.OnChange := @PageSearchChanged;
  FPageSearch.SetConstraintWidth(asmStar,ArosaCoord(1));
  PageSearchRow.AddVisual(FPageSearch);
  PrevButton := TArosaButton.CreateControl(FTheme,FFonts);
  PrevButton.Caption := 'Previous';
  PrevButton.Hint := 'Previous match';
  PrevButton.ContextTitle := 'Previous';
  PrevButton.OnClick := @PageFindPrevious;
  if Assigned(FCommandIconResolver) then
  begin
    if FCommandIconResolver('app:previous',Img,Src) then
    begin
      PrevButton.Image:=Img; PrevButton.ImageSourceRect:=Src; PrevButton.Caption:='';
      PrevButton.SetConstraintWidth(asmFixed,ArosaCoord(28));
    end
    else PrevButton.SetConstraintWidth(asmFixed,ArosaCoord(76));
  end
  else PrevButton.SetConstraintWidth(asmFixed,ArosaCoord(76));
  PageSearchRow.AddVisual(PrevButton);

  NextButton := TArosaButton.CreateControl(FTheme,FFonts);
  NextButton.Caption := 'Next';
  NextButton.Hint := 'Next match';
  NextButton.ContextTitle := 'Next';
  NextButton.OnClick := @PageFindNext;
  if Assigned(FCommandIconResolver) then
  begin
    if FCommandIconResolver('app:next',Img,Src) then
    begin
      NextButton.Image:=Img; NextButton.ImageSourceRect:=Src; NextButton.Caption:='';
      NextButton.SetConstraintWidth(asmFixed,ArosaCoord(28));
    end
    else NextButton.SetConstraintWidth(asmFixed,ArosaCoord(58));
  end
  else NextButton.SetConstraintWidth(asmFixed,ArosaCoord(58));
  PageSearchRow.AddVisual(NextButton);
  FPageSearchStatus := TArosaLabel.CreateControl(FTheme,FFonts);
  FPageSearchStatus.Text := '';
  FPageSearchStatus.HorizontalAlignment := AROSA_ALIGN_FAR;
  FPageSearchStatus.SetConstraintWidth(asmFixed,ArosaCoord(72));
  PageSearchRow.AddVisual(FPageSearchStatus);
  FDocumentHost.AddVisual(PageSearchRow);

  FCommandBar := TArosaCommandBar.CreateBar(FTheme,FFonts);
  FCommandBar.TextResolver := FCommandTextResolver;
  FCommandBar.IconResolver := FCommandIconResolver;
  FCommandBar.SetConstraintWidth(asmStar,ArosaCoord(1));
  FDocumentHost.AddVisual(FCommandBar);

  Main.SetPanes(Left,FDocumentHost);

  FStatus := TArosaLabel.CreateControl(FTheme,FFonts);
  FStatus.Text := 'AFileManager Help';
  FStatus.SetConstraintHeight(asmFixed,ArosaCoord(22));
  { Keep the status in the document column so the help window stays simple
    and fully retained-platform neutral. }
  FDocumentHost.AddVisual(FStatus);

  FHost := TArosaFormHost.Create(FApplication,FForm);
  FHost.CloseTerminatesApplication := False;
  if FOwnerScreen<>ArosaNilHandle then
    FHost.TargetScreen:=FOwnerScreen;
  { Native close notifications on a secondary Help window must never close or
    terminate the AFileManager application.  They are normalized to Hide. }
  FHost.OnCloseRequest := @HostCloseRequested;
  FHost.Open;
  if FOwnerWindow<>ArosaNilHandle then FHost.CenterOn(FOwnerWindow);

  PopulateNavigation;
  ShowLandingPage;
end;

procedure TAFileManagerHelpSystem.QueueClose;
begin
  if FClosePending then Exit;
  FClosePending:=True;
  if (FApplication<>nil) and (FApplication.Loop<>nil) and not FCloseIdleAttached then
  begin
    FApplication.Loop.AddIdleHandler(@CloseIdle);
    FCloseIdleAttached:=True;
  end;
end;

procedure TAFileManagerHelpSystem.CloseIdle(var AMoreWorkPending: Boolean);
begin
  if FCloseIdleAttached and (FApplication<>nil) and (FApplication.Loop<>nil) then
  begin
    FApplication.Loop.RemoveIdleHandler(@CloseIdle);
    FCloseIdleAttached:=False;
  end;
  FClosePending:=False;
  { AROS Release 1 cannot hide an Intuition window: ShowWindow(False) only
    changes retained state.  Close the secondary native host in idle, after
    the gadget/native close event has returned.  The Help object itself stays
    alive and rebuilds the host on the next Show. }
  if (FHost<>nil) and not FHost.Closed then FHost.Close;
  AMoreWorkPending:=False;
end;

procedure TAFileManagerHelpSystem.WindowCloseRequested(ASender: TArosaControl);
begin
  QueueClose;
  if ASender=nil then ;
end;

procedure TAFileManagerHelpSystem.HostCloseRequested;
begin
  QueueClose;
end;


procedure TAFileManagerHelpSystem.ConfigureCommandResolvers(
  ATextResolver: TArosaCommandTextResolver; AIconResolver: TArosaCommandIconResolver);
begin
  FCommandTextResolver := ATextResolver;
  FCommandIconResolver := AIconResolver;
  if FCommandBar<>nil then
  begin
    FCommandBar.TextResolver := FCommandTextResolver;
    FCommandBar.IconResolver := FCommandIconResolver;
  end;
end;

procedure TAFileManagerHelpSystem.ConfigureWindowChrome(AFrame: TArosaWindowFrame; AOwnerHost: TArosaFormHost);
begin
  if AOwnerHost<>nil then
  begin
    FOwnerWindow:=AOwnerHost.Window;
    FOwnerScreen:=AOwnerHost.TargetScreen;
  end;
  if AFrame=nil then Exit;
  FCloseImage:=AFrame.CloseGadget.Image;
  FCloseImageSource:=AFrame.CloseGadget.ImageSourceRect;
  FMinimizeImage:=AFrame.MinimizeGadget.Image;
  FMinimizeImageSource:=AFrame.MinimizeGadget.ImageSourceRect;
  if FWindowFrame<>nil then
  begin
    if FCloseImage<>ArosaNilHandle then
    begin
      FWindowFrame.CloseGadget.Image:=FCloseImage;
      FWindowFrame.CloseGadget.ImageSourceRect:=FCloseImageSource;
    end;
    if FMinimizeImage<>ArosaNilHandle then
    begin
      FWindowFrame.MinimizeGadget.Image:=FMinimizeImage;
      FWindowFrame.MinimizeGadget.ImageSourceRect:=FMinimizeImageSource;
    end;
  end;
end;

procedure TAFileManagerHelpSystem.ApplyDocumentFont(
  const AFamily: string; ASize: Integer);
var
  Family: string;

  procedure ApplyTo(C: TArosaControl);
  begin
    if C=nil then Exit;
    C.FontFamily:=Family;
    C.FontSize:=ASize;
    C.InvalidateLayout;
    C.InvalidatePaint;
  end;

begin
  Family:=Trim(AFamily);
  if Family='' then Family:='system';
  if ASize<8 then ASize:=8 else if ASize>24 then ASize:=24;

  ApplyTo(FTree);
  ApplyTo(FFilter);
  ApplyTo(FPageSearch);
  ApplyTo(FPageSearchStatus);
  ApplyTo(FStatus);

  { Current HTML presentation uses the shared theme's afrDocument role. A
    refresh recreates its document layout with the just-applied role. }
  if FPresentation<>nil then
    FPresentation.Refresh;

  if FForm<>nil then
  begin
    FForm.InvalidateLayout;
    FForm.InvalidatePaint;
  end;
end;

procedure TAFileManagerHelpSystem.CloseForApplicationExit;
begin
  if FCloseIdleAttached and (FApplication<>nil) and (FApplication.Loop<>nil) then
  begin
    FApplication.Loop.RemoveIdleHandler(@CloseIdle);
    FCloseIdleAttached:=False;
  end;
  FClosePending:=False;
  if (FHost<>nil) and not FHost.Closed then FHost.Close;
end;

procedure TAFileManagerHelpSystem.PresentationStateChanged(ASender: TObject);
begin
  if FCommandBar<>nil then FCommandBar.RefreshState;
  UpdatePageSearchStatus;
  if ASender=nil then ;
end;

procedure TAFileManagerHelpSystem.UpdatePageSearchStatus;
var V: TArosaHtmlView; N,I: Integer;
begin
  if FPageSearchStatus=nil then Exit;
  FPageSearchStatus.Text:='';
  if (FPresentation=nil) or not (FPresentation.Control is TArosaHtmlView) then Exit;
  V:=TArosaHtmlView(FPresentation.Control); N:=V.SearchMatchCount; I:=V.SearchMatchIndex;
  if Trim(V.SearchText)='' then Exit;
  if N=0 then FPageSearchStatus.Text:='0 matches'
  else FPageSearchStatus.Text:=IntToStr(I+1)+' / '+IntToStr(N);
end;

procedure TAFileManagerHelpSystem.PageSearchChanged(ASender: TArosaControl);
var V: TArosaHtmlView;
begin
  if (FPresentation<>nil) and (FPresentation.Control is TArosaHtmlView) and (FPageSearch<>nil) then
  begin
    V:=TArosaHtmlView(FPresentation.Control);
    V.Search(FPageSearch.Text); UpdatePageSearchStatus;
  end;
  if ASender=nil then ;
end;

procedure TAFileManagerHelpSystem.PageFindPrevious(ASender: TArosaControl);
var V: TArosaHtmlView;
begin
  if (FPresentation<>nil) and (FPresentation.Control is TArosaHtmlView) then
  begin V:=TArosaHtmlView(FPresentation.Control); V.FindPrevious; UpdatePageSearchStatus; end;
  if ASender=nil then ;
end;

procedure TAFileManagerHelpSystem.PageFindNext(ASender: TArosaControl);
var V: TArosaHtmlView;
begin
  if (FPresentation<>nil) and (FPresentation.Control is TArosaHtmlView) then
  begin V:=TArosaHtmlView(FPresentation.Control); V.FindNext; UpdatePageSearchStatus; end;
  if ASender=nil then ;
end;

procedure TAFileManagerHelpSystem.NativeDrag(AZone: TArosaWindowHitZone;
  const APosition: TArosaPoint; AStarting, AEnding: Boolean);
var R,N: TArosaRect; X,Y,DX,DY,L,T,RR,B: Integer;
begin
  if (FHost=nil) or (FHost.Window=ArosaNilHandle) or (FApplication=nil) or
     (FApplication.PlatformBackend=nil) or (FApplication.PlatformBackend.Windows=nil) then Exit;
  R:=FApplication.PlatformBackend.Windows.GetWindowBounds(FHost.Window);
  if AStarting then
  begin
    FNativeDragging:=True; FNativeDragZone:=AZone; FNativeDragStart:=R;
    FNativePointerStart:=ArosaPointRaw(R.Left+APosition.X,R.Top+APosition.Y); Exit;
  end;
  if AEnding then begin FNativeDragging:=False; Exit; end;
  if not FNativeDragging then Exit;
  X:=ArosaCoordWhole(R.Left+APosition.X); Y:=ArosaCoordWhole(R.Top+APosition.Y);
  DX:=X-ArosaCoordWhole(FNativePointerStart.X); DY:=Y-ArosaCoordWhole(FNativePointerStart.Y);
  L:=ArosaCoordWhole(FNativeDragStart.Left); T:=ArosaCoordWhole(FNativeDragStart.Top);
  RR:=ArosaCoordWhole(FNativeDragStart.Right); B:=ArosaCoordWhole(FNativeDragStart.Bottom);
  case FNativeDragZone of
    awhzTitle: begin Inc(L,DX); Inc(RR,DX); Inc(T,DY); Inc(B,DY); end;
    awhzLeft: Inc(L,DX); awhzRight: Inc(RR,DX); awhzTop: Inc(T,DY); awhzBottom: Inc(B,DY);
    awhzTopLeft: begin Inc(L,DX); Inc(T,DY); end;
    awhzTopRight: begin Inc(RR,DX); Inc(T,DY); end;
    awhzBottomLeft: begin Inc(L,DX); Inc(B,DY); end;
    awhzBottomRight: begin Inc(RR,DX); Inc(B,DY); end;
  else Exit; end;
  if RR-L<680 then if FNativeDragZone in [awhzLeft,awhzTopLeft,awhzBottomLeft] then L:=RR-680 else RR:=L+680;
  if B-T<460 then if FNativeDragZone in [awhzTop,awhzTopLeft,awhzTopRight] then T:=B-460 else B:=T+460;
  N:=ArosaRectXYWH(L,T,RR-L,B-T); FHost.SetWindowBounds(N);
end;

procedure TAFileManagerHelpSystem.DestroyWindow;
begin
  if FCloseIdleAttached and (FApplication<>nil) and (FApplication.Loop<>nil) then
  begin
    FApplication.Loop.RemoveIdleHandler(@CloseIdle);
    FCloseIdleAttached:=False;
  end;
  FClosePending:=False;
  if FCommandBar<>nil then FCommandBar.Unbind;
  if (FPresentation<>nil) and (FPresentation.Control<>nil) and
     (FDocumentHost<>nil) then
    FDocumentHost.RemoveVisual(FPresentation.Control);
  FreeAndNil(FPresentation);
  FreeAndNil(FHost);
  FreeAndNil(FForm);
  FWindowFrame := nil;
  FTree := nil;
  FFilter := nil;
  FDocumentHost := nil;
  FCommandBar := nil;
  FStatus := nil;
  FPageSearch := nil;
  FPageSearchStatus := nil;
  { Command resolvers describe the owning application, not one native Help
    window.  Keep them across close/rebuild so a reopened Help window still
    inherits application text/icon resources before falling back to AROSA. }
end;

procedure TAFileManagerHelpSystem.Show(AApplication: TArosaApplication);
begin
  if AApplication=nil then Exit;
  FApplication := AApplication;
  if (FHost<>nil) and (not FHost.Closed) then
  begin
    FHost.Show;
    Exit;
  end;
  DestroyWindow;
  BuildWindow;
end;

procedure TAFileManagerHelpSystem.ShowTopic(AApplication: TArosaApplication;
  const ARelativePage: string);
begin
  Show(AApplication);
  if (FHost=nil) or FHost.Closed then Exit;
  if Trim(ARelativePage)<>'' then
    LoadPage(JoinPath(FRootPath,ARelativePage));
end;

procedure TAFileManagerHelpSystem.DoDispose;
begin
  DestroyWindow;
  FApplication := nil;
  FreeAndNil(FDocumentation);
  FPresentationService := nil;
  FTheme := nil;
  FFonts := nil;
  inherited DoDispose;
end;

end.
