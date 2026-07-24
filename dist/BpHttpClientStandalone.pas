unit BpHttpClientStandalone;

// BpHttpClientStandalone.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Units\BpBase64.pas
//   src\Core\Classes\BpCancellationToken.pas
//   src\Core\Classes\BpHttpClient.pas
//   src\Core\Classes\BpHttpDownloadTask.pas
// Source commit 44a1d3d, generated 2026-07-24 by tools\Amalgamate.ps1.
// Fix bugs in the modular units, then regenerate with:
//   powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
// Notes:
// - use at most one bundle per project; two bundles embedding the same
//   helper unit would declare duplicate identifiers
// - unit-wide compiler directives of embedded units (e.g. {$Q-} in the
//   hash units) apply from their position to the end of this file

interface

uses
  SysUtils, Windows, Classes, WinInet, Messages;

// ==================================================================
// BpBase64.pas - interface
// ==================================================================

// Base64 encode/decode per RFC 4648, standard and url-safe alphabets.
// Encoding computes the exact output size and builds the result with a single
// allocation. Standard encode pads with '='; Base64url encode omits padding
// (the common form in tokens, e.g. JWT).
// Decoding uses one shared reverse lookup table that accepts both alphabets,
// tolerates missing padding and skips whitespace (so MIME output with CRLF
// line breaks decodes fine). Any other character raises EbpBase64.

type
  EbpBase64 = class(Exception);

function Base64Encode(const AData; ASize: Integer): string; overload;
function Base64Encode(const ABytes: TBytes): string; overload;
function Base64Encode(const AText: AnsiString): string; overload;
function Base64UrlEncode(const AData; ASize: Integer): string; overload;
function Base64UrlEncode(const ABytes: TBytes): string; overload;
function Base64UrlEncode(const AText: AnsiString): string; overload;
function Base64Decode(const ABase64: string): TBytes;
function Base64DecodeStr(const ABase64: string): AnsiString;

// ==================================================================
// BpCancellationToken.pas - interface
// ==================================================================

// Cooperative cancellation for Delphi 7/2007 and later, modeled on the
// C# CancellationToken / JS AbortController pair.
//
// One party holds the token and calls Cancel; the working party polls
// IsCancellationRequested at convenient points and unwinds when it turns
// True. Both sides may live on different threads: Cancel and the query are
// thread-safe, and a token is one-shot by design (no Reset), so a stale
// True can never flip back to False under the worker's feet.
//
// RegisterCleanup is the analogue of C#'s CancellationToken.Register: it
// arranges a callback to run inside Cancel, which is how a blocking
// operation gets aborted promptly instead of at the next poll. The HTTP
// client registers a callback that closes its WinInet request handle, so a
// thread stuck in HttpSendRequest or InternetReadFile fails over
// immediately with ERROR_INTERNET_OPERATION_CANCELLED. Cleanups fire
// inside the canceller's thread while the token lock is held; keep them
// short and never call back into the token from one.
//
// The token must outlive every operation it was handed to; the usual
// owner is whoever calls Cancel (a UI form, a download task).

