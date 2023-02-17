unit common;

interface

uses
  // web3
  web3;

type
  TGateway = (Alchemy, Infura);

function GetClient(chain: TChain; gateway: TGateway): TWeb3Ex;

implementation

uses
  // Delphi
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  WinAPI.ShellAPI,
  WinAPI.Windows,
  // web3
  web3.eth.alchemy,
  web3.eth.infura,
  web3.json.rpc.sgc.websockets;

function GetApiKey(gateway: TGateway): string;

  function API_KEY_FILE: string;
  const
    API_KEY_NAME: array[TGateway] of string = (
      'MY_ALCHEMY_API_KEY', // Alchemy
      'MY_INFURA_API_KEY'   // Infura
  );
  begin
    Result := TPath.GetHomePath + TPath.DirectorySeparatorChar + API_KEY_NAME[gateway] + '.TXT';
  end;

var
  SEI: TShellExecuteInfo;
begin
  Result := '';

  if TFile.Exists(API_KEY_FILE) then
    Result := Trim(TFile.ReadAllText(API_KEY_FILE))
  else
    TFile.Create(API_KEY_FILE).Free;

  if Result <> '' then
    EXIT;

  FillChar(SEI, SizeOf(SEI), 0);
  with SEI do
  begin
    cbSize := SizeOf(SEI);
    fMask := SEE_MASK_NOCLOSEPROCESS;
    lpFile := PChar(API_KEY_FILE);
    nShow := SW_SHOW;
  end;

  if not ShellExecuteEx(@SEI) then
    EXIT;

  try
    WaitForSingleObject(SEI.hProcess, INFINITE);
  finally
    CloseHandle(SEI.hProcess);
  end;

  Result := GetApiKey(gateway);
end;

function GetEndpoint(chain: TChain; gateway: TGateway; protocol: TTransport): string;
begin
  case gateway of
    Alchemy:
      Result := web3.eth.alchemy.endpoint(chain, protocol, GetApiKey(Alchemy)).Value;
    Infura:
      Result := web3.eth.infura.endpoint(chain, protocol, GetApiKey(Infura)).Value;
  end;
end;

function GetClient(chain: TChain; gateway: TGateway): TWeb3Ex;
const
  SECURITY: array[TGateway] of TSecurity = (
    Automatic, // Alchemy
    TLS_12     // Infura
  );
begin
  Result := TWeb3Ex.Create(
    chain.SetRPC(WebSocket, GetEndpoint(chain, gateway, WebSocket)),
    TJsonRpcSgcWebSocket.Create,
    SECURITY[gateway]
  );
end;

end.
