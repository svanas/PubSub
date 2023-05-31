unit common;

interface

uses
  // web3
  web3;

type
  TProvider = (Alchemy, Infura);

function GetClient(chain: TChain; provider: TProvider): TWeb3Ex;

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

function GetApiKey(provider: TProvider): string;

  function API_KEY_FILE: string;
  const
    API_KEY_NAME: array[TProvider] of string = (
      'MY_ALCHEMY_API_KEY', // Alchemy
      'MY_INFURA_API_KEY'   // Infura
  );
  begin
    Result := TPath.GetHomePath + TPath.DirectorySeparatorChar + API_KEY_NAME[provider] + '.TXT';
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

  Result := GetApiKey(provider);
end;

function GetEndpoint(chain: TChain; provider: TProvider; protocol: TTransport): string;
begin
  case provider of
    Alchemy:
      Result := web3.eth.alchemy.endpoint(chain, protocol, GetApiKey(Alchemy), core).Value;
    Infura:
      Result := web3.eth.infura.endpoint(chain, protocol, GetApiKey(Infura)).Value;
  end;
end;

function GetClient(chain: TChain; provider: TProvider): TWeb3Ex;
const
  SECURITY: array[TProvider] of TSecurity = (
    Automatic, // Alchemy
    TLS_12     // Infura
  );
begin
  Result := TWeb3Ex.Create(
    chain.SetRPC(WebSocket, GetEndpoint(chain, provider, WebSocket)),
    TJsonRpcSgcWebSocket.Create,
    TProxy.Disabled,
    SECURITY[provider]
  );
end;

end.