type
  // plain procedure on purpose: usable from any code without an object
  TbpCancelCleanupProc = procedure(AData: Pointer);

  TbpCancellationToken = class
  private
    FLock: TRTLCriticalSection;
    FCancelled: Integer;          // 0/1, written under the lock
    FCleanupProcs: array of TbpCancelCleanupProc;
    FCleanupData: array of Pointer;
    FCleanupIds: array of Integer;
    FNextId: Integer;
    function IndexOfId(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    // one-shot; safe to call repeatedly and from any thread
    procedure Cancel;
    function IsCancellationRequested: Boolean;

    // registers a cleanup that Cancel will invoke; returns False without
    // registering when the token is already cancelled (mirrors C#, where a
    // late Register runs the callback immediately - the caller reacts by
    // aborting instead)
    function RegisterCleanup(AProc: TbpCancelCleanupProc; AData: Pointer;
      out AId: Integer): Boolean;
    // removes a registration; True when it was still pending, False when
    // Cancel already ran it (the resource is gone, do not touch it again)
    function UnregisterCleanup(AId: Integer): Boolean;
  end;

// ==================================================================
// BpHttpClient.pas - interface
// ==================================================================

// HTTP/HTTPS client over WinInet for Delphi 7/2007 and later.
// TLS comes from Schannel, so no OpenSSL DLLs are needed.
//
// TbpHttpClient wraps the session/connection/request handle dance behind
// Get/Post/Put/Delete returning a TbpHttpResponse record. Persistent custom
// headers (AddHeader), a BearerToken property and a SetBasicAuth helper cover
// the common API auth schemes; PostJson sets the Content-Type for the typical
// JSON endpoint call. Username/Password go through the WinInet option instead
// of a header, so they also answer proxy and 401 challenges.
// Failures raise EbpHttpClient carrying the WinInet error code, and
// BpClassifyHttpError turns either error dimension into a user-facing string.
//
// Download/DownloadToFile stream a body of any size to a TStream or file in
// constant memory, reporting Int64 progress and honouring cooperative
// cancellation through TbpCancellationToken (see BpCancellationToken.pas).
// A cancel closes the WinInet request handle, so even a thread blocked in
// connect or read aborts promptly; the failure surfaces as the typed
// EbpHttpClientCancelled. For the non-blocking wrapper that runs a download
// on a worker thread see BpHttpDownloadTask.pas.

type
  TbpHttpMethod = (hmGet, hmPost, hmPut, hmDelete);

  EbpHttpClient = class(Exception)
  private
    FStatusCode: Integer;
    FWinInetError: DWORD;
  public
    constructor Create(const AMessage: string; AStatusCode: Integer = 0;
      AWinInetError: DWORD = 0);
    property StatusCode: Integer read FStatusCode;
    property WinInetError: DWORD read FWinInetError;
  end;

  // raised when a download is aborted through a token or a progress callback;
  // WinInetError is gcErrOperationCancelled
  EbpHttpClientCancelled = class(EbpHttpClient);

  TbpHttpResponse = record
    StatusCode: Integer;
    StatusText: string;
    Headers: string;         // raw response headers, CRLF separated
    Body: AnsiString;        // raw bytes as received; empty for Download
    ContentLength: Int64;    // from the Content-Length header, -1 when absent
  end;

  // progress callback for downloads, fired synchronously on the thread that
  // runs the download: once after the headers arrive (AReceived = 0) and then
  // after every chunk. ATotal is -1 when the server sent no Content-Length
  // (chunked transfer). Set ACancel to True to abort; the download raises
  // EbpHttpClientCancelled and, for DownloadToFile, deletes the partial file.
  TbpHttpProgressEvent = procedure(ASender: TObject; const AReceived,
    ATotal: Int64; var ACancel: Boolean) of object;

  TbpHttpClient = class
  private
    FUserAgent: string;
    FConnectTimeout: DWORD;
    FSendTimeout: DWORD;
    FReceiveTimeout: DWORD;
    FFollowRedirects: Boolean;
    FUsername: AnsiString;
    FPassword: AnsiString;
    FBearerToken: string;
    FHeaders: TStringList;  // persistent headers as Name=Value pairs
    function GetWinInetErrorMessage(AErrorCode: DWORD): string;
    function CreateSession: HINTERNET;
    function CreateConnection(ASession: HINTERNET; const AServerName: string;
      APort: Integer): HINTERNET;
    function CreateRequest(AConnection: HINTERNET; const AMethod, AResource: string;
      ASecure: Boolean): HINTERNET;
    procedure ApplyTimeouts(AHandle: HINTERNET);
    procedure ApplyAuthentication(ARequest: HINTERNET);
    procedure SendHttpRequest(ARequest: HINTERNET; const AHeaders: string;
      const ABody: AnsiString);
    function ReadResponseStatus(ARequest: HINTERNET): Integer;
    function ReadResponseHeaders(ARequest: HINTERNET): string;
    function ReadResponseBody(ARequest: HINTERNET): AnsiString;
    procedure ReadBodyToStream(ARequest: HINTERNET; ADest: TStream;
      const ATotal: Int64; AProgress: TbpHttpProgressEvent;
      AToken: TbpCancellationToken);
  public
    constructor Create;
    destructor Destroy; override;

    function Execute(const AUrl: string; AMethod: TbpHttpMethod = hmGet;
      const AHeaders: string = ''; const ABody: AnsiString = ''): TbpHttpResponse;
    function Get(const AUrl: string; const AHeaders: string = ''): TbpHttpResponse;
    function Post(const AUrl: string; const ABody: AnsiString;
      const AHeaders: string = ''): TbpHttpResponse;
    function PostJson(const AUrl: string; const AJson: AnsiString): TbpHttpResponse;
    function Put(const AUrl: string; const ABody: AnsiString;
      const AHeaders: string = ''): TbpHttpResponse;
    function Delete(const AUrl: string; const AHeaders: string = ''): TbpHttpResponse;
    class function FetchUrl(const AUrl: string; const AHeaders: string = ''): AnsiString;

    // streams the response body to ADest in constant memory; the returned
    // record carries status/headers with an empty Body. The body is written
    // to ADest whatever the status code, so check BpHttpResponseIsSuccess.
    // Cancellation (token or ACancel in the progress callback) raises
    // EbpHttpClientCancelled; ADest keeps whatever arrived before the abort.
    // Resume/Range: pass e.g. 'Range: bytes=1024-' in AHeaders and expect 206.
    function Download(const AUrl: string; ADest: TStream;
      AProgress: TbpHttpProgressEvent = nil; AToken: TbpCancellationToken = nil;
      const AHeaders: string = ''; const AMethod: string = 'GET'): TbpHttpResponse;
    // Download convenience that manages the file itself: the file only
    // survives when the download completed with a 2xx status; on any error,
    // cancel or non-success status the partial file is deleted
    function DownloadToFile(const AUrl, AFileName: string;
      AProgress: TbpHttpProgressEvent = nil; AToken: TbpCancellationToken = nil;
      const AHeaders: string = ''): TbpHttpResponse;

    // persistent headers sent with every request; setting a name again replaces it
    procedure AddHeader(const AName, AValue: string);
    procedure ClearHeaders;
    // preemptive Basic auth header via Base64; clears BearerToken
    procedure SetBasicAuth(const AUser, APassword: AnsiString);

    // exposed for testing; also useful on their own
    function ParseUrl(const AUrl: string; out AServerName, AResource: string;
      out APort: Integer; out ASecure: Boolean): Boolean;
    function BuildHeaders(const ARequestHeaders: string): string;
    class function MethodToString(AMethod: TbpHttpMethod): string;

    property UserAgent: string read FUserAgent write FUserAgent;
    property Username: AnsiString read FUsername write FUsername;
    property Password: AnsiString read FPassword write FPassword;
    // sent as 'Authorization: Bearer <token>' when not empty
    property BearerToken: string read FBearerToken write FBearerToken;
    property ConnectTimeout: DWORD read FConnectTimeout write FConnectTimeout;
    property SendTimeout: DWORD read FSendTimeout write FSendTimeout;
    property ReceiveTimeout: DWORD read FReceiveTimeout write FReceiveTimeout;
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;
  end;

function BpHttpResponseIsSuccess(const AResponse: TbpHttpResponse): Boolean;
// decodes the body as UTF-8 (invalid input yields an empty string)
function BpHttpResponseBodyAsUtf8(const AResponse: TbpHttpResponse): WideString;
// value of a header line from a raw CRLF header block, '' when absent
function BpHttpHeaderValue(const AHeaders, AName: string): string;
// Content-Length parsed from a raw header block; -1 when absent or invalid
function BpHttpContentLength(const AHeaders: string): Int64;
// whole percent 0..100 for a progress pair; -1 when the total is unknown
function BpHttpProgressPercent(const AReceived, ATotal: Int64): Integer;
// user-facing categorization; pass 0 for the dimension that does not apply
function BpClassifyHttpError(AWinInetError: DWORD; AHttpStatus: Integer): string;

const
  // WinInet ERROR_INTERNET_OPERATION_CANCELLED, missing from D2007's WinInet.pas
  gcErrOperationCancelled = 12017;

// ==================================================================
// BpHttpDownloadTask.pas - interface
// ==================================================================

// Non-blocking HTTP(S) download for Delphi 7/2007 and later, shaped like a
// C# Task / JS Promise: configure, Start, receive OnProgress and OnComplete,
// Cancel at any point, optionally WaitFor to join. One instance is one
// download (one-shot); create a new task for a retry.
//
// The transport is the synchronous TbpHttpClient.Download running on a
// dedicated worker thread - no Application.ProcessMessages anywhere. Cancel
// works through TbpCancellationToken, which closes the WinInet request
// handle, so even a worker blocked in connect or read aborts promptly.
//
// Event threading (document of record):
// - MarshalToMainThread = True (default, for VCL apps): events are posted
//   through a hidden window and fire on the thread that created the task,
//   which must be the one running the message loop. Progress posts are
//   coalesced, so a fast download cannot flood the queue; each event
//   reports the latest byte counts. Events only fire while messages are
//   being pumped - do not combine with blocking the main thread in WaitFor
//   and expecting events first.
// - MarshalToMainThread = False (console apps, tests, own threads): events
//   fire directly on the worker thread; the handler must be thread-safe.
//
// State machine: dtsPending -> dtsRunning -> dtsSucceeded | dtsFailed |
// dtsCancelled. A non-2xx status is dtsFailed (the response record stays
// available). Results (State, Response, ErrorMessage...) are valid and
// thread-safe to read as soon as the state is terminal, independent of
// event delivery.
//
// The destructor cancels a running download, joins the worker and frees
// everything - no orphan threads, no leaked handles, whatever state the
// task died in.

type
  TbpHttpDownloadState = (dtsPending, dtsRunning, dtsSucceeded, dtsFailed,
    dtsCancelled);

  TbpHttpDownloadCompleteEvent = procedure(ASender: TObject) of object;
  TbpHttpDownloadErrorEvent = procedure(ASender: TObject;
    const AErrorMessage: string) of object;

  TbpHttpDownloadTask = class
  private
    FClient: TbpHttpClient;        // owned; configure via Client before Start
    FToken: TbpCancellationToken;  // owned
    FThread: TThread;              // owned worker, joined in Destroy
    FLock: TRTLCriticalSection;    // guards state, progress pair and results
    FUrl: string;
    FDestFileName: string;
    FDestStream: TStream;          // caller-owned; must outlive the task
    FHeaders: string;
    FMarshalToMainThread: Boolean;
    FWnd: HWND;                    // hidden marshaling window, 0 when direct
    FState: TbpHttpDownloadState;
    FReceived: Int64;
    FTotal: Int64;
    FProgressPosted: Integer;      // coalescing flag for progress posts
    FResponse: TbpHttpResponse;
    FErrorMessage: string;
    FErrorCode: DWORD;
    FHttpStatus: Integer;
    FOnProgress: TbpHttpProgressEvent;
    FOnComplete: TbpHttpDownloadCompleteEvent;
    FOnError: TbpHttpDownloadErrorEvent;
    function GetState: TbpHttpDownloadState;
    function GetReceived: Int64;
    function GetTotal: Int64;
    function GetResponse: TbpHttpResponse;
    function GetErrorMessage: string;
    function GetErrorCode: DWORD;
    function GetHttpStatus: Integer;
    procedure WndProc(var AMessage: TMessage);
    procedure HandleWorkerProgress(ASender: TObject; const AReceived,
      ATotal: Int64; var ACancel: Boolean);
    procedure FireCompletionEvents;
    procedure RunDownload;  // worker thread body
  public
    // create the task on the thread that should receive marshaled events
    // (the main thread in a VCL app); pass False to get events directly on
    // the worker thread instead
    constructor Create(AMarshalToMainThread: Boolean = True);
    destructor Destroy; override;

    // validates Url and destination, then returns immediately while the
    // download runs on the worker thread; raises EbpHttpClient when the
    // task was already started or is misconfigured
    procedure Start;
    // requests cancellation; prompt and safe from any thread, also before
    // Start. The task reaches dtsCancelled when the worker has unwound and
    // any partial file has been deleted.
    procedure Cancel;
    // joins the worker; True when the download has finished (any outcome).
    // Marshaled events still need a running message loop to fire, but all
    // result properties are valid once this returns True.
    function WaitFor(ATimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;

    // configure before Start
    property Url: string read FUrl write FUrl;
    property DestFileName: string read FDestFileName write FDestFileName;
    property DestStream: TStream read FDestStream write FDestStream;
    property Headers: string read FHeaders write FHeaders;
    // timeouts, auth, proxy behaviour, user agent: set them here
    property Client: TbpHttpClient read FClient;
    property Token: TbpCancellationToken read FToken;
    property MarshalToMainThread: Boolean read FMarshalToMainThread;

    // results, thread-safe at any time; authoritative once IsFinished
    property State: TbpHttpDownloadState read GetState;
    property Received: Int64 read GetReceived;
    property Total: Int64 read GetTotal;
    property Response: TbpHttpResponse read GetResponse;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorCode: DWORD read GetErrorCode;        // WinInet error, 0 if none
    property HttpStatus: Integer read GetHttpStatus;    // status of a failed response

    // OnProgress fires per chunk with Int64 received/total (-1 = unknown);
    // set ACancel to abort. OnError fires before OnComplete on dtsFailed.
    // OnComplete fires once on every terminal state - check State inside.
    property OnProgress: TbpHttpProgressEvent read FOnProgress write FOnProgress;
    property OnComplete: TbpHttpDownloadCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpHttpDownloadErrorEvent read FOnError write FOnError;
  end;

implementation

// ==================================================================
// BpBase64.pas - implementation
// ==================================================================

const
  gcBase64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  gcBase64UrlChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  // reverse table markers
  gcInvalid = -1;
  gcWhitespace = -2;
  gcPadding = -3;

var
  gvDecodeTable: array[0..255] of ShortInt;

procedure InitDecodeTable;
var
  i: Integer;
begin
  for i := 0 to 255 do
    gvDecodeTable[i] := gcInvalid;
  for i := 1 to 64 do
    gvDecodeTable[Ord(gcBase64Chars[i])] := i - 1;
  // url-safe alphabet decodes with the same table
  gvDecodeTable[Ord('-')] := 62;
  gvDecodeTable[Ord('_')] := 63;
  gvDecodeTable[9] := gcWhitespace;
  gvDecodeTable[10] := gcWhitespace;
  gvDecodeTable[13] := gcWhitespace;
  gvDecodeTable[32] := gcWhitespace;
  gvDecodeTable[Ord('=')] := gcPadding;
end;

function EncodeBuffer(ASource: PByte; ASize: Integer; const AAlphabet: string;
  APadded: Boolean): string;
var
  lvDest: PChar;
  lvB0, lvB1, lvB2: Byte;
  lvFull, lvRest, lvOutLen, i: Integer;
begin
  Result := '';
  if ASize <= 0 then
    Exit;
  lvFull := ASize div 3;
  lvRest := ASize mod 3;
  lvOutLen := lvFull * 4;
  if lvRest > 0 then
  begin
    if APadded then
      Inc(lvOutLen, 4)
    else
      Inc(lvOutLen, lvRest + 1);
  end;
  SetLength(Result, lvOutLen);
  lvDest := Pointer(Result);
  for i := 1 to lvFull do
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^; Inc(ASource);
    lvB2 := ASource^; Inc(ASource);
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[(((lvB1 and $0F) shl 2) or (lvB2 shr 6)) + 1];
    lvDest[3] := AAlphabet[(lvB2 and $3F) + 1];
    Inc(lvDest, 4);
  end;
  if lvRest = 1 then
  begin
    lvB0 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[((lvB0 and $03) shl 4) + 1];
    if APadded then
    begin
      lvDest[2] := '=';
      lvDest[3] := '=';
    end;
  end
  else if lvRest = 2 then
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[((lvB1 and $0F) shl 2) + 1];
    if APadded then
      lvDest[3] := '=';
  end;
end;

function Base64Encode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64Chars, True);
end;

function Base64Encode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64Chars, True);
end;

