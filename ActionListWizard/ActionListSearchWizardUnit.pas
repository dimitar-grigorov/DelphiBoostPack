unit ActionListSearchWizardUnit;

interface

uses
  ToolsAPI, Classes, ActnList, Forms, StdCtrls, Controls, ExtCtrls, SysUtils, DockForm, Windows, AppEvnts, ComCtrls, Graphics, Registry;

type
  TActionListSearchWizard = class(TNotifierObject, IOTAWizard, IOTANotifier)
  private
    FApplicationEvents: TApplicationEvents;
    FSearchPanel: TPanel;
    FSearchLabel: TLabel;
    FSearchEdit: TEdit;
    ActionListView: TListView;
    FDefaultWidth: Integer;
    FDefaultHeight: Integer;
    procedure AddSearchField(Form: TForm);
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

procedure Register;
begin
  RegisterPackageWizard(TActionListSearchWizard.Create as IOTAWizard);
end;

{ TActionListSearchWizard }

constructor TActionListSearchWizard.Create;
begin
  inherited Create;
  FApplicationEvents := TApplicationEvents.Create(nil);
  FApplicationEvents.OnIdle := ApplicationEventsIdle;
  {$IFDEF DEBUG}
  ShowMessage('TActionListSearchWizard created and application events hooked');
  {$ENDIF}
end;

destructor TActionListSearchWizard.Destroy;
begin
  FApplicationEvents.Free;
  inherited Destroy;
end;

procedure TActionListSearchWizard.AddSearchField(Form: TForm);
const
  OFFSET = 8;
var
  ToolBar1: TToolBar;
  I: Integer;
begin
  {$IFDEF DEBUG}
  ShowMessage('AddSearchField called for form: ' + Form.Name);
  {$ENDIF}

  // Check if the search panel is already added
  if Form.FindComponent('ActionListSearchPanel') <> nil then
    Exit;

  // Find the ListView1 component on the form
  ActionListView := Form.FindComponent('ListView1') as TListView;
  if not Assigned(ActionListView) then
  begin
    ShowMessage('ListView1 not found on form: ' + Form.Name);
    Exit;
  end;

  // Find the ToolBar1 component on the form
  ToolBar1 := Form.FindComponent('ToolBar1') as TToolBar;
  if not Assigned(ToolBar1) then
  begin
    ShowMessage('ToolBar1 not found on form: ' + Form.Name);
    Exit;
  end;

  // Create a panel to hold the search controls
  FSearchPanel := TPanel.Create(Form);
  FSearchPanel.Name := 'ActionListSearchPanel';
  FSearchPanel.Parent := Form;
  FSearchPanel.Height := 30;
  FSearchPanel.Caption := '';

  // Insert the panel below ToolBar1
  FSearchPanel.Top := ToolBar1.Top + ToolBar1.Height;
  FSearchPanel.Align := alTop;

  // Adjust the Top property of the components below FSearchPanel
  for i := 0 to Form.ControlCount - 1 do
  begin
    if (Form.Controls[i] <> FSearchPanel) and (Form.Controls[i].Top >= FSearchPanel.Top) then
      Form.Controls[i].Top := Form.Controls[i].Top + FSearchPanel.Height;
  end;

  // Create the search label
  FSearchLabel := TLabel.Create(FSearchPanel);
  FSearchLabel.Parent := FSearchPanel;
  FSearchLabel.Caption := 'Search:';
  FSearchLabel.Left := OFFSET;
  FSearchLabel.Top := 8;

  // Create the search edit field
  FSearchEdit := TEdit.Create(FSearchPanel);
  FSearchEdit.Parent := FSearchPanel;
  FSearchEdit.Left := FSearchLabel.Left + FSearchLabel.Width + OFFSET;
  FSearchEdit.Top := 4;
  FSearchEdit.Width := FSearchPanel.Width - (FSearchLabel.Left + FSearchLabel.Width + 2 * OFFSET);
  FSearchEdit.Anchors := [akTop, akLeft, akRight];
  FSearchEdit.Name := 'ActionListSearchEdit'; // Assign a name for easy reference

  // Set placeholder text
  FSearchEdit.Text := 'Search...';
  FSearchEdit.Font.Color := clGray;

  // Assign event handlers
  FSearchEdit.OnEnter := SearchEditEnter;
  FSearchEdit.OnExit := SearchEditExit;
  FSearchEdit.OnChange := SearchEditChange;

  // Load the last saved size from the registry
  LoadFormSizeFromRegistry(Form);

  // Assign the close event to save the form size
  Form.OnClose := FormClose;

  // Store default sizes
  FDefaultWidth := Form.Width;
  FDefaultHeight := Form.Height;

  {$IFDEF DEBUG}
  ShowMessage('Search field added to form: ' + Form.Name);
  {$ENDIF}
