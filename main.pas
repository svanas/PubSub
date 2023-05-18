unit main;

interface

uses
  // Delphi
  System.Classes,
  System.Notification,
  // FireMonkey
  FMX.Controls,
  FMX.Controls.Presentation,
  FMX.Forms,
  FMX.ListBox,
  FMX.StdCtrls,
  FMX.Types,
  // web3
  web3,
  web3.sync,
  // Project
  common;

type
  TWebSocket = class(TCriticalThing)
  strict private
    FClient: IWeb3Ex;
    FProvider: TProvider;
    FSubscription: string;
  public
    function Subscribed: Boolean;
    constructor Create(provider: TProvider); reintroduce;
    property Client: IWeb3Ex read FClient;
    property Provider: TProvider read FProvider;
    property Subscription: string read FSubscription write FSubscription;
  end;

  TFrmMain = class(TForm)
    Panel1: TPanel;
    btnStart: TButton;
    btnStop: TButton;
    cboProvider: TComboBox;
    Panel2: TPanel;
    lblCurrBlock: TLabel;
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FClosing: Boolean;
    FNotificationCenter: TNotificationCenter;
    FRunning: Boolean;
    FWebSocket: TWebSocket;
    function  GetProvider: TProvider;
    function  GetWebSocket: TWebSocket;
    procedure HandleError(const msg: string); overload;
    procedure HandleError(const err: IError); overload;
    procedure SetRunning(Value: Boolean);
    class procedure Synchronize(P: TThreadProcedure);
    procedure UpdateUI;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    property Closing: Boolean read FClosing;
    property Provider: TProvider read GetProvider;
    property NotificationCenter: TNotificationCenter read FNotificationCenter;
    property Running: Boolean read FRunning write SetRunning;
    property WebSocket: TWebSocket read GetWebSocket;
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.fmx}

uses
  // Delphi
  System.JSON,
  System.SysUtils,
  System.TypInfo,
  // web3
  web3.eth.pubsub,
  web3.eth.tx;

resourcestring
  CURR_BLOCK = 'CURRENT BLOCK : %s';

{ TWebSocket }

constructor TWebSocket.Create(provider: TProvider);
begin
  inherited Create;
  Self.FClient := common.GetClient(Ethereum, provider);
  Self.FProvider := provider;
end;

function TWebSocket.Subscribed: Boolean;
begin
  Result := Self.FSubscription <> '';
end;

{ TFrmMain }

constructor TFrmMain.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  FNotificationCenter := TNotificationCenter.Create(Self);
  for var G := System.Low(TProvider) to System.High(TProvider) do
    cboProvider.Items.AddObject(GetEnumName(TypeInfo(TProvider), Ord(G)), TObject(G));
  cboProvider.ItemIndex := 0;
  UpdateUI;
end;

destructor TFrmMain.Destroy;
begin
  if Assigned(FNotificationCenter) then FNotificationCenter.Free;
  if Assigned(FWebSocket) then FWebSocket.Free;
  inherited Destroy;
end;

function TFrmMain.GetProvider: TProvider;
begin
  Result := TProvider(cboProvider.Items.Objects[cboProvider.ItemIndex]);
end;

function TFrmMain.GetWebSocket: TWebSocket;
begin
  if not Assigned(FWebSocket) then
    FWebSocket := TWebSocket.Create(Self.Provider);
  if FWebSocket.Provider <> Self.Provider then
  begin
    FWebSocket.Free;
    FWebSocket := TWebSocket.Create(Self.Provider);
  end;
  Result := FWebSocket;
end;

procedure TFrmMain.HandleError(const msg: string);
begin
  if msg = '' then
    EXIT;
  Self.Synchronize(procedure
  begin
    var N := NotificationCenter.CreateNotification;
    N.AlertBody := Format('[%s] %s', [TimeToStr(System.SysUtils.Now), msg]);
    NotificationCenter.PresentNotification(N);
  end);
end;

procedure TFrmMain.HandleError(const err: IError);
begin
  Self.HandleError(err.Message);
end;

class procedure TFrmMain.Synchronize(P: TThreadProcedure);
begin
  if TThread.CurrentThread.ThreadID = MainThreadId then
    P
  else
    TThread.Synchronize(nil, procedure
    begin
      P
    end);
end;

procedure TFrmMain.UpdateUI;
begin
  cboProvider.Enabled := not Running;
  btnStart.Enabled := not Running;
  btnStop.Enabled := Running;

  if Running then
    Self.Caption := 'Running'
  else
    Self.Caption := 'Off duty';

  if not Running then
  begin
    lblCurrBlock.Text := Format(CURR_BLOCK, ['0']);
    if Closing then Self.Close;
  end;
end;

procedure TFrmMain.btnStartClick(Sender: TObject);
begin
  Running := True;
end;

procedure TFrmMain.btnStopClick(Sender: TObject);
begin
  Running := False;
end;

procedure TFrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not Running;
  if not CanClose then
  begin
    FClosing := True;
    Running := False;
  end;
end;

procedure TFrmMain.SetRunning(Value: Boolean);
var
  Subscribe  : TProc;
  Unsubscribe: TProc;
begin
  if Value = FRunning then
    EXIT;

  FRunning := Value;

  Subscribe := procedure
  begin
    web3.eth.pubsub.subscribe(
      WebSocket.Client,
      newHeads,
      // one-time callback
      procedure(subscription: string; err: IError)
      begin
        if Assigned(err) then
        begin
          Self.HandleError(err);
          EXIT;
        end;
        Self.WebSocket.Enter;
        try
          Self.WebSocket.Subscription := subscription;
        finally
          Self.WebSocket.Leave;
        end;
      end,
      // continuous notifications
      procedure(notification: TJsonObject; err: IError)
      begin
        if Assigned(err) then
        begin
          Self.HandleError(err);
          EXIT;
        end;
        Self.Synchronize(procedure
        begin
          lblCurrBlock.Text := Format(CURR_BLOCK, [web3.eth.pubsub.blockNumber(notification).ToString]);
          Beep;
        end)
      end,
      // non-JSON-RPC-error handler (probably a socket error)
      procedure(err: IError)
      begin
        Self.HandleError(err);
      end,
      // connection closed
      procedure
      begin
        Self.WebSocket.Enter;
        try
          Self.WebSocket.Subscription := '';
        finally
          Self.WebSocket.Leave;
        end;
        if Running then
          Subscribe
        else
          Self.Synchronize(procedure
          begin
            UpdateUI;
          end);
      end
    );
  end;

  Unsubscribe := procedure
  begin
    if WebSocket.Subscribed then
      web3.eth.pubsub.unsubscribe(WebSocket.Client, WebSocket.Subscription, procedure(unsubscribed: Boolean; err: IError)
      begin
        if Assigned(err) then
        begin
          Self.HandleError(err);
          EXIT;
        end;
        if unsubscribed then
          WebSocket.Client.Disconnect;
      end);
  end;

  if FRunning then
    Subscribe
  else
    Unsubscribe;

  UpdateUI;
end;

end.
