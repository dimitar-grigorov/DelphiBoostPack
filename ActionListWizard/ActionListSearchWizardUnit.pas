unit ActionListSearchWizardUnit;

interface

uses
  ToolsAPI, Classes, ActnList, Forms, StdCtrls, Controls, ExtCtrls, SysUtils,
  DockForm, Windows, AppEvnts, ComCtrls, Graphics, Registry;

type
  TActionListSearchWizard = class(TNotifierObject, IOTAWizard, IOTANotifier)
  private
    evApplication: TApplicationEvents;
    pnlSearch: TPanel;
    lblSearch: TLabel;
    edSearch: TEdit;
    lvActionList: TListView;
  private
    FDefaultWidth: Integer;
    FDefaultHeight: Integer;
    procedure SearchEditChange(Sender: TObject);
    procedure SearchEditEnter(Sender: TObject);
    procedure SearchEditExit(Sender: TObject);
    procedure ApplicationEventsIdle(Sender: TObject; var Done: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure AddSearchFunctionality(aForm: TForm);    
    procedure SaveFormSizeToRegistry(aForm: TForm);
    procedure LoadFormSizeFromRegistry(aForm: TForm);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Execute;
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
  end;

procedure Register;

implementation

uses
  Dialogs;

const
  REG_PATH = 'Software\Speedy\ActionListSearchWizard';
  REG_FORM_HEIGHT = 'FormHeight';
  REG_FORM_WIDTH = 'FormWidth';
  REG_FORM_LEFT = 'FormLeft';
  REG_FORM_TOP = 'FormTop';
  SEARCH_PANEL_CONTROL_NAME = 'pnlSearch';

resourcestring
  SSearchPlaceholder = 'Search...';

procedure Register;
begin
  RegisterPackageWizard(TActionListSearchWizard.Create as IOTAWizard);
end;

constructor TActionListSearchWizard.Create;
begin
  inherited Create;
  evApplication := TApplicationEvents.Create(nil);
  evApplication.OnIdle := ApplicationEventsIdle;
end;

destructor TActionListSearchWizard.Destroy;
begin
  evApplication.Free;
  inherited Destroy;
end;

procedure TActionListSearchWizard.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveFormSizeToRegistry(TForm(Sender));
  Action := caFree;
end;

procedure TActionListSearchWizard.ApplicationEventsIdle(Sender: TObject; var Done: Boolean);
var
  I: Integer;
  lvSearchPanel: TPanel;
begin
  Done := True;
  for I := 0 to Screen.FormCount - 1 do
  begin
    if Screen.Forms[I].ClassName = 'TActionListDesigner' then
    begin
      lvSearchPanel := Screen.Forms[I].FindComponent(SEARCH_PANEL_CONTROL_NAME) as TPanel;
      if not Assigned(lvSearchPanel) then
      begin
        AddSearchFunctionality(Screen.Forms[I]);
        Done := False;
      end;
    end;
  end;
end;

procedure TActionListSearchWizard.AddSearchFunctionality(aForm: TForm);
const
  CONTROLS_OFFSET = 8;
var
  lvToolBar1: TToolBar;
  I: Integer;
begin
  if (aForm.FindComponent(SEARCH_PANEL_CONTROL_NAME) <> nil) then
    Exit;

  lvActionList := aForm.FindComponent('ListView1') as TListView;
  if not Assigned(lvActionList) then
  begin
    ShowMessage('ListView1 not found on form: ' + aForm.Name);
    Exit;
  end;

  lvToolBar1 := aForm.FindComponent('ToolBar1') as TToolBar;
  if not Assigned(lvToolBar1) then
  begin
    ShowMessage('ToolBar1 not found on form: ' + aForm.Name);
    Exit;
  end;

  pnlSearch := TPanel.Create(aForm);
  pnlSearch.Name := SEARCH_PANEL_CONTROL_NAME;
  pnlSearch.Parent := aForm;
  pnlSearch.Height := 30;
  pnlSearch.Caption := '';
  pnlSearch.Top := lvToolBar1.Top + lvToolBar1.Height;
  pnlSearch.Align := alTop;
  //Move all the controls that are below pnlSearch
  for I := 0 to aForm.ControlCount - 1 do
  begin
    if (aForm.Controls[I] <> pnlSearch) and (aForm.Controls[I].Top >= pnlSearch.Top) then
      aForm.Controls[I].Top := aForm.Controls[I].Top + pnlSearch.Height;
  end;

  lblSearch := TLabel.Create(pnlSearch);
  lblSearch.Parent := pnlSearch;
  lblSearch.Caption := 'Search:';
  lblSearch.Left := CONTROLS_OFFSET;
  lblSearch.Top := CONTROLS_OFFSET;

  edSearch := TEdit.Create(pnlSearch);
  edSearch.Parent := pnlSearch;
  edSearch.Left := lblSearch.Left + lblSearch.Width + CONTROLS_OFFSET;
  edSearch.Top := 4;
  edSearch.Width := pnlSearch.Width - (lblSearch.Left + lblSearch.Width + 2 * CONTROLS_OFFSET);
  edSearch.Anchors := [akTop, akLeft, akRight];
  edSearch.Name := 'edSearch';
  edSearch.Text := SSearchPlaceholder;
  edSearch.Font.Color := clGray;
  edSearch.OnEnter := SearchEditEnter;
  edSearch.OnExit := SearchEditExit;
  edSearch.OnChange := SearchEditChange;

  aForm.OnClose := FormClose;

  // First store default sizes
  FDefaultWidth := aForm.Width;
  FDefaultHeight := aForm.Height;
  // Then load the Size from Registry
  LoadFormSizeFromRegistry(aForm);
end;

procedure TActionListSearchWizard.SearchEditChange(Sender: TObject);
var
  I: Integer;
  lvSearchText: string;
  lvListItem: TListItem;
  lvFirstMatch: TListItem;
begin
  if not Assigned(lvActionList) then
  begin
    ShowMessage('ActionListView not found');
    Exit;
  end;

  lvSearchText := TEdit(Sender).Text;
  if (Length(lvSearchText) < 2) or (lvSearchText = SSearchPlaceholder) then
    Exit; // Only search with at least 2 characters

  lvActionList.Items.BeginUpdate;
  try
    lvFirstMatch := nil;
    for I := 0 to lvActionList.Items.Count - 1 do
    begin
      lvListItem := lvActionList.Items[I];
      if Pos(LowerCase(lvSearchText), LowerCase(lvListItem.Caption)) > 0 then
      begin
        lvListItem.Selected := True;
        if lvFirstMatch = nil then
          lvFirstMatch := lvListItem;
      end
      else
        lvListItem.Selected := False;
    end;

    if Assigned(lvFirstMatch) then
    begin
      lvActionList.Selected := lvFirstMatch;
      lvFirstMatch.MakeVisible(False);
    end;
  finally
    lvActionList.Items.EndUpdate;
  end;
  // Keep the focus on the edit control
  if TEdit(Sender).CanFocus then
    TEdit(Sender).SetFocus;
end;

procedure TActionListSearchWizard.SearchEditEnter(Sender: TObject);
begin
  if TEdit(Sender).Text = SSearchPlaceholder then
  begin
    TEdit(Sender).Text := '';
    TEdit(Sender).Font.Color := clWindowText;
  end;
end;

procedure TActionListSearchWizard.SearchEditExit(Sender: TObject);
begin
  if TEdit(Sender).Text = '' then
  begin
    TEdit(Sender).Text := SSearchPlaceholder;
    TEdit(Sender).Font.Color := clGray;
  end;
end;

procedure TActionListSearchWizard.SaveFormSizeToRegistry(aForm: TForm);
var
  lvRegistry: TRegistry;
  lvScreenRect: TRect;
begin
  lvScreenRect := Screen.MonitorFromWindow(aForm.Handle).WorkareaRect;

  // Ensure the form is within screen bounds
  if (aForm.Left < lvScreenRect.Left) or (aForm.Top < lvScreenRect.Top) or
     (aForm.Left + aForm.Width > lvScreenRect.Right) or (aForm.Top + aForm.Height > lvScreenRect.Bottom) then
    Exit;

  lvRegistry := TRegistry.Create;
  try
    lvRegistry.RootKey := HKEY_CURRENT_USER;
    if lvRegistry.OpenKey(REG_PATH, True) then
    begin
      lvRegistry.WriteInteger(REG_FORM_WIDTH, aForm.Width);
      lvRegistry.WriteInteger(REG_FORM_HEIGHT, aForm.Height);
      lvRegistry.WriteInteger(REG_FORM_LEFT, aForm.Left);
      lvRegistry.WriteInteger(REG_FORM_TOP, aForm.Top);
      lvRegistry.CloseKey;
    end;
  finally
    lvRegistry.Free;
  end;
end;

procedure TActionListSearchWizard.LoadFormSizeFromRegistry(aForm: TForm);
var
  lvRegistry: TRegistry;
  lvWidth, lvHeight: Integer;
begin
  lvRegistry := TRegistry.Create;
  try
    lvRegistry.RootKey := HKEY_CURRENT_USER;
    if lvRegistry.OpenKey(REG_PATH, False) then
    begin
      if lvRegistry.ValueExists(REG_FORM_WIDTH) then
      begin
        lvWidth := lvRegistry.ReadInteger(REG_FORM_WIDTH);
        if lvWidth >= FDefaultWidth then
          aForm.Width := lvWidth;
      end;

      if lvRegistry.ValueExists(REG_FORM_HEIGHT) then
      begin
        lvHeight := lvRegistry.ReadInteger(REG_FORM_HEIGHT);
        if lvHeight >= FDefaultHeight then
          aForm.Height := lvHeight;
      end;

      if lvRegistry.ValueExists(REG_FORM_LEFT) then
        aForm.Left := lvRegistry.ReadInteger(REG_FORM_LEFT);

      if lvRegistry.ValueExists(REG_FORM_TOP) then
        aForm.Top := lvRegistry.ReadInteger(REG_FORM_TOP);

      lvRegistry.CloseKey;
    end;
  finally
    lvRegistry.Free;
  end;
end;

procedure TActionListSearchWizard.Execute;
begin
  //
end;

function TActionListSearchWizard.GetIDString: string;
begin
  Result := 'ActionListSearchWizard';
end;

function TActionListSearchWizard.GetName: string;
begin
  Result := 'Action List Search Wizard';
end;

function TActionListSearchWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

end.