function Base64Encode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64Chars, True);
end;

function Base64UrlEncode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64UrlChars, False);
end;

function Base64UrlEncode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64UrlChars, False);
end;

function Base64UrlEncode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64UrlChars, False);
end;

function Base64Decode(const ABase64: string): TBytes;
var
  lvLen, lvOutPos, lvAccum, lvGroup, i: Integer;
  lvCode: ShortInt;
  lvCh: Char;
  lvSeenPad: Boolean;
begin
  Result := nil;
  lvLen := Length(ABase64);
  if lvLen = 0 then
    Exit;
  // upper bound, trimmed to the real size at the end
  SetLength(Result, (lvLen div 4) * 3 + 3);
  lvOutPos := 0;
  lvAccum := 0;
  lvGroup := 0;
  lvSeenPad := False;
  for i := 1 to lvLen do
  begin
    lvCh := ABase64[i];
    {$IF SizeOf(Char) > 1}
    if Ord(lvCh) > 255 then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    {$IFEND}
    lvCode := gvDecodeTable[Ord(lvCh)];
    if lvCode = gcWhitespace then
      Continue;
    if lvCode = gcPadding then
    begin
      lvSeenPad := True;
      Continue;
    end;
    if lvCode = gcInvalid then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    if lvSeenPad then
      raise EbpBase64.Create('Base64 data continues after padding');
    lvAccum := (lvAccum shl 6) or lvCode;
    Inc(lvGroup);
    if lvGroup = 4 then
    begin
      Result[lvOutPos] := (lvAccum shr 16) and $FF;
      Result[lvOutPos + 1] := (lvAccum shr 8) and $FF;
      Result[lvOutPos + 2] := lvAccum and $FF;
      Inc(lvOutPos, 3);
      lvAccum := 0;
      lvGroup := 0;
    end;
  end;
  // 2 or 3 leftover chars carry 1 or 2 bytes; a single leftover is impossible
  case lvGroup of
    1: raise EbpBase64.Create('Truncated Base64 data');
    2:
      begin
        Result[lvOutPos] := (lvAccum shr 4) and $FF;
        Inc(lvOutPos);
      end;
    3:
      begin
        Result[lvOutPos] := (lvAccum shr 10) and $FF;
        Result[lvOutPos + 1] := (lvAccum shr 2) and $FF;
        Inc(lvOutPos, 2);
      end;
  end;
  SetLength(Result, lvOutPos);