end;

procedure TActionListSearchWizard.SearchEditChange(Sender: TObject);
var
  i: Integer;
  SearchText: string;
  ListItem: TListItem;
begin
  if not Assigned(ActionListView) then
  begin
    ShowMessage('ActionListView not found');
    Exit;
  end;

  SearchText := TEdit(Sender).Text;
  if (Length(SearchText) < 2) or (SearchText = 'Search...') then
    Exit; // Only search with at least 2 characters and if it's not the placeholder text

  ActionListView.Items.BeginUpdate;
  try
    for i := 0 to ActionListView.Items.Count - 1 do
    begin
      ListItem := ActionListView.Items[i];
      if Pos(LowerCase(SearchText), LowerCase(ListItem.Caption)) > 0 then
      begin
        ListItem.Selected := True;
        ListItem.MakeVisible(False);
      end
      else
      begin
        ListItem.Selected := False;
      end;
    end;
  finally
    ActionListView.Items.EndUpdate;
  end;
end;

procedure TActionListSearchWizard.SearchEditEnter(Sender: TObject);
begin
  if TEdit(Sender).Text = 'Search...' then
  begin
    TEdit(Sender).Text := '';
    TEdit(Sender).Font.Color := clWindowText;
  end;
end;

procedure TActionListSearchWizard.SearchEditExit(Sender: TObject);
begin
  if TEdit(Sender).Text = '' then
  begin
    TEdit(Sender).Text := 'Search...';
    TEdit(Sender).Font.Color := clGray;
  end;
end;

procedure TActionListSearchWizard.ApplicationEventsIdle(Sender: TObject; var Done: Boolean);
var
  i: Integer;
  Form: TForm;
begin
  for i := 0 to Screen.FormCount - 1 do
  begin
    Form := Screen.Forms[i];
    if Form.ClassName = 'TActionListDesigner' then
    begin
      AddSearchField(Form);
    end;
  end;
end;

procedure TActionListSearchWizard.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveFormSizeToRegistry(TForm(Sender));
end;

procedure TActionListSearchWizard.SaveFormSizeToRegistry(Form: TForm);
var
  Reg: TRegistry;
  ScreenRect: TRect;
begin
  ScreenRect := Screen.MonitorFromWindow(Form.Handle).WorkareaRect;

  // Ensure the form is within screen bounds
  if (Form.Left < ScreenRect.Left) or (Form.Top < ScreenRect.Top) or
     (Form.Left + Form.Width > ScreenRect.Right) or (Form.Top + Form.Height > ScreenRect.Bottom) then
    Exit;

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\MyCompany\ActionListSearchWizard', True) then
    begin
      if (Form.Width > FDefaultWidth) and (Form.Height > FDefaultHeight) then
      begin
        Reg.WriteInteger('Width', Form.Width);
        Reg.WriteInteger('Height', Form.Height);
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure TActionListSearchWizard.LoadFormSizeFromRegistry(Form: TForm);
var
  Reg: TRegistry;
  Width, Height: Integer;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\MyCompany\ActionListSearchWizard', False) then
    begin
      if Reg.ValueExists('Width') then
      begin
        Width := Reg.ReadInteger('Width');
        if Width >= FDefaultWidth then
          Form.Width := Width;
      end;

      if Reg.ValueExists('Height') then
      begin
        Height := Reg.ReadInteger('Height');
        if Height >= FDefaultHeight then
          Form.Height := Height;
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure TActionListSearchWizard.Execute;
begin
  {$IFDEF DEBUG}
  ShowMessage('Execute called');
  {$ENDIF}
  // Application events are already hooked in the constructor
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

