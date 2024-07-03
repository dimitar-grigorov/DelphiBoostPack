unit ActionListSearchWizardUnit;

interface

uses
  ToolsAPI, Classes, ActnList, Forms, StdCtrls, Controls, ExtCtrls, SysUtils,
  DockForm, Windows, AppEvnts, ComCtrls, Graphics, Registry;

type
  TActionListSearchWizard = class(TNotifierObject, IOTAWizard, IOTANotifier)
  private
    FApplicationEvents: TApplicationEvents;
    FSearchPanel: TPanel;
    FSearchLabel: TLabel;
    FSearchEdit: TEdit;
    FActionListView: TListView;
    FDefaultWidth: Integer;
    FDefaultHeight: Integer;
    procedure AddSearchFunctionality(Form: TForm);
    procedure SearchEditChange(Sender: TObject);
    procedure SearchEditEnter(Sender: TObject);
    procedure SearchEditExit(Sender: TObject);
    procedure ApplicationEventsIdle(Sender: TObject; var Done: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure SaveFormSizeToRegistry(Form: TForm);
    procedure LoadFormSizeFromRegistry(Form: TForm);
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

resourcestring
  SSearchPlaceholder = 'Search...';

procedure Register;
begin
  RegisterPackageWizard(TActionListSearchWizard.Create as IOTAWizard);
end;

constructor TActionListSearchWizard.Create;
begin
  inherited Create;
  FApplicationEvents := TApplicationEvents.Create(nil);
  FApplicationEvents.OnIdle := ApplicationEventsIdle;
end;

destructor TActionListSearchWizard.Destroy;
begin
  FApplicationEvents.Free;
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
begin
  for I := 0 to Screen.FormCount - 1 do
  begin
    if Screen.Forms[I].ClassName = 'TActionListDesigner' then
      AddSearchFunctionality(Screen.Forms[I]);
  end;
end;

procedure TActionListSearchWizard.AddSearchFunctionality(Form: TForm);
const
  CONTROLS_OFFSET = 8;
var
  lvToolBar1: TToolBar;
  I: Integer;
begin
  if Form.FindComponent('ActionListSearchPanel') <> nil then
    Exit;
  
  FActionListView := Form.FindComponent('ListView1') as TListView;
  if not Assigned(FActionListView) then
  begin
    ShowMessage('ListView1 not found on form: ' + Form.Name);
    Exit;
  end;
  
  lvToolBar1 := Form.FindComponent('ToolBar1') as TToolBar;
  if not Assigned(lvToolBar1) then
  begin
    ShowMessage('ToolBar1 not found on form: ' + Form.Name);
    Exit;
  end;

  FSearchPanel := TPanel.Create(Form);
  FSearchPanel.Name := 'ActionListSearchPanel';
  FSearchPanel.Parent := Form;
  FSearchPanel.Height := 30;
  FSearchPanel.Caption := '';
  FSearchPanel.Top := lvToolBar1.Top + lvToolBar1.Height;
  FSearchPanel.Align := alTop;

  for I := 0 to Form.ControlCount - 1 do
  begin
    if (Form.Controls[I] <> FSearchPanel) and (Form.Controls[I].Top >= FSearchPanel.Top) then
      Form.Controls[I].Top := Form.Controls[I].Top + FSearchPanel.Height;
  end;

  FSearchLabel := TLabel.Create(FSearchPanel);
  FSearchLabel.Parent := FSearchPanel;
  FSearchLabel.Caption := 'Search:';
  FSearchLabel.Left := CONTROLS_OFFSET;
  FSearchLabel.Top := CONTROLS_OFFSET;

  FSearchEdit := TEdit.Create(FSearchPanel);
  FSearchEdit.Parent := FSearchPanel;
  FSearchEdit.Left := FSearchLabel.Left + FSearchLabel.Width + CONTROLS_OFFSET;
  FSearchEdit.Top := 4;
  FSearchEdit.Width := FSearchPanel.Width - (FSearchLabel.Left + FSearchLabel.Width + 2 * CONTROLS_OFFSET);
  FSearchEdit.Anchors := [akTop, akLeft, akRight];
  FSearchEdit.Name := 'ActionListSearchEdit';
  FSearchEdit.Text := SSearchPlaceholder;
  FSearchEdit.Font.Color := clGray;
  FSearchEdit.OnEnter := SearchEditEnter;
  FSearchEdit.OnExit := SearchEditExit;
  FSearchEdit.OnChange := SearchEditChange;

  Form.OnClose := FormClose;

  // First store default sizes
  FDefaultWidth := Form.Width;
  FDefaultHeight := Form.Height;
  // Then load the Size from Registry
  LoadFormSizeFromRegistry(Form);
end;

procedure TActionListSearchWizard.SearchEditChange(Sender: TObject);
var
  I: Integer;
  lvSearchText: string;
  lvListItem: TListItem;
  lvFirstMatch: TListItem;
begin
  if not Assigned(FActionListView) then
  begin
    ShowMessage('ActionListView not found');
    Exit;
  end;

  lvSearchText := TEdit(Sender).Text;
  if (Length(lvSearchText) < 2) or (lvSearchText = SSearchPlaceholder) then
    Exit; // Only search with at least 2 characters

  FActionListView.Items.BeginUpdate;
  try
    lvFirstMatch := nil;
    for I := 0 to FActionListView.Items.Count - 1 do
    begin
      lvListItem := FActionListView.Items[I];
      if Pos(LowerCase(lvSearchText), LowerCase(lvListItem.Caption)) > 0 then
      begin
        lvListItem.Selected := True;
        if (lvFirstMatch = nil) then
          lvFirstMatch := lvListItem;
      end
      else
        lvListItem.Selected := False;
    end;

    if Assigned(lvFirstMatch) then
    begin
      FActionListView.Selected := lvFirstMatch;
      lvFirstMatch.MakeVisible(False);
    end;
  finally
    FActionListView.Items.EndUpdate;
  end;  
  // Keep the focus on the edit control
  if TEdit(Sender).CanFocus then
    TEdit(Sender).SetFocus;
end;

procedure TActionListSearchWizard.SearchEditEnter(Sender: TObject);
begin
  if (TEdit(Sender).Text = SSearchPlaceholder) then
  begin
    TEdit(Sender).Text := '';
    TEdit(Sender).Font.Color := clWindowText;
  end;
end;

procedure TActionListSearchWizard.SearchEditExit(Sender: TObject);
begin
  if (TEdit(Sender).Text = '') then
  begin
    TEdit(Sender).Text := SSearchPlaceholder;
    TEdit(Sender).Font.Color := clGray;
  end;
end;

procedure TActionListSearchWizard.SaveFormSizeToRegistry(Form: TForm);
var
  lvRegistry: TRegistry;
  lvScreenRect: TRect;
begin
  lvScreenRect := Screen.MonitorFromWindow(Form.Handle).WorkareaRect;

  // Ensure the form is within screen bounds
  // TODO: refine it
  if (Form.Left < lvScreenRect.Left) or (Form.Top < lvScreenRect.Top) or
     (Form.Left + Form.Width > lvScreenRect.Right) or (Form.Top + Form.Height > lvScreenRect.Bottom) then
    Exit;

  lvRegistry := TRegistry.Create;
  try
    lvRegistry.RootKey := HKEY_CURRENT_USER;
    if lvRegistry.OpenKey(REG_PATH, True) then
    begin
      if (Form.Width > FDefaultWidth) and (Form.Height > FDefaultHeight) then
      begin
        lvRegistry.WriteInteger(REG_FORM_WIDTH, Form.Width);
        lvRegistry.WriteInteger(REG_FORM_HEIGHT, Form.Height);
      end;
      lvRegistry.CloseKey;
    end;
  finally
    lvRegistry.Free;
  end;
end;

procedure TActionListSearchWizard.LoadFormSizeFromRegistry(Form: TForm);
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
          Form.Width := lvWidth;
      end;

      if lvRegistry.ValueExists(REG_FORM_HEIGHT) then
      begin
        lvHeight := lvRegistry.ReadInteger(REG_FORM_HEIGHT);
        if lvHeight >= FDefaultHeight then
          Form.Height := lvHeight;
      end;
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