end;

function Base64DecodeStr(const ABase64: string): AnsiString;
var
  lvBytes: TBytes;
begin
  Result := '';
  lvBytes := Base64Decode(ABase64);
  if Length(lvBytes) = 0 then
    Exit;
  SetLength(Result, Length(lvBytes));
  Move(lvBytes[0], Pointer(Result)^, Length(lvBytes));
end;

// ==================================================================
// BpCancellationToken.pas - implementation
// ==================================================================

constructor TbpCancellationToken.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FNextId := 1;
end;

destructor TbpCancellationToken.Destroy;
begin
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpCancellationToken.IsCancellationRequested: Boolean;
begin
  // aligned 32-bit read is atomic; the lock is only needed on the write
  // side to order the flag against the cleanup list
  Result := FCancelled <> 0;
end;

function TbpCancellationToken.IndexOfId(AId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FCleanupIds) do
    if FCleanupIds[i] = AId then
    begin
      Result := i;
      Exit;
    end;
end;

procedure TbpCancellationToken.Cancel;
var
  i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    FCancelled := 1;
    // run in registration order, then drop everything so a later
    // UnregisterCleanup reports the cleanup as already executed
    for i := 0 to High(FCleanupProcs) do
      FCleanupProcs[i](FCleanupData[i]);
    SetLength(FCleanupProcs, 0);
    SetLength(FCleanupData, 0);
    SetLength(FCleanupIds, 0);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.RegisterCleanup(AProc: TbpCancelCleanupProc;
  AData: Pointer; out AId: Integer): Boolean;
var
  lvCount: Integer;
begin
  AId := 0;
  Result := False;
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    lvCount := Length(FCleanupProcs);
    SetLength(FCleanupProcs, lvCount + 1);
    SetLength(FCleanupData, lvCount + 1);
    SetLength(FCleanupIds, lvCount + 1);
    FCleanupProcs[lvCount] := AProc;
    FCleanupData[lvCount] := AData;
    FCleanupIds[lvCount] := FNextId;
    AId := FNextId;
    Inc(FNextId);
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.UnregisterCleanup(AId: Integer): Boolean;
var
  lvIndex, i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    lvIndex := IndexOfId(AId);
    Result := lvIndex >= 0;
    if not Result then
      Exit;
    for i := lvIndex to High(FCleanupProcs) - 1 do
    begin
      FCleanupProcs[i] := FCleanupProcs[i + 1];
      FCleanupData[i] := FCleanupData[i + 1];
      FCleanupIds[i] := FCleanupIds[i + 1];
    end;
    SetLength(FCleanupProcs, Length(FCleanupProcs) - 1);
    SetLength(FCleanupData, Length(FCleanupData) - 1);
    SetLength(FCleanupIds, Length(FCleanupIds) - 1);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

// ==================================================================
// BpHttpClient.pas - implementation
// ==================================================================

const
  gcBufferSize = 8192;
  gcDownloadBufferSize = 65536;  // bigger chunks pay off on large bodies
  gcDefaultTimeout = 8000;  // milliseconds
  gcDefaultUserAgent = 'DelphiBoostPack/1.0';

// registered with a TbpCancellationToken so Cancel aborts a blocked WinInet
// call by closing its request handle (fails over with error 12017)
procedure BpCloseInetHandleCleanup(AData: Pointer);
begin
  InternetCloseHandle(HINTERNET(AData));
end;

procedure RaiseDownloadCancelled;
begin
  raise EbpHttpClientCancelled.Create('Operation cancelled', 0,
    gcErrOperationCancelled);
end;

// appends a header line with a CRLF separator between lines
procedure AppendHeaderLine(var AHeaders: string; const ALine: string);
begin
  if ALine = '' then
    Exit;
  if AHeaders <> '' then
    AHeaders := AHeaders + #13#10;
  AHeaders := AHeaders + ALine;
end;

{ EbpHttpClient }

constructor EbpHttpClient.Create(const AMessage: string; AStatusCode: Integer;
  AWinInetError: DWORD);
begin
  inherited Create(AMessage);
  FStatusCode := AStatusCode;
  FWinInetError := AWinInetError;
end;

{ TbpHttpResponse helpers }

function BpHttpResponseIsSuccess(const AResponse: TbpHttpResponse): Boolean;
begin
  Result := (AResponse.StatusCode >= 200) and (AResponse.StatusCode < 300);
end;

