
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"
#import "SULog.h"

#import "NSURL+SUAdditions.h"
#import "NSFileManager+SUAdditions.h"

#define	LONG_INSTALLATION_TIME			5				// If the Installation takes longer than this time the Application Icon is shown in the Dock so that the user has some feedback.
#define	CHECK_FOR_PARENT_TO_QUIT_TIME	.5				// Time this app uses to recheck if the parent has already died.
										
@interface TerminationListener : NSObject
{
	NSFileManager	*_fileManager;
	NSURL			*_hostURL;
	NSURL			*_executableURL;
	pid_t           _parentPID;
	NSURL			*_folderURL;
	NSURL			*_selfURL;
	NSURL			*_installationURL;

	NSTimer			*_watchdogTimer;
	NSTimer			*_longInstallationTimer;
	SUHost			*_host;
	BOOL            _shouldRelaunch;
	BOOL			_shouldShowUI;
}

- (void) parentHasQuit;

- (void) relaunch;
- (void) install;

- (void) showAppIconInDock:(NSTimer *)aTimer;
- (void) watchdog:(NSTimer *)aTimer;

@end

@implementation TerminationListener

- (instancetype)initWithHostURL:(NSURL *)hostURL executableURL:(NSURL *)executableURL parentPID:(pid_t)parentPID folderURL:(NSURL *)folderURL shouldRelaunch:(BOOL)shouldRelaunch shouldShowUI:(BOOL)shouldShowUI selfURL:(NSURL *)selfURL
{
	if( !(self = [super init]) )
		return nil;

	_hostURL		= hostURL;
	_executableURL	= executableURL;
	_parentPID      = parentPID;
	_folderURL		= folderURL;
	_selfURL		= selfURL;
	_shouldRelaunch = shouldRelaunch;
	_shouldShowUI   = shouldShowUI;
	_fileManager = [[NSFileManager alloc] init];

	BOOL	alreadyTerminated = (getppid() == 1); // ppid is launchd (1) => parent terminated already

	if (alreadyTerminated) {
		[self parentHasQuit];
	} else {
		_watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:CHECK_FOR_PARENT_TO_QUIT_TIME target:self selector:@selector(watchdog:) userInfo:nil repeats:YES];
	}

	return self;
}

- (void)dealloc
{
	[_longInstallationTimer invalidate];
}

- (void)parentHasQuit
{
	[_watchdogTimer invalidate];
	_longInstallationTimer = [NSTimer scheduledTimerWithTimeInterval: LONG_INSTALLATION_TIME
								target: self selector: @selector(showAppIconInDock:)
								userInfo:nil repeats:NO];

	if (_folderURL)
		[self install];
	else
		[self relaunch];
}

- (void) watchdog:(NSTimer *)aTimer
{
	if (![NSRunningApplication runningApplicationWithProcessIdentifier:_parentPID]) {
		[self parentHasQuit];
}
}

- (void)showAppIconInDock:(NSTimer *)aTimer;
{
	ProcessSerialNumber		psn = { 0, kCurrentProcess };
	TransformProcessType( &psn, kProcessTransformToForegroundApplication );
}

- (void) relaunch
{
    if (_shouldRelaunch) {
		NSURL *appURL = (!_folderURL || ![_executableURL isEqual:_hostURL]) ? _executableURL : _installationURL;
        [NSWorkspace.sharedWorkspace launchApplicationAtURL:appURL options:0 configuration:nil error:NULL];
    }

    if (_folderURL) {
        NSError *theError = nil;
		if (![_fileManager su_removeItemAtURLWithAuthentication:SUInstaller.updateFolderURL error:&theError]) {
			SULog( @"Couldn't remove update folder: %@.", theError);
		}
    }

    [_fileManager removeItemAtURL:_selfURL error:NULL];

	exit(EXIT_SUCCESS);
}


- (void) install
{
	NSBundle *theBundle = [NSBundle bundleWithURL:_hostURL];
	_host = [[SUHost alloc] initWithBundle: theBundle];
	_installationURL = _host.installationURL;

    if (_shouldShowUI) {
        SUStatusController*	statusCtl = [[SUStatusController alloc] initWithHost:_host];	// We quit anyway after we've installed, so leak this for now.
        [statusCtl setButtonTitle: SULocalizedString(@"Cancel Update",@"") target: nil action: Nil isDefault: NO];
        [statusCtl beginActionWithTitle: SULocalizedString(@"Installing update...",@"")
                        maxProgressValue: 0 statusText: @""];
        [statusCtl showWindow: self];
    }

	[SUInstaller installFromUpdateFolder:_folderURL overHost:_host
						 installationURL:_installationURL delegate:self
						   synchronously:NO
					   versionComparator:SUStandardVersionComparator.defaultComparator];
}

- (void) installerFinishedForHost:(SUHost *)aHost
{
	[self relaunch];
}

- (void) installerForHost:(SUHost *)host failedWithError:(NSError *)error
{
    if (_shouldShowUI)
        NSRunAlertPanel( @"", @"%@", @"OK", @"", @"", [error localizedDescription] );
	exit(EXIT_FAILURE);
}

@end

int main (int argc, const char * argv[])
{
	if( argc < 5 || argc > 7 )
		return EXIT_FAILURE;
	
	@autoreleasepool {
	
		//ProcessSerialNumber		psn = { 0, kCurrentProcess };
		//TransformProcessType( &psn, kProcessTransformToForegroundApplication );

		#if 0	// Cmdline tool
		NSURL *relativeTo = argv[0][0] != '/' ? [NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath] : nil;
		NSURL *selfURL = [NSURL su_fileURLWithFileSystemRepresentation:argv[0] isDirectory:NO relativeToURL:relativeTo];
		#else
		NSURL *selfURL = NSBundle.mainBundle.bundleURL;
		#endif

		NSApplication *app = [NSApplication sharedApplication];
		
		BOOL shouldShowUI = (argc > 6) ? atoi(argv[6]) : 1;
		if (shouldShowUI)
		{
			[app activateIgnoringOtherApps: YES];
		}

		NSURL *hostURL = (argc > 1) ? [NSURL su_fileURLWithFileSystemRepresentation:argv[1] isDirectory:YES relativeToURL:nil] : nil;
		NSURL *executableURL = (argc > 2) ? [NSURL su_fileURLWithFileSystemRepresentation:argv[2] isDirectory:NO relativeToURL:nil] : nil;
		pid_t parentProcessId = (argc > 3) ? atoi(argv[3]) : 0;
		NSURL *folderURL = (argc > 4) ? [NSURL su_fileURLWithFileSystemRepresentation:argv[4] isDirectory:NO relativeToURL:nil] : nil;
		BOOL shouldRelaunch = (argc > 5) ? atoi(argv[5]) : 1;

		TerminationListener *__unused listener = [[TerminationListener alloc] initWithHostURL:hostURL executableURL:executableURL parentPID:parentProcessId folderURL:folderURL shouldRelaunch:shouldRelaunch shouldShowUI:shouldShowUI selfURL:selfURL];

		[[NSApplication sharedApplication] run];

		return EXIT_SUCCESS;
	}
}
