program DemoBpHttpDownload;

// Manual demo for dist\BpHttpClientStandalone.pas - NEEDS NETWORK ACCESS,
// so it is not part of tools\VerifyBundles.cmd. Compile it against dist\:
//   dcc32 -U..\..\dist DemoBpHttpDownload.dpr
// It shows the three headline features of the download stack:
//   1. a synchronous HTTPS GET (TLS via Schannel, no OpenSSL DLLs)
//   2. a streaming download to a stream with a textual progress bar
//   3. an async (worker thread) download cancelled mid-flight

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, Windows, BpHttpClientStandalone;

type
  // console callbacks; events are method pointers, so a carrier class
  TDemo = class
  public
    procedure ShowProgress(ASender: TObject; const AReceived, ATotal: Int64;
      var ACancel: Boolean);
  end;

procedure TDemo.ShowProgress(ASender: TObject; const AReceived, ATotal: Int64;
  var ACancel: Boolean);
const
  lcBarWidth = 30;
var
  lvPercent, lvFilled, i: Integer;
  lvBar: string;
begin
  lvPercent := BpHttpProgressPercent(AReceived, ATotal);
  if lvPercent < 0 then
  begin
    Write(#13'  ', AReceived, ' bytes (total unknown)');
    Exit;
  end;
  lvFilled := (lvPercent * lcBarWidth) div 100;
  lvBar := '';
  for i := 1 to lcBarWidth do
    if i <= lvFilled then
      lvBar := lvBar + '#'
    else
      lvBar := lvBar + '.';
  Write(Format(#13'  [%s] %3d%%  %d/%d bytes', [lvBar, lvPercent, AReceived, ATotal]));
end;

procedure DemoSyncGet;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  Writeln('1) Synchronous HTTPS GET https://example.com/');
  lvClient := TbpHttpClient.Create;
  try
    lvResponse := lvClient.Get('https://example.com/');
    Writeln(Format('  %s, %d body bytes, Content-Length %d',
      [lvResponse.StatusText, Length(lvResponse.Body), lvResponse.ContentLength]));
  finally
    lvClient.Free;
  end;
  Writeln;
end;

procedure DemoStreamingDownload(ADemo: TDemo);
var
  lvClient: TbpHttpClient;
  lvStream: TMemoryStream;
  lvResponse: TbpHttpResponse;
begin
  Writeln('2) Streaming download, 2 MB with progress');
  lvClient := TbpHttpClient.Create;
  lvStream := TMemoryStream.Create;
  try
    lvResponse := lvClient.Download(
      'https://speed.cloudflare.com/__down?bytes=2097152', lvStream,
      ADemo.ShowProgress);
    Writeln;
    Writeln(Format('  done: %s, %d bytes in the stream',
      [lvResponse.StatusText, lvStream.Size]));
  finally
    lvStream.Free;
    lvClient.Free;
  end;
  Writeln;
end;

procedure DemoAsyncCancel;
var
  lvTask: TbpHttpDownloadTask;
  lvFileName: string;
  lvDeadline: Cardinal;
begin
  Writeln('3) Async download on a worker thread, cancelled mid-flight');
  lvFileName := ExtractFilePath(ParamStr(0)) + 'demo_cancel.bin';
  // hot task in one call; False = console app without a message loop, so no
  // event marshaling, this thread just polls the thread-safe properties
  lvTask := BpDownloadAsync('https://speed.cloudflare.com/__down?bytes=67108864',
    lvFileName, nil, nil, False);
  try
    Writeln('  started, main thread stays free...');

    // let it move some bytes, then abort
    lvDeadline := GetTickCount + 15000;
    while (lvTask.Received < 1048576) and not lvTask.IsFinished and
      (GetTickCount < lvDeadline) do
      Sleep(20);
    Writeln(Format('  %d of %d bytes received, cancelling now',
      [lvTask.Received, lvTask.Total]));
    lvTask.Cancel;
    lvTask.WaitFor(10000);

    case lvTask.State of
      dtsCancelled:
        Writeln('  state: cancelled (as requested)');
      dtsSucceeded:
        Writeln('  state: succeeded (too fast to cancel)');
    else
      Writeln('  state: failed: ' + lvTask.ErrorMessage);
    end;
    if FileExists(lvFileName) then
      Writeln('  partial file still exists (unexpected)')
    else
      Writeln('  partial file was cleaned up');
  finally
    lvTask.Free;
  end;
end;

var
  gvDemo: TDemo;

begin
  ExitCode := 1;
  gvDemo := TDemo.Create;
  try
    try
      DemoSyncGet;
      DemoStreamingDownload(gvDemo);
      DemoAsyncCancel;
      ExitCode := 0;
    except
      on E: Exception do
        Writeln('DEMO FAILED: ' + E.Message);
    end;
  finally
    gvDemo.Free;
  end;
end.