function BpHttpResponseBodyAsUtf8(const AResponse: TbpHttpResponse): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if AResponse.Body = '' then
    Exit;
  // convert straight from the raw bytes so no ANSI codepage round trip happens
  lvLen := MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(AResponse.Body),
    Length(AResponse.Body), nil, 0);
  if lvLen = 0 then
    Exit;
  SetLength(Result, lvLen);
  MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(AResponse.Body),
    Length(AResponse.Body), PWideChar(Result), lvLen);
end;

function BpHttpHeaderValue(const AHeaders, AName: string): string;
var
  lvLines: TStringList;
  lvLine, lvPrefix: string;
  i, lvColon: Integer;
begin
  Result := '';
  lvPrefix := LowerCase(AName);
  lvLines := TStringList.Create;
  try
    lvLines.Text := AHeaders;
    for i := 0 to lvLines.Count - 1 do
    begin
      lvLine := lvLines[i];
      lvColon := Pos(':', lvLine);
      if lvColon = 0 then
        Continue;
      if LowerCase(Trim(Copy(lvLine, 1, lvColon - 1))) = lvPrefix then
      begin
        Result := Trim(Copy(lvLine, lvColon + 1, MaxInt));
        Exit;
      end;
    end;
  finally
    lvLines.Free;
  end;
end;

function BpHttpContentLength(const AHeaders: string): Int64;
var
  lvValue: string;
begin
  Result := -1;
  lvValue := BpHttpHeaderValue(AHeaders, 'Content-Length');
  if lvValue = '' then
    Exit;
  Result := StrToInt64Def(lvValue, -1);
  if Result < 0 then
    Result := -1;
end;

function BpHttpProgressPercent(const AReceived, ATotal: Int64): Integer;
begin
  if ATotal <= 0 then
    Result := -1
  else if AReceived <= 0 then
    Result := 0
  else if AReceived >= ATotal then
    Result := 100
  else
    Result := (AReceived * 100) div ATotal;
end;

function BpClassifyHttpError(AWinInetError: DWORD; AHttpStatus: Integer): string;
const
  // some of these are missing from D2007's WinInet.pas, so declared inline
  lcErrTimeout           = 12002;
  lcErrNameNotResolved   = 12007;
  lcErrCannotConnect     = 12029;
  lcErrConnectionReset   = 12031;
  lcErrCertDateInvalid   = 12037;
  lcErrCertCnInvalid     = 12038;
  lcErrInvalidCa         = 12045;
  lcErrSecureFailure     = 12175;
begin
  if AWinInetError <> 0 then
  begin
    case AWinInetError of
      lcErrNameNotResolved:
        Result := 'Cannot reach server (DNS or network issue)';
      lcErrTimeout:
        Result := 'Connection timed out';
      gcErrOperationCancelled:
        Result := 'Operation cancelled';
      lcErrCannotConnect:
        Result := 'Cannot connect to server';
      lcErrConnectionReset:
        Result := 'Connection lost';
      lcErrCertDateInvalid, lcErrCertCnInvalid, lcErrInvalidCa, lcErrSecureFailure:
        Result := 'SSL/TLS certificate error';
    else
      Result := 'Network error';
    end;
    Exit;
  end;

  case AHttpStatus of
    401: Result := 'Authentication failed (invalid credentials or token?)';
    403: Result := 'Access denied (missing permission or scope?)';
    404: Result := 'Endpoint not found (check URL)';
    429: Result := 'Rate limited by server';
  else
    if (AHttpStatus >= 500) and (AHttpStatus <= 599) then
      Result := 'Server error'
    else if AHttpStatus > 0 then
      Result := Format('HTTP error %d', [AHttpStatus])
    else
      Result := 'Unknown error';
  end;
end;

{ TbpHttpClient }

constructor TbpHttpClient.Create;
begin
  inherited Create;
  FUserAgent := gcDefaultUserAgent;
  FConnectTimeout := gcDefaultTimeout;
  FSendTimeout := gcDefaultTimeout;
  FReceiveTimeout := gcDefaultTimeout;
  FFollowRedirects := True;
  FHeaders := TStringList.Create;
end;

destructor TbpHttpClient.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TbpHttpClient.AddHeader(const AName, AValue: string);
begin
  FHeaders.Values[AName] := AValue;
end;

procedure TbpHttpClient.ClearHeaders;
begin
  FHeaders.Clear;
end;

procedure TbpHttpClient.SetBasicAuth(const AUser, APassword: AnsiString);
begin
  FBearerToken := '';
  AddHeader('Authorization', 'Basic ' + Base64Encode(AUser + ':' + APassword));
end;

class function TbpHttpClient.MethodToString(AMethod: TbpHttpMethod): string;
begin
  case AMethod of
    hmGet: Result := 'GET';
    hmPost: Result := 'POST';
    hmPut: Result := 'PUT';
    hmDelete: Result := 'DELETE';
  else
    Result := 'GET';
  end;
end;

function TbpHttpClient.GetWinInetErrorMessage(AErrorCode: DWORD): string;
var
  lvBuffer: array[0..1023] of Char;
  lvLen: DWORD;
begin
  lvLen := FormatMessage(
    FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_FROM_SYSTEM,
    Pointer(GetModuleHandle('wininet.dll')),
    AErrorCode,
    0,
    lvBuffer,
    Length(lvBuffer),
    nil);

  if lvLen > 0 then
  begin
    SetString(Result, lvBuffer, lvLen);
    Result := Trim(Result);
  end
  else
    Result := Format('WinInet error %d', [AErrorCode]);
end;

function TbpHttpClient.ParseUrl(const AUrl: string; out AServerName,
  AResource: string; out APort: Integer; out ASecure: Boolean): Boolean;
var
  lvComponents: TURLComponents;
  lvHostBuffer: array[0..INTERNET_MAX_HOST_NAME_LENGTH] of Char;
  lvPathBuffer: array[0..INTERNET_MAX_PATH_LENGTH] of Char;
  lvExtraBuffer: array[0..INTERNET_MAX_PATH_LENGTH] of Char;
begin
  Result := False;

  ZeroMemory(@lvComponents, SizeOf(lvComponents));
  ZeroMemory(@lvHostBuffer, SizeOf(lvHostBuffer));
  ZeroMemory(@lvPathBuffer, SizeOf(lvPathBuffer));
  ZeroMemory(@lvExtraBuffer, SizeOf(lvExtraBuffer));

  lvComponents.dwStructSize := SizeOf(lvComponents);
  lvComponents.lpszHostName := @lvHostBuffer[0];
  lvComponents.dwHostNameLength := Length(lvHostBuffer);
  lvComponents.lpszUrlPath := @lvPathBuffer[0];
  lvComponents.dwUrlPathLength := Length(lvPathBuffer);
  lvComponents.lpszExtraInfo := @lvExtraBuffer[0];
  lvComponents.dwExtraInfoLength := Length(lvExtraBuffer);

  if not InternetCrackUrl(PChar(AUrl), Length(AUrl), 0, lvComponents) then
    Exit;

  AServerName := lvComponents.lpszHostName;
  // keep the query string attached to the resource
  AResource := string(lvComponents.lpszUrlPath) + string(lvComponents.lpszExtraInfo);
  if AResource = '' then
    AResource := '/';

  APort := lvComponents.nPort;
  ASecure := lvComponents.nScheme = INTERNET_SCHEME_HTTPS;

  if APort = 0 then
  begin
    if ASecure then
      APort := INTERNET_DEFAULT_HTTPS_PORT
    else
      APort := INTERNET_DEFAULT_HTTP_PORT;
  end;

  Result := True;
