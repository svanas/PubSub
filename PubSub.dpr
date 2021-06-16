program PubSub;

uses
  System.StartUpCopy,
  FMX.Forms,
  main in 'main.pas' {FrmMain},
  common in 'common.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFrmMain, FrmMain);
  Application.Run;
end.