end;

function TbpHttpClient.BuildHeaders(const ARequestHeaders: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FHeaders.Count - 1 do
    AppendHeaderLine(Result, FHeaders.Names[i] + ': ' + FHeaders.ValueFromIndex[i]);
  if FBearerToken <> '' then
    AppendHeaderLine(Result, 'Authorization: Bearer ' + FBearerToken);
  AppendHeaderLine(Result, Trim(ARequestHeaders));
end;

function TbpHttpClient.CreateSession: HINTERNET;
var
  lvErr: DWORD;
begin
  Result := InternetOpen(
    PChar(FUserAgent),
    INTERNET_OPEN_TYPE_PRECONFIG,
    nil,
    nil,
    0);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to initialize HTTP session: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;

  ApplyTimeouts(Result);
end;

function TbpHttpClient.CreateConnection(ASession: HINTERNET;
  const AServerName: string; APort: Integer): HINTERNET;
var
  lvErr: DWORD;
begin
  Result := InternetConnect(
    ASession,
    PChar(AServerName),
    APort,
    nil,
    nil,
    INTERNET_SERVICE_HTTP,
    0,
    0);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      Format('Failed to connect to %s:%d: %s',
        [AServerName, APort, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

function TbpHttpClient.CreateRequest(AConnection: HINTERNET;
  const AMethod, AResource: string; ASecure: Boolean): HINTERNET;
var
  lvFlags, lvErr: DWORD;
begin
  lvFlags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE;

  if ASecure then
    lvFlags := lvFlags or INTERNET_FLAG_SECURE;

  if not FFollowRedirects then
    lvFlags := lvFlags or INTERNET_FLAG_NO_AUTO_REDIRECT;

  Result := HttpOpenRequest(
    AConnection,
    PChar(AMethod),
    PChar(AResource),
    nil,  // nil version defaults to HTTP/1.1 on any non-ancient Windows
    nil,
    nil,
    lvFlags,
    0);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      Format('Failed to create HTTP request for %s: %s',
        [AResource, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

procedure TbpHttpClient.ApplyTimeouts(AHandle: HINTERNET);
begin
  if FConnectTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_CONNECT_TIMEOUT,
      @FConnectTimeout, SizeOf(FConnectTimeout));

  if FSendTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_SEND_TIMEOUT,
      @FSendTimeout, SizeOf(FSendTimeout));

  if FReceiveTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_RECEIVE_TIMEOUT,
      @FReceiveTimeout, SizeOf(FReceiveTimeout));
end;

procedure TbpHttpClient.ApplyAuthentication(ARequest: HINTERNET);
begin
  // WinInet-level credentials, also used for proxy and 401 challenges
  if FUsername <> '' then
    InternetSetOption(ARequest, INTERNET_OPTION_USERNAME,
      @FUsername[1], Length(FUsername));

  if FPassword <> '' then
    InternetSetOption(ARequest, INTERNET_OPTION_PASSWORD,
      @FPassword[1], Length(FPassword));
end;

procedure TbpHttpClient.SendHttpRequest(ARequest: HINTERNET;
  const AHeaders: string; const ABody: AnsiString);
var
  lvHeadersPtr: PChar;
  lvHeadersLen: DWORD;
  lvBodyPtr: Pointer;
  lvBodyLen, lvErr: DWORD;
begin
  if AHeaders <> '' then
  begin
    lvHeadersPtr := PChar(AHeaders);
    lvHeadersLen := Length(AHeaders);
  end
  else
  begin
    lvHeadersPtr := nil;
    lvHeadersLen := 0;
  end;

  if Length(ABody) > 0 then
  begin
    lvBodyPtr := @ABody[1];
    lvBodyLen := Length(ABody);
  end
  else
  begin
    lvBodyPtr := nil;
    lvBodyLen := 0;
  end;

  if not HttpSendRequest(ARequest, lvHeadersPtr, lvHeadersLen,
    lvBodyPtr, lvBodyLen) then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to send HTTP request: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;
end;

function TbpHttpClient.ReadResponseStatus(ARequest: HINTERNET): Integer;
var
  lvStatusCode, lvBufferLen, lvReserved, lvErr: DWORD;
begin
  lvBufferLen := SizeOf(lvStatusCode);
  lvReserved := 0;

  if not HttpQueryInfo(
    ARequest,
    HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
    @lvStatusCode,
    lvBufferLen,
    lvReserved) then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to query HTTP status code: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;

  Result := lvStatusCode;
end;

function TbpHttpClient.ReadResponseHeaders(ARequest: HINTERNET): string;
var
  lvSize, lvReserved: DWORD;
begin
  Result := '';
  lvSize := 0;
  lvReserved := 0;

  // first call just reports the required buffer size
  if HttpQueryInfo(ARequest, HTTP_QUERY_RAW_HEADERS_CRLF, nil, lvSize, lvReserved) then
    Exit;
  if GetLastError <> ERROR_INSUFFICIENT_BUFFER then
    Exit;

  SetLength(Result, lvSize div SizeOf(Char));
  if HttpQueryInfo(ARequest, HTTP_QUERY_RAW_HEADERS_CRLF, PChar(Result),
    lvSize, lvReserved) then
    SetLength(Result, lvSize div SizeOf(Char))
  else
    Result := '';
end;

function TbpHttpClient.ReadResponseBody(ARequest: HINTERNET): AnsiString;
var
  lvBuffer: array[0..gcBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    repeat
      if not InternetReadFile(ARequest, @lvBuffer[0], gcBufferSize, lvBytesRead) then
      begin
        lvErr := GetLastError;
        raise EbpHttpClient.Create(
          'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
          0, lvErr);
      end;

      if lvBytesRead > 0 then
        lvStream.WriteBuffer(lvBuffer[0], lvBytesRead);
    until lvBytesRead = 0;

    SetLength(Result, lvStream.Size);
    if lvStream.Size > 0 then
    begin
      lvStream.Position := 0;
      lvStream.ReadBuffer(Result[1], lvStream.Size);
    end;
  finally
    lvStream.Free;
  end;
end;

procedure TbpHttpClient.ReadBodyToStream(ARequest: HINTERNET; ADest: TStream;
  const ATotal: Int64; AProgress: TbpHttpProgressEvent;
  AToken: TbpCancellationToken);
var
  lvBuffer: array[0..gcDownloadBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvReceived: Int64;
  lvCancel: Boolean;
begin
  lvReceived := 0;
  if Assigned(AProgress) then
  begin
    // headers are in; announce the total before the first byte
    lvCancel := False;
    AProgress(Self, 0, ATotal, lvCancel);
    if lvCancel then
      RaiseDownloadCancelled;
  end;

  repeat
    if (AToken <> nil) and AToken.IsCancellationRequested then
      RaiseDownloadCancelled;

    if not InternetReadFile(ARequest, @lvBuffer[0], gcDownloadBufferSize,
      lvBytesRead) then
    begin
      lvErr := GetLastError;
      raise EbpHttpClient.Create(
        'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
        0, lvErr);
    end;

    if lvBytesRead > 0 then
    begin
      ADest.WriteBuffer(lvBuffer[0], lvBytesRead);
      Inc(lvReceived, lvBytesRead);
      if Assigned(AProgress) then
      begin
        lvCancel := False;
        AProgress(Self, lvReceived, ATotal, lvCancel);
        if lvCancel then
          RaiseDownloadCancelled;
      end;
    end;
  until lvBytesRead = 0;
end;

function TbpHttpClient.Download(const AUrl: string; ADest: TStream;
  AProgress: TbpHttpProgressEvent; AToken: TbpCancellationToken;
  const AHeaders: string; const AMethod: string): TbpHttpResponse;
var
  lvSession, lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure, lvOwnsRequest: Boolean;
  lvCleanupId: Integer;
begin
  if ADest = nil then
    raise EbpHttpClient.Create('Download destination stream is nil');
  if (AToken <> nil) and AToken.IsCancellationRequested then
    RaiseDownloadCancelled;
  if not ParseUrl(AUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + AUrl);

  lvSession := CreateSession;
  try
    lvConnection := CreateConnection(lvSession, lvServerName, lvPort);
    try
      lvRequest := CreateRequest(lvConnection, AMethod, lvResource, lvSecure);
      // hand the request handle to the token: Cancel closes it, which makes
      // a blocked connect/read fail over immediately with error 12017
      lvOwnsRequest := True;
      lvCleanupId := 0;
      if AToken <> nil then
        if not AToken.RegisterCleanup(BpCloseInetHandleCleanup, lvRequest,
          lvCleanupId) then
        begin
          // cancelled between the check above and here
          InternetCloseHandle(lvRequest);
          RaiseDownloadCancelled;
        end;
      try
        try
          ApplyAuthentication(lvRequest);
          SendHttpRequest(lvRequest, BuildHeaders(AHeaders), '');

          Result.StatusCode := ReadResponseStatus(lvRequest);
          Result.Headers := ReadResponseHeaders(lvRequest);
          Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
          Result.Body := '';
          Result.ContentLength := BpHttpContentLength(Result.Headers);

          ReadBodyToStream(lvRequest, ADest, Result.ContentLength, AProgress,
            AToken);
        except
          // a WinInet failure caused by Cancel closing the handle surfaces
          // as the typed cancellation, not as a generic network error
          on E: EbpHttpClient do
            if (AToken <> nil) and AToken.IsCancellationRequested and
              not (E is EbpHttpClientCancelled) then
              RaiseDownloadCancelled
            else
              raise;
        end;
      finally
        if AToken <> nil then
          lvOwnsRequest := AToken.UnregisterCleanup(lvCleanupId);
        if lvOwnsRequest then
          InternetCloseHandle(lvRequest);
      end;
    finally
      InternetCloseHandle(lvConnection);
    end;
  finally
    InternetCloseHandle(lvSession);
  end;
end;

function TbpHttpClient.DownloadToFile(const AUrl, AFileName: string;
  AProgress: TbpHttpProgressEvent; AToken: TbpCancellationToken;
  const AHeaders: string): TbpHttpResponse;
var
  lvFile: TFileStream;
  lvKeep: Boolean;
begin
  lvKeep := False;
  lvFile := TFileStream.Create(AFileName, fmCreate);
  try
    Result := Download(AUrl, lvFile, AProgress, AToken, AHeaders);
    lvKeep := BpHttpResponseIsSuccess(Result);
  finally
    lvFile.Free;
    // never leave a partial or error-page file behind
    if not lvKeep then
      SysUtils.DeleteFile(AFileName);
  end;
end;

function TbpHttpClient.Execute(const AUrl: string; AMethod: TbpHttpMethod;
  const AHeaders: string; const ABody: AnsiString): TbpHttpResponse;
var
  lvSession, lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  if not ParseUrl(AUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + AUrl);

  lvSession := CreateSession;
  try
    lvConnection := CreateConnection(lvSession, lvServerName, lvPort);
    try
      lvRequest := CreateRequest(lvConnection, MethodToString(AMethod),
        lvResource, lvSecure);
      try
        ApplyAuthentication(lvRequest);
        SendHttpRequest(lvRequest, BuildHeaders(AHeaders), ABody);

        Result.StatusCode := ReadResponseStatus(lvRequest);
        Result.Headers := ReadResponseHeaders(lvRequest);
        Result.ContentLength := BpHttpContentLength(Result.Headers);
        Result.Body := ReadResponseBody(lvRequest);
        Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
      finally
        InternetCloseHandle(lvRequest);
      end;
    finally
      InternetCloseHandle(lvConnection);
    end;
  finally
    InternetCloseHandle(lvSession);
  end;
end;

function TbpHttpClient.Get(const AUrl: string;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmGet, AHeaders, '');
end;

function TbpHttpClient.Post(const AUrl: string; const ABody: AnsiString;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPost, AHeaders, ABody);
end;

function TbpHttpClient.PostJson(const AUrl: string;
  const AJson: AnsiString): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPost, 'Content-Type: application/json', AJson);
end;

function TbpHttpClient.Put(const AUrl: string; const ABody: AnsiString;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPut, AHeaders, ABody);
end;

function TbpHttpClient.Delete(const AUrl: string;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmDelete, AHeaders, '');
end;

class function TbpHttpClient.FetchUrl(const AUrl: string;
  const AHeaders: string): AnsiString;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  lvClient := TbpHttpClient.Create;
  try
    lvResponse := lvClient.Get(AUrl, AHeaders);
    Result := lvResponse.Body;
  finally
    lvClient.Free;
  end;
end;

// ==================================================================
// BpHttpDownloadTask.pas - implementation
// ==================================================================

const
  gcWmTaskProgress = WM_APP + 1;
  gcWmTaskDone = WM_APP + 2;

type
  // thin shell; the logic lives in TbpHttpDownloadTask.RunDownload
  TbpDownloadThread = class(TThread)
  private
    FTask: TbpHttpDownloadTask;
  protected
    procedure Execute; override;
  public
    constructor Create(ATask: TbpHttpDownloadTask);
  end;

constructor TbpDownloadThread.Create(ATask: TbpHttpDownloadTask);
begin
  FTask := ATask;
  FreeOnTerminate := False;  // the task owns and joins the thread
  inherited Create(False);
end;

procedure TbpDownloadThread.Execute;
begin
  FTask.RunDownload;
end;

{ TbpHttpDownloadTask }

constructor TbpHttpDownloadTask.Create(AMarshalToMainThread: Boolean);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FClient := TbpHttpClient.Create;
  FToken := TbpCancellationToken.Create;
  FState := dtsPending;
  FTotal := -1;
  FMarshalToMainThread := AMarshalToMainThread;
  if FMarshalToMainThread then
    FWnd := Classes.AllocateHWnd(WndProc);
end;

destructor TbpHttpDownloadTask.Destroy;
begin
  // abort and join first: the worker touches FClient/FToken/fields
  FToken.Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  if FWnd <> 0 then
    Classes.DeallocateHWnd(FWnd);  // pending posted messages are discarded
  FToken.Free;
  FClient.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpHttpDownloadTask.GetState: TbpHttpDownloadState;
begin
  EnterCriticalSection(FLock);
  Result := FState;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetReceived: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FReceived;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetTotal: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FTotal;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetResponse: TbpHttpResponse;
begin
  EnterCriticalSection(FLock);
  Result := FResponse;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorMessage: string;
begin
  EnterCriticalSection(FLock);
  Result := FErrorMessage;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorCode: DWORD;
begin
  EnterCriticalSection(FLock);
  Result := FErrorCode;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetHttpStatus: Integer;
begin
  EnterCriticalSection(FLock);
  Result := FHttpStatus;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.IsFinished: Boolean;
begin
  Result := GetState in [dtsSucceeded, dtsFailed, dtsCancelled];
end;

procedure TbpHttpDownloadTask.Start;
begin
  if FUrl = '' then
    raise EbpHttpClient.Create('Download task has no Url');
  if (FDestFileName = '') and (FDestStream = nil) then
    raise EbpHttpClient.Create('Download task has no destination (set DestFileName or DestStream)');
  if (FDestFileName <> '') and (FDestStream <> nil) then
    raise EbpHttpClient.Create('Download task has both DestFileName and DestStream; set only one');

  EnterCriticalSection(FLock);
  try
    if FState <> dtsPending then
      raise EbpHttpClient.Create('Download task already started');
    FState := dtsRunning;
  finally
    LeaveCriticalSection(FLock);
  end;

  FThread := TbpDownloadThread.Create(Self);
end;

procedure TbpHttpDownloadTask.Cancel;
begin
  FToken.Cancel;
end;

function TbpHttpDownloadTask.WaitFor(ATimeoutMs: DWORD): Boolean;
begin
  if FThread = nil then
    Result := IsFinished  // never started
  else
    Result := WaitForSingleObject(FThread.Handle, ATimeoutMs) = WAIT_OBJECT_0;
end;

// worker thread: progress from the sync core. Direct mode forwards to the
// user handler as-is; marshaled mode stores the counters and posts at most
// one pending notification.
procedure TbpHttpDownloadTask.HandleWorkerProgress(ASender: TObject;
  const AReceived, ATotal: Int64; var ACancel: Boolean);
begin
  EnterCriticalSection(FLock);
  FReceived := AReceived;
  FTotal := ATotal;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
  begin
    if InterlockedExchange(FProgressPosted, 1) = 0 then
      PostMessage(FWnd, gcWmTaskProgress, 0, 0);
  end
  else if Assigned(FOnProgress) then
    FOnProgress(Self, AReceived, ATotal, ACancel);
end;

// main thread (marshaled mode only)
procedure TbpHttpDownloadTask.WndProc(var AMessage: TMessage);
var
  lvReceived, lvTotal: Int64;
  lvCancel: Boolean;
begin
  case AMessage.Msg of
    gcWmTaskProgress:
      begin
        InterlockedExchange(FProgressPosted, 0);
        if Assigned(FOnProgress) then
        begin
          EnterCriticalSection(FLock);
          lvReceived := FReceived;
          lvTotal := FTotal;
          LeaveCriticalSection(FLock);
          lvCancel := False;
          FOnProgress(Self, lvReceived, lvTotal, lvCancel);
          if lvCancel then
            Cancel;
        end;
      end;
    gcWmTaskDone:
      FireCompletionEvents;
  else
    AMessage.Result := DefWindowProc(FWnd, AMessage.Msg, AMessage.WParam,
      AMessage.LParam);
  end;
end;

procedure TbpHttpDownloadTask.FireCompletionEvents;
begin
  if (GetState = dtsFailed) and Assigned(FOnError) then
    FOnError(Self, GetErrorMessage);
  if Assigned(FOnComplete) then
    FOnComplete(Self);
end;

procedure TbpHttpDownloadTask.RunDownload;
var
  lvResponse: TbpHttpResponse;
  lvState: TbpHttpDownloadState;
  lvErrorMessage: string;
  lvErrorCode: DWORD;
  lvHttpStatus: Integer;
begin
  lvErrorMessage := '';
  lvErrorCode := 0;
  lvHttpStatus := 0;
  // an exception path leaves lvResponse unassigned; keep it defined
  lvResponse.StatusCode := 0;
  lvResponse.StatusText := '';
  lvResponse.Headers := '';
  lvResponse.Body := '';
  lvResponse.ContentLength := -1;
  try
    if FDestFileName <> '' then
      lvResponse := FClient.DownloadToFile(FUrl, FDestFileName,
        HandleWorkerProgress, FToken, FHeaders)
    else
      lvResponse := FClient.Download(FUrl, FDestStream,
        HandleWorkerProgress, FToken, FHeaders);

    if BpHttpResponseIsSuccess(lvResponse) then
      lvState := dtsSucceeded
    else
    begin
      lvState := dtsFailed;
      lvHttpStatus := lvResponse.StatusCode;
      lvErrorMessage := BpClassifyHttpError(0, lvResponse.StatusCode);
    end;
  except
    on E: EbpHttpClientCancelled do
    begin
      lvState := dtsCancelled;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
    end;
    on E: EbpHttpClient do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
      lvHttpStatus := E.StatusCode;
    end;
    on E: Exception do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
    end;
  end;

  // publish results before the state turns terminal, then notify
  EnterCriticalSection(FLock);
  FResponse := lvResponse;
  FErrorMessage := lvErrorMessage;
  FErrorCode := lvErrorCode;
  FHttpStatus := lvHttpStatus;
  FState := lvState;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
    PostMessage(FWnd, gcWmTaskDone, 0, 0)
  else
    FireCompletionEvents;
end;

initialization
  // from BpBase64.pas
  InitDecodeTable;

end.
